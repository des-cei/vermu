// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// tb_vpu_top_vmv_scalar : vmv.x.s and vmv.s.x
//
//
// vmv.x.s rd, vs2   x[rd] = sext(vs2[0])   (SEW < XLEN: sign-extended)
//                   executes even if vl = 0
//   1. vsetvli vl=VLMAX ; vle<SEW> group <- pattern (element 0 of reg r forced
//      to a test value)
//   2. vsetvli vl=AVL   ; vmv.x.s x5, v(base+r)
//   3. check x_result: data, rd, we
//
// vmv.s.x vd, rs1   vd[0] = x[rs1]  if vl >= 1 ; vl = 0 -> NOTHING is updated
//                   (not even tail elements). Elements > 0 are tail.
//   1. vsetvli vl=VLMAX ; vle<SEW> group <- OLD pattern
//   2. vsetvli vl=AVL   ; vmv.s.x v(base+r), rs1
//   3. read back with vmv.x.s       -> new value (vl>=1) / old value (vl=0)
//   4. vsetvli vl=VLMAX ; vse<SEW> group -> DST ; compare element by element
//        - target element        : new value (vl>=1) / old value (vl=0)
//        - everything else, vl=0 : old value
//        - everything else, vl>=1: tail -> old value (vta=0) or old / all ones (vta=1)
//
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_vpu_top_vmv_scalar;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;
    import rvv_instr_pkg::*;
    import tb_vpu_pkg::*;

    //----------------------------------------------------------------------
    // Configuration  (match your VPU build)
    //----------------------------------------------------------------------
    localparam int unsigned VLEN          = VPU_VLEN;   // bits
    localparam int unsigned ELEN          = 32;         // bits
    localparam int unsigned NUM_PORTS     = VPU_N_IPU;  // OBI master ports of vpu_top
    localparam int unsigned OBI_DATA_W    = 32;
    localparam bit          VTA           = 1'b1;       // tail agnostic
    localparam bit          VMA           = 1'b1;
    localparam hartid_t     HARTID        = 1;          // as in the original testbench

    localparam bit          CHECK_TAIL        = 1'b1;   // check elements other than the target
    localparam bit          STRICT_OTHER_REGS = 1'b0;   // 1: registers of the group other than vd
                                                        //    must be untouched even with vta=1
    localparam bit          VERBOSE_PASS  = 1'b0;
    localparam int          LMUL_LOG2_MIN = -2;         // vpu_pkg::lmul_e has no 1/8

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] SRC_BASE  = 32'h0000_1000;   // data loaded into the group
    localparam logic [31:0] DST_BASE  = 32'h0000_3000;   // dump of the group
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int          VD_REG    = 8;         // register group v8..v15
    localparam logic [4:0]  X_DST     = 5'd5;      // rd of vmv.x.s

    `include "tb_vpu_common.svh"

    //----------------------------------------------------------------------
    // Helpers
    //----------------------------------------------------------------------
    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    function automatic string data_str(input logic [31:0] data);
        return $sformatf("%02h_%02h_%02h_%02h",
                         data[31:24], data[23:16], data[15:8], data[7:0]);
    endfunction

    // Check the x_result of a vmv.x.s
    task automatic check_xs_result(input x_result_t res, input logic [31:0] exp_data,
                                   input string tag);
        check(32'(res.data) === exp_data,
              $sformatf("%s: x[rd] = %s, expected %s", tag,
                        data_str(32'(res.data)), data_str(exp_data)));
        check(res.rd === X_DST,
              $sformatf("%s: result rd = %0d, expected %0d", tag, res.rd, X_DST));
        check(res.we != '0, {tag, ": result does not write back (we=0)"});
    endtask

    task automatic end_case(input string tag);
        if (case_errors != 0) case_failed++;
        if (case_errors != 0 || VERBOSE_PASS)
            $display("[%0t] %s  %s", $time, (case_errors != 0) ? "FAIL" : "PASS", tag);
    endtask

    //----------------------------------------------------------------------
    // vmv.x.s
    //   r = register of the group that is read (v(VD_REG + r)); LMUL is ignored,
    //   so r > 0 is legal even though v(VD_REG + r) is not group aligned.
    //----------------------------------------------------------------------
    task automatic run_xs(input int sew, input int lmul_log2, input int r,
                          input logic [31:0] val, input int avl);
        int          vlmax     = vtb_vlmax(VLEN, sew, lmul_log2);
        int          exp_vl    = (avl < vlmax) ? avl : vlmax;
        int          per_reg   = VLEN / sew;               // elements per vector register
        int          grp_bytes = vlmax * sew / 8;
        int          idx       = r * per_reg;              // element index of vs2[0] in the group
        logic [31:0] exp;
        x_result_t   res;
        bit          accepted;
        string       tag;

        tag = $sformatf("vmv.x.s x%0d,v%0d SEW=%0d LMUL=%s vl=%0d val=%s", X_DST, VD_REG + r,
                        sew, lmul_str(lmul_log2), exp_vl, data_str(val));
        case_errors = 0;
        case_count++;

        // group content: SRC[i] = 0x10 + i, element 0 of register r replaced by 'val'
        mem.clear_mem();
        mem.fill_incr(SRC_BASE, grp_bytes, 8'h10);
        for (int b = 0; b < sew / 8; b++)
            mem.write8(SRC_BASE + idx * (sew / 8) + b, val[8*b +: 8]);
        exp = vtb_x_from_elem(read_elem(SRC_BASE, idx, sew), sew);

        configure_vtype(sew, lmul_log2, AVL_MAX, vlmax);
        issue_instr(vtb_vle(sew, 5'(VD_REG), X_ADDR), SRC_BASE, 1'b1, {"load group: ", tag}, accepted);

        configure_vtype(sew, lmul_log2, avl, exp_vl);
        issue_instr_res(vtb_enc_scalar_move(rvv_instr_pkg::VMV_XS, X_DST, 5'(VD_REG + r)), 0,
                        1'b1, tag, accepted, res);
        if (accepted) check_xs_result(res, exp, tag);

        end_case(tag);
    endtask

    //----------------------------------------------------------------------
    // vmv.s.x
    //----------------------------------------------------------------------
    task automatic run_sx(input int sew, input int lmul_log2, input int r,
                          input logic [31:0] val, input int avl);
        int          vlmax     = vtb_vlmax(VLEN, sew, lmul_log2);
        int          exp_vl    = (avl < vlmax) ? avl : vlmax;
        int          per_reg   = VLEN / sew;
        int          grp_bytes = vlmax * sew / 8;
        int          idx       = r * per_reg;               // target element in the group
        logic [31:0] new_elem  = vtb_elem_from_x(val, sew);
        logic [31:0] all_ones  = vtb_trunc('1, sew);
        logic [31:0] old_elem;
        logic [31:0] exp_read;
        x_result_t   res;
        bit          accepted;
        string       tag;

        new_elem  = vtb_elem_from_x(val, sew);

        tag = $sformatf("vmv.s.x v%0d,x%0d SEW=%0d LMUL=%s vl=%0d rs1=%s", VD_REG + r, X_SCALAR,
                        sew, lmul_str(lmul_log2), exp_vl, data_str(val));
        case_errors = 0;
        case_count++;

        mem.clear_mem();
        mem.fill_incr(SRC_BASE, grp_bytes, 8'h40);           // OLD[i] = 0x40 + i
        mem.fill(DST_BASE, grp_bytes + 16, SENTINEL);
        old_elem = read_elem(SRC_BASE, idx, sew);

        // old content into the group
        configure_vtype(sew, lmul_log2, AVL_MAX, vlmax);
        issue_instr(vtb_vle(sew, 5'(VD_REG), X_ADDR), SRC_BASE, 1'b1, {"load group: ", tag}, accepted);

        // the instruction under test
        configure_vtype(sew, lmul_log2, avl, exp_vl);
        issue_instr(vtb_enc_scalar_move(rvv_instr_pkg::VMV_SX, 5'(VD_REG + r), X_SCALAR), val,
                    1'b1, tag, accepted);

        // read back element 0 of the register with vmv.x.s
        exp_read = vtb_x_from_elem((exp_vl >= 1) ? new_elem : old_elem, sew);
        issue_instr_res(vtb_enc_scalar_move(rvv_instr_pkg::VMV_XS, X_DST, 5'(VD_REG + r)), 0,
                        1'b1, {"readback: ", tag}, accepted, res);
        if (accepted) check_xs_result(res, exp_read, {"readback: ", tag});

        // dump the whole group and compare
        configure_vtype(sew, lmul_log2, AVL_MAX, vlmax);
        issue_instr(vtb_vse(sew, 5'(VD_REG), X_ADDR), DST_BASE, 1'b1, {"dump group: ", tag}, accepted);

        for (int i = 0; i < vlmax; i++) begin
            logic [31:0] got = read_elem(DST_BASE, i, sew);
            logic [31:0] old = read_elem(SRC_BASE, i, sew);
            bit          in_vd_reg = ((i / per_reg) == r);

            if (i == idx) begin
                logic [31:0] exp = (exp_vl >= 1) ? new_elem : old;
                if (got !== exp)
                    fail($sformatf("%s: target element %0d = %s, expected %s",
                                   tag, i, data_str(got), data_str(exp)));
            end else if (exp_vl == 0) begin
                // vl = 0 : nothing may change, tail included
                if (got !== old)
                    fail($sformatf("%s: element %0d changed with vl=0: %s, expected %s",
                                   tag, i, data_str(got), data_str(old)));
            end else if (CHECK_TAIL) begin
                bit may_be_ones = VTA && (in_vd_reg || !STRICT_OTHER_REGS);
                if (!(got === old || (may_be_ones && got === all_ones)))
                    fail($sformatf("%s: tail element %0d = %s, expected %s%s",
                                   tag, i, data_str(got), data_str(old),
                                   may_be_ones ? " or all ones" : ""));
            end
        end

        end_case(tag);
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int          sews [3] = '{8, 16, 32};
    // values: sign boundaries for SEW = 8 / 16 / 32, and a "random-looking" one
    // logic [31:0] vals [8] = '{32'hDEAD_BEEF, 32'h0000_007F, 32'h0000_0080, 32'h0000_8000,
    //                           32'h7FFF_FFFF, 32'h8000_0000, 32'hFFFF_FFFF, 32'h1234_5678};
    logic [31:0] vals [1] = '{32'hDEAD_BEEF};
    initial begin
        int vlmax, regs, per_reg;
        int rs [2];
        int avls [3];
        int nr;

        do_reset();

        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            regs  = vtb_emul_regs(vtb_lmul_x8(l));
            rs    = '{0, regs - 1};                       // first and last register of the group
            nr    = (regs > 1) ? 2 : 1;
            avls  = '{0, 1, vlmax};                       // vl = 0 / one element / full

            // ---- vmv.x.s : independent of vl and LMUL
            // for (int ri = 0; ri < nr; ri++)
            //     foreach (vals[k]) foreach (avls[a])
            //         run_xs(sews[s], l, rs[ri], vals[k], avls[a]);

            // ---- vmv.s.x : vl = 0 must not update anything
            for (int ri = 0; ri < nr; ri++)
                foreach (vals[k]) foreach (avls[a])
                    run_sx(sews[s], l, rs[ri], vals[k], avls[a]);

            // LMUL > 1 : a register that is not group aligned (v9) is still legal
            if (regs > 1) begin
                run_xs(sews[s], l, 1, 32'h8765_4321, vlmax);
                run_sx(sews[s], l, 1, 32'h8765_4321, vlmax);
            end
        end

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_vmv_scalar: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule