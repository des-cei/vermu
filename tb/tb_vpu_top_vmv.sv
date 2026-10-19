// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// tb_vpu_top_vmv : vmv.v.v / vmv.v.x / vmv.v.i
//
// Per test point (SEW, LMUL, AVL, operand):
//   1. vsetvli  vl = VLMAX
//   2. vle<SEW> vd  <- OLD pattern          (known "previous" content of vd)
//      vle<SEW> vs1 <- SRC pattern          (vmv.v.v only)
//   3. vsetvli  vl = min(AVL, VLMAX)
//   4. vmv.v.*  vd, <vs1 | rs1 | simm5>
//   5. vsetvli  vl = VLMAX ; vse<SEW> vd -> DST   (dump the WHOLE register group)
//   6. compare DST element by element:
//        i <  vl : vs1[i] / splat(rs1) / splat(sext(simm5))
//        i >= vl : tail -> old value (vta=0) or old value / all ones (vta=1)
//
// Negative tests (LMUL > 1): vd or vs1 not aligned to the register group must be
// REJECTED by the VPU.
//
// Only the load/store path is used to observe the register file, so vle/vse
// must already work. Define VPU_VRF_BYTE in tb_vpu_top_lsu_eew.sv style if you
// also want a white-box check.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef VPU_VRF_BYTE
  `define VPU_VRF_BYTE
`endif

module tb_vpu_top_vmv;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;
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

    localparam bit          CHECK_TAIL    = 1'b1;       // check elements >= vl
    localparam bit          VERBOSE_PASS  = 1'b0;       // print a line for every passing case

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] OLD_BASE  = 32'h0000_1000;   // previous content of vd
    localparam logic [31:0] SRC_BASE  = 32'h0000_2000;   // content of vs1
    localparam logic [31:0] DST_BASE  = 32'h0000_3000;   // dump of vd
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int LMUL_LOG2_MIN = -2;   // vpu_pkg::lmul_e has no 1/8

    // Register groups (aligned for any LMUL up to 8)
    localparam int VD_REG  = 8;     // v8..v15
    localparam int VS1_REG = 16;    // v16..v23

    `include "tb_vpu_common.svh"
    `ifdef VPU_VRF_BYTE
        // Width of one fragment of the DUT's vreg = VPU_N_IPU * ELEN (set it to your DUT's value)
        localparam int VRF_FRAG_W = VPU_N_IPU * ELEN;

        // One byte of the register file, selected in two steps
        function automatic logic [7:0] vrf_byte(input int vreg_i, input int byte_i);
            logic [VRF_FRAG_W-1:0] frag;
            frag = dut.vregfile_i.vreg[vreg_i][(byte_i * 8) / VRF_FRAG_W];
            return frag[((byte_i * 8) % VRF_FRAG_W) +: 8];
        endfunction

        // Element idx (SEW bits) of the register group that starts at base_reg
        function automatic logic [31:0] vrf_elem(input int base_reg, input int idx, input int sew);
            logic [31:0] v = '0;
            for (int b = 0; b < sew / 8; b++) begin
                int n = idx * (sew / 8) + b;                              // byte number inside the group
                v[8*b +: 8] = vrf_byte(base_reg + n / (VLEN / 8), n % (VLEN / 8));

                // $display("[VMV] time=%0t | idx=%0d | sew=%0d | b=%0d | n=%0d | reg=%0d | byte_idx=%0d | data=0x%02h",
                //         $time, idx, sew, b, n,
                //         base_reg + n / (VLEN / 8),
                //         n % (VLEN / 8),
                //         v[8*b +: 8]);
            end
            return v;
        endfunction
    `endif
    //----------------------------------------------------------------------
    // Test point
    //----------------------------------------------------------------------
    typedef struct {
        rvv_instr_pkg::vec_instr_e instr;      // VMV_VV / VMV_VX / VMV_VI
        int          sew;
        int          lmul_log2;
        int          avl;
        int          vd;
        int          vs1;                      // VMV_VV only
        logic [31:0] scalar;                   // VMV_VX only : value of rs1
        logic [4:0]  simm5;                    // VMV_VI only
    } vmv_case_t;

    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    task automatic run_vmv_case(input vmv_case_t c);
        bit is_vv     = (c.instr == rvv_instr_pkg::VMV_VV);
        bit is_vx     = (c.instr == rvv_instr_pkg::VMV_VX);
        int lmul_x8   = vtb_lmul_x8(c.lmul_log2);
        bit vd_ok     = vtb_vreg_aligned(c.vd, lmul_x8);
        bit vs1_ok    = !is_vv || vtb_vreg_aligned(c.vs1, lmul_x8);
        bit legal     = vd_ok && vs1_ok;
        int vlmax     = vtb_vlmax(VLEN, c.sew, c.lmul_log2);
        int exp_vl    = vtb_expected_vl(c.avl, vlmax);
        int grp_bytes = vlmax * c.sew / 8;
        bit same_reg  = is_vv && (c.vd == c.vs1);
        logic [31:0] old_base = same_reg ? SRC_BASE : OLD_BASE;   // vd content before the vmv
        logic [4:0]  op1;
        logic [31:0] rs1_val;
        logic [31:0] splat, all_ones;
        bit          accepted;
        string       tag;
        string       name;

        case (c.instr)
            rvv_instr_pkg::VMV_VV: begin name = "vmv.v.v"; op1 = 5'(c.vs1); rs1_val = '0;      end
            rvv_instr_pkg::VMV_VX: begin name = "vmv.v.x"; op1 = X_SCALAR;  rs1_val = c.scalar; end
            default:               begin name = "vmv.v.i"; op1 = c.simm5;   rs1_val = '0;      end
        endcase

        splat     = is_vx ? vtb_elem_from_x(c.scalar, c.sew) : vtb_elem_from_simm5(c.simm5, c.sew);
        all_ones  = vtb_trunc('1, c.sew);

        tag = $sformatf("%s v%0d%s SEW=%0d LMUL=%s avl=%0d vl=%0d%s", name, c.vd,
                        is_vv ? $sformatf(",v%0d", c.vs1) : "",
                        c.sew, lmul_str(c.lmul_log2), c.avl, exp_vl,
                        is_vx ? $sformatf(" rs1=%08h", c.scalar)
                              : (is_vv ? "" : $sformatf(" simm5=%0d", $signed(c.simm5))));

        case_errors = 0;
        case_count++;

        //  memory setup
        mem.clear_mem();
        mem.fill_incr(OLD_BASE, grp_bytes, 8'h40);    // OLD[i] = 0x40 + i
        mem.fill_incr(SRC_BASE, grp_bytes, 8'h01);    // SRC[i] = 0x01 + i
        mem.fill(DST_BASE, grp_bytes + 16, SENTINEL);

        // preload vd / vs1 with known data (legal cases only)
        if (legal) begin
            configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
            if (!same_reg)
                issue_instr(vtb_vle(c.sew, 5'(c.vd), X_ADDR), OLD_BASE, 1'b1,
                            {"preload vd: ", tag}, accepted);
            if (is_vv)
                issue_instr(vtb_vle(c.sew, 5'(c.vs1), X_ADDR), SRC_BASE, 1'b1,
                            {"preload vs1: ", tag}, accepted);
        end

        //  the vmv itself, with the vl under test
        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);
        mem.clear_log();
        issue_instr(vtb_enc_opi(c.instr, 5'(c.vd), 5'd0, op1), rs1_val, legal, tag, accepted);

        if (legal && accepted) begin
            check(mem.access_log.size() == 0, {"vmv touched the bus: ", tag});

        
        `ifndef VPU_VRF_BYTE
            // dump the whole group and compare
            configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
            issue_instr(vtb_vse(c.sew, 5'(c.vd), X_ADDR), DST_BASE, 1'b1,
                        {"dump vd: ", tag}, accepted);
        `endif
            for (int i = 0; i < vlmax; i++) begin
        `ifdef VPU_VRF_BYTE
                logic [31:0] got = vrf_elem(c.vd, i, c.sew);          // straight from the DUT
        `else 
                logic [31:0] got = read_elem(DST_BASE, i, c.sew);      // through mem
        `endif 
                logic [31:0] old = read_elem(old_base, i, c.sew);
                logic [31:0] exp;
                if (i < exp_vl) begin
                    exp = is_vv ? read_elem(SRC_BASE, i, c.sew) : splat;
                    if (got !== exp) begin
                        fail($sformatf("%s: element %0d = %0h, expected %0h", tag, i, got, exp));
                        $stop;
                    end
                end else if (CHECK_TAIL) begin
                    if (!(got === old || (VTA && got === all_ones))) begin
                        fail($sformatf("%s: tail element %0d = %0h, expected %0h%s",
                                        tag, i, got, old, VTA ? " or all ones" : ""));
                        $stop;
                    end
                end
            end
        end else if (!legal && !accepted) begin
            check(mem.access_log.size() == 0, {"rejected vmv touched the bus: ", tag});
        end

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s  [%s]", $time, case_errors ? "FAIL" : "PASS", tag,
                     legal ? "legal" : (!vd_ok ? "illegal: vd misaligned" : "illegal: vs1 misaligned"));
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int          sews     [3] = '{8, 16, 32};
    logic [31:0] scalars  [5] = '{32'hDEAD_BEEF, 32'h1234_5678,
                                  32'h8000_0080, 32'h0000_00A5, 32'hFFFF_FFFF};
    logic [4:0]  simms    [5] = '{5'b10000 /*-16*/, 5'b11111 /*-1*/, 5'd0, 5'd1, 5'd15};

    initial begin
        vmv_case_t c;
        int        vlmax, regs;
        int        avls [3];

        do_reset();

        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            regs  = vtb_emul_regs(vtb_lmul_x8(l));
            avls  = '{1, vlmax / 2 + 1, vlmax};   // single element / partial / full

            foreach (avls[a]) begin
                if (avls[a] < 1) continue;

                // vmv.v.v : separate groups, plus vd == vs1 once
                c = '{instr    : rvv_instr_pkg::VMV_VV,
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : avls[a],
                      vd       : VD_REG,
                      vs1      : VS1_REG,
                      scalar   : '0,
                      simm5    : '0};
                run_vmv_case(c);
                if (a == 1) begin c.vs1 = VD_REG; run_vmv_case(c); end

                // vmv.v.x : several scalar patterns (truncation / sign checks)
                // foreach (scalars[k]) begin
                //     c = '{instr: rvv_instr_pkg::VMV_VX,
                //           sew      : sews[s],
                //           lmul_log2: l,
                //           avl      : avls[a],
                //           vd       : VD_REG,
                //           vs1      : 0,
                //           scalar   : scalars[k],
                //           simm5    : '0};
                //     run_vmv_case(c);
                // end

                // vmv.v.i : simm5 sign extension
                // foreach (simms[k]) begin
                //     c = '{instr: rvv_instr_pkg::VMV_VI,
                //            sew      : sews[s],
                //            lmul_log2: l, 
                //            avl      : avls[a],
                //            vd       : VD_REG,
                //            vs1      : 0, 
                //            scalar   : '0, 
                //            simm5    : simms[k]};
                //     run_vmv_case(c);
                // end
            end

            // Negative tests: register groups not aligned to LMUL
            if (regs > 1) begin
                c = '{instr: rvv_instr_pkg::VMV_VV,
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : vlmax,
                      vd       : VD_REG + 1,
                      vs1      : VS1_REG,
                      scalar   : '0,
                      simm5    : '0};
                run_vmv_case(c);                                   // vd misaligned
                c.vd  = VD_REG;
                c.vs1 = VS1_REG + 1;
                run_vmv_case(c);                                   // vs1 misaligned
                c = '{instr: rvv_instr_pkg::VMV_VX,
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : vlmax,
                      vd       : VD_REG + 1,
                      vs1      : 0, scalar: 32'h1, 
                      simm5    : '0};
                run_vmv_case(c);
                c = '{instr: rvv_instr_pkg::VMV_VI,
                     sew: sews[s],
                     lmul_log2: l,
                     avl: vlmax,
                     vd: VD_REG + 1, 
                     vs1: 0,
                     scalar: '0, 
                     simm5: 5'd1};
                run_vmv_case(c);
            end
        end

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_vmv: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule