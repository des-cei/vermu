// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)
// 
// Description : unit-stride vector load/store with EEW != SEW, EMUL != LMUL
//
// -----------------------------------------------------------------------------
// tb_vpu_top_lsu_eew : unit-stride vector load/store with EEW != SEW, EMUL != LMUL
//
// For every (SEW, LMUL, EEW, AVL) point the test does
//     vsetvli                      -> check the returned vl
//     vle<EEW>.v  vd,  (SRC)       -> check accept/reject, bus activity
//     [optional VRF back-door check, see VPU_VRF_BYTE below]
//     vse<EEW>.v  vd,  (DST)       -> compare DST against SRC, check guard bytes
//
// Illegal combinations (EMUL outside 1/8..8, vd not aligned to EMUL) must be
// REJECTED by the VPU (accept = 0): no result, no memory access.
// With SEW/EEW in {8,16,32}, ELEN=32 and LMUL in {1/4..8} the smallest EMUL that
// can be reached by a legal vtype is 1/4, so "EMUL too small" never shows up;
// "EMUL too large" (e.g. SEW=8, LMUL=8, EEW=32) does.
//
// Compile order: cvxif_types_pkg, obi_pkg, vpu_pkg, rvv_instr_pkg, tb_vpu_pkg, <DUT>,
//                obi_mem_model, cvxif_cpu_model, tb_vpu_top_lsu_eew
//                (tb_vpu_common.svh is included)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

// Optional white-box check of the register file. Define it to a hierarchical
// path returning byte <byte_idx> of vector register <vreg>, e.g.
`define VPU_VRF_BYTE
// Without it, only the load->store round trip is checked (a bug that is
// symmetric in load and store would then go unnoticed).
// `define VPU_VRF_BYTE(vreg, byte_idx) ...

module tb_vpu_top_lsu_eew;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;
    import tb_vpu_pkg::*;

    //----------------------------------------------------------------------
    // Configuration  (match your VPU build)
    //----------------------------------------------------------------------
    localparam int unsigned VLEN          = 128;   // bits
    localparam int unsigned ELEN          = 32;    // bits
    localparam int unsigned NUM_PORTS     = 1;     // OBI master ports of vpu_top
    localparam int unsigned OBI_DATA_W    = 32;
    localparam bit          VTA           = 1'b1;
    localparam bit          VMA           = 1'b1;
    localparam hartid_t     HARTID        = 1;     // as in the original testbench

    localparam bit          VERBOSE_PASS  = 1'b0;  // print a line for every passing case
    localparam int          LMUL_LOG2_MIN = -2;    // vpu_pkg::lmul_e has no 1/8

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] SRC_BASE  = 32'h0000_1000;
    localparam logic [31:0] DST_BASE  = 32'h0000_2000;
    localparam int unsigned GUARD     = 16;        // sentinel bytes after the store window
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    `include "tb_vpu_common.svh"
    `ifdef VPU_VRF_BYTE
        localparam int VRF_FRAG_W = VPU_N_IPU * ELEN;  
        function automatic logic [7:0] vrf_byte(input int vreg_i, input int byte_i);
            logic [VRF_FRAG_W-1:0] frag;
            frag = dut.vregfile_i.vreg[vreg_i][(byte_i * 8) / VRF_FRAG_W];
            return frag[((byte_i * 8) % VRF_FRAG_W) +: 8];
        endfunction
    `endif
    //----------------------------------------------------------------------
    // One test point
    //----------------------------------------------------------------------
    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    task automatic run_case(input vtb_lsu_case_t c);
        int  emul_x8   = vtb_emul_x8(c.sew, c.lmul_log2, c.eew);
        bit  emul_ok   = vtb_emul_legal(c.sew, c.lmul_log2, c.eew);
        bit  align_ok  = emul_ok && vtb_vreg_aligned(c.vd, emul_x8);
        bit  legal     = emul_ok && align_ok;
        int  vlmax     = vtb_vlmax(VLEN, c.sew, c.lmul_log2);
        int  exp_vl    = (c.avl < vlmax) ? c.avl : vlmax;
        int  nbytes    = exp_vl * c.eew / 8;
        int  buf_bytes = VLEN;                         // EMUL=8 -> 8 regs * VLEN/8 bytes
        bit  accepted;
        string tag;

        tag = $sformatf("SEW=%0d LMUL=%s EEW=%0d EMUL=%s vd=v%0d avl=%0d vl=%0d",
                        c.sew, lmul_str(c.lmul_log2), c.eew,
                        !emul_ok          ? "illegal" :
                        (emul_x8 >= 8)    ? $sformatf("%0d", emul_x8 / 8)
                                          : $sformatf("1/%0d", 8 / emul_x8),
                        c.vd, c.avl, exp_vl);

        case_errors = 0;
        case_count++;

        // ---------------- memory setup
        mem.clear_mem();
        mem.fill_incr(SRC_BASE, legal ? nbytes : buf_bytes, 8'h01);   // SRC[i] = i+1
        mem.fill(DST_BASE, buf_bytes + GUARD, SENTINEL);

        // ---------------- vtype / vl
        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);

        // ---------------- load
        mem.clear_log();
        issue_instr(vtb_vle(c.eew, 5'(c.vd), X_ADDR), SRC_BASE, legal,
                    {"vle: ", tag}, accepted);

        if (legal && accepted) begin
            `ifdef VPU_VRF_BYTE
                    // byte b of the group is in register vd + b/VLENB, at byte b % VLENB
                    for (int b = 0; b < nbytes; b++) begin
                        logic [7:0] got = vrf_byte(c.vd + b / (VLEN / 8), b % (VLEN / 8));
                        logic [7:0] exp = mem.read8(SRC_BASE + b);
                        if (got !== exp)
                            fail($sformatf("VRF byte %0d (v%0d): got %02h exp %02h",
                                        b, c.vd + b / (VLEN / 8), got, exp));
                    end
            `endif
            check(mem.count_writes() == 0, {"vle performed bus writes: ", tag});
            check(mem.reads_within(SRC_BASE, SRC_BASE + nbytes),
                  {"vle read outside the source window: ", tag});
            check(mem.uninit_reads == 0, {"vle read bytes beyond the source window: ", tag});

            if (VERBOSE_PASS)
                $display("    load : %0d bytes in %0d bus reads", nbytes, mem.count_reads());
        end else if (!legal && !accepted) begin
            check(mem.access_log.size() == 0, {"rejected vle still touched the bus: ", tag});
        end

        // ---------------- store back
        mem.clear_log();
        issue_instr(vtb_vse(c.eew, 5'(c.vd), X_ADDR), DST_BASE, legal,
                    {"vse: ", tag}, accepted);

        if (legal && accepted) begin
            check(mem.count_reads() == 0, {"vse performed bus reads: ", tag});
            check(mem.writes_within(DST_BASE, DST_BASE + nbytes),
                  {"vse wrote outside the destination window: ", tag});
            if (VERBOSE_PASS)
                $display("    store: %0d bytes in %0d bus writes", nbytes, mem.count_writes());

            for (int b = 0; b < nbytes + GUARD; b++) begin
                logic [7:0] exp = (b < nbytes) ? mem.read8(SRC_BASE + b) : SENTINEL;
                logic [7:0] got = mem.read8(DST_BASE + b);
                if (got !== exp)
                    fail($sformatf("DST[%0d] = %02h, expected %02h (%s)", b, got, exp,
                                   (b < nbytes) ? "data" : "guard/tail"));
            end
        end else if (!legal && !accepted) begin
            check(mem.access_log.size() == 0, {"rejected vse still touched the bus: ", tag});
            for (int b = 0; b < buf_bytes; b++)
                check(mem.read8(DST_BASE + b) === SENTINEL, "rejected vse modified memory");
        end

        if (case_errors != 0) case_failed++;
        if (case_errors != 0 || VERBOSE_PASS)
            $display("[%0t] %s  %s  [%s]", $time, (case_errors != 0) ? "FAIL" : "PASS", tag,
                     legal ? "legal" : (emul_ok ? "illegal: vd misaligned" : "illegal: EMUL"));
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int sews [3] = '{8, 16, 32};
    int eews [3] = '{8, 16, 32};

    initial begin
        vtb_lsu_case_t c;
        int  vlmax;
        int  avls [4];
        int  emul_x8;

        do_reset();

        // ---- 1. directed sanity check: the original test (SEW=32, LMUL=1, EEW=32)
        c = '{sew: 32, lmul_log2: 0, eew: 32, vd: 8, avl: 3};
        run_case(c);

        // ---- 2. sweep over SEW x LMUL x EEW x AVL
        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) foreach (eews[e]) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax   = vtb_vlmax(VLEN, sews[s], l);
            emul_x8 = vtb_emul_x8(sews[s], l, eews[e]);
            avls    = '{1, 5, vlmax / 2 + 1, vlmax};   // partial reg / odd / crossing regs / full

            foreach (avls[a]) begin
                if (avls[a] < 1) continue;
                c = '{sew: sews[s], lmul_log2: l, eew: eews[e], vd: 8, avl: avls[a]};
                run_case(c);
            end

            // vd not aligned to the EMUL register group -> must be rejected
            if (vtb_emul_legal(sews[s], l, eews[e]) && vtb_emul_regs(emul_x8) > 1) begin
                c = '{sew: sews[s], lmul_log2: l, eew: eews[e], vd: 9, avl: vlmax};
                run_case(c);
            end
        end

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_lsu_eew: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule