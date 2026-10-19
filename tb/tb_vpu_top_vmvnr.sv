// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// tb_vpu_top_vmvnr : vmv1r.v / vmv2r.v / vmv4r.v / vmv8r.v  (whole register move)
//
// vmv<nr>r.v copies NR whole registers, vs2..vs2+NR-1 -> vd..vd+NR-1. It runs
// with EEW = SEW and evl = NR*VLEN/SEW, so it ignores vl and LMUL: every byte of
// the NR registers is copied (no tail), and registers after vd+NR-1 are not touched.
//
// Per test point (NR, SEW, LMUL, AVL):
//   1. vsetvli  e8,m8 vl = VLMAX
//      vle8 v8  <- OLD pattern   (whole v8..v15  : previous content of vd group)
//      vle8 v16 <- SRC pattern   (whole v16..v23 : content of vs2 group)
//   2. vsetvli  SEW, LMUL, vl = min(AVL, VLMAX)   (includes vl = 0)
//   3. vmv<nr>r.v vd, vs2
//   4. read v8..v15 (white-box, or vse8 e8,m8 -> DST) and compare byte by byte:
//        reg <  vd+NR : SRC   (legal case)
//        otherwise    : OLD   (also for every rejected instruction)
//
// Negative tests: vd / vs2 not aligned to NR, reserved simm5 (NR not in
// {1,2,4,8}) and vm = 0 must be REJECTED, without bus traffic and without
// changing the register file.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef VPU_VRF_BYTE
  `define VPU_VRF_BYTE
`endif

module tb_vpu_top_vmvnr;

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

    localparam bit          VERBOSE_PASS  = 1'b0;       // print a line for every passing case

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] OLD_BASE  = 32'h0000_1000;   // previous content of v8..v15
    localparam logic [31:0] SRC_BASE  = 32'h0000_2000;   // content of v16..v23
    localparam logic [31:0] DST_BASE  = 32'h0000_3000;   // dump of v8..v15
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int LMUL_LOG2_MIN = -2;   // vpu_pkg::lmul_e has no 1/8

    // Register groups (aligned for NR up to 8)
    localparam int VD_REG    = 8;       // v8..v15
    localparam int VS2_REG   = 16;      // v16..v23
    localparam int GRP_REGS  = 8;       // registers observed / preloaded per group
    localparam int VREG_B    = VLEN / 8;              // bytes per vector register
    localparam int GRP_BYTES = GRP_REGS * VREG_B;     // bytes per 8-register group

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
    `endif

    //----------------------------------------------------------------------
    // Test point
    //----------------------------------------------------------------------
    typedef struct {
        int   nr;           // registers to copy (1/2/4/8 legal, anything else reserved)
        int   sew;
        int   lmul_log2;
        int   avl;
        int   vd;
        int   vs2;
        bit   vm;           // 1 = legal encoding, 0 = reserved
    } vmvnr_case_t;

    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    function automatic bit nr_legal(input int nr);
        return nr == 1 || nr == 2 || nr == 4 || nr == 8;
    endfunction

    task automatic run_vmvnr_case(input vmvnr_case_t c);
        bit  nr_ok    = nr_legal(c.nr);
        bit  vd_ok    = nr_ok && (c.vd  % c.nr == 0);
        bit  vs2_ok   = nr_ok && (c.vs2 % c.nr == 0);
        bit  legal    = nr_ok && c.vm && vd_ok && vs2_ok;
        int  vlmax    = vtb_vlmax(VLEN, c.sew, c.lmul_log2);
        int  exp_vl   = vtb_expected_vl(c.avl, vlmax);
        bit  same_reg = (c.vd == c.vs2);
        bit  accepted;
        string tag, why;

        tag = $sformatf("vmv%0dr.v v%0d,v%0d%s SEW=%0d LMUL=%s avl=%0d vl=%0d", c.nr, c.vd,
                        c.vs2, c.vm ? "" : " (vm=0)", c.sew, lmul_str(c.lmul_log2),
                        c.avl, exp_vl);
        if      (legal)   why = "legal";
        else if (!nr_ok)  why = "illegal: reserved nr";
        else if (!c.vm)   why = "illegal: vm=0";
        else if (!vd_ok)  why = "illegal: vd misaligned";
        else              why = "illegal: vs2 misaligned";

        case_errors = 0;
        case_count++;

        //  memory setup
        mem.clear_mem();
        mem.fill_incr(OLD_BASE, GRP_BYTES, 8'h80);    // OLD[i] = 0x80 + i
        mem.fill_incr(SRC_BASE, GRP_BYTES, 8'h01);    // SRC[i] = 0x01 + i
        mem.fill(DST_BASE, GRP_BYTES + 16, SENTINEL);

        // preload the whole v8..v15 and v16..v23 groups (also for rejected cases:
        // the register file must not change)
        configure_vtype(8, 3, AVL_MAX, vtb_vlmax(VLEN, 8, 3));
        issue_instr(vtb_vle(8, 5'(VD_REG), X_ADDR), OLD_BASE, 1'b1,
                    {"preload vd: ", tag}, accepted);
        issue_instr(vtb_vle(8, 5'(VS2_REG), X_ADDR), SRC_BASE, 1'b1,
                    {"preload vs2: ", tag}, accepted);

        //  the vmv<nr>r.v itself, with the vtype / vl under test
        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);
        mem.clear_log();
        issue_instr(vtb_vmv_nr_r(c.nr, 5'(c.vd), 5'(c.vs2), c.vm), '0, legal, tag, accepted);
        check(mem.access_log.size() == 0, {"vmv<nr>r.v touched the bus: ", tag});

    `ifndef VPU_VRF_BYTE
        // dump the whole v8..v15 group
        configure_vtype(8, 3, AVL_MAX, vtb_vlmax(VLEN, 8, 3));
        issue_instr(vtb_vse(8, 5'(VD_REG), X_ADDR), DST_BASE, 1'b1,
                    {"dump vd: ", tag}, accepted);
    `endif

        // compare v8..v15 byte by byte
        for (int n = 0; n < GRP_BYTES; n++) begin
            int          reg_i = VD_REG + n / VREG_B;
            logic [7:0]  old   = mem.read8(OLD_BASE + n);
            logic [7:0]  exp, got;
            bit          copied;
            copied = legal && !same_reg &&
                     reg_i >= c.vd && reg_i < c.vd + c.nr;
            // byte n of v8..v15 is copied from the same offset inside vs2's group
            exp = copied ? mem.read8(SRC_BASE + (c.vs2 - VS2_REG) * VREG_B
                                     + (reg_i - c.vd) * VREG_B + n % VREG_B)
                         : old;
    `ifdef VPU_VRF_BYTE
            got = vrf_byte(reg_i, n % VREG_B);                         // straight from the DUT
    `else
            got = mem.read8(DST_BASE + n);                             // through mem
    `endif
            if (got !== exp) begin
                fail($sformatf("%s: v%0d byte %0d = %02h, expected %02h (%s)", tag, reg_i,
                               n % VREG_B, got, exp, copied ? "copied" : "untouched"));
                $stop;
            end
        end

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s  [%s]", $time, case_errors ? "FAIL" : "PASS", tag, why);
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int sews     [3] = '{8, 16, 32};
    int nrs      [4] = '{1, 2, 4, 8};
    int bad_nrs  [7] = '{3, 5, 6, 7, 9 /*simm5=8*/, 16, 32 /*simm5=31*/};

    initial begin
        vmvnr_case_t c;
        int          vlmax;
        int          avls [3];

        do_reset();

        // vtype / vl must not change what is copied: sweep SEW x LMUL x AVL (vl = 0 included)
        foreach (nrs[r]) foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            avls  = '{0, 1, vlmax};

            foreach (avls[a]) begin
                c = '{nr: nrs[r], sew: sews[s], lmul_log2: l, avl: avls[a],
                      vd: VD_REG, vs2: VS2_REG, vm: 1'b1};
                run_vmvnr_case(c);
            end
        end

        foreach (nrs[r]) begin
            // vd == vs2 : legal, registers keep their value
            c = '{nr: nrs[r], sew: 8, lmul_log2: 0, avl: AVL_MAX,
                  vd: VD_REG, vs2: VD_REG, vm: 1'b1};
            run_vmvnr_case(c);

            // Negative tests: vd / vs2 not aligned to NR
            if (nrs[r] > 1) begin
                c = '{nr: nrs[r], sew: 8, lmul_log2: 0, avl: AVL_MAX,
                      vd: VD_REG + nrs[r] / 2, vs2: VS2_REG, vm: 1'b1};
                run_vmvnr_case(c);                                 // vd misaligned
                c.vd  = VD_REG;
                c.vs2 = VS2_REG + nrs[r] / 2;
                run_vmvnr_case(c);                                 // vs2 misaligned
            end

            // Negative test: vm = 0 is reserved
            c = '{nr: nrs[r], sew: 8, lmul_log2: 0, avl: AVL_MAX,
                  vd: VD_REG, vs2: VS2_REG, vm: 1'b0};
            run_vmvnr_case(c);
        end

        // Negative tests: simm5 that does not encode 1/2/4/8 registers
        foreach (bad_nrs[k]) begin
            c = '{nr: bad_nrs[k], sew: 8, lmul_log2: 0, avl: AVL_MAX,
                  vd: VD_REG, vs2: VS2_REG, vm: 1'b1};
            run_vmvnr_case(c);
        end

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_vmvnr: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule
