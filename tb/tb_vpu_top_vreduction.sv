// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// tb_vpu_top_vreduction : single-width integer reductions  vred<op>.vs vd, vs2, vs1
//
//   Currently tested : vredsum.vs
//   Ready for        : vredmaxu, vredmax, vredminu, vredmin, vredand, vredor, vredxor
//                      (encoder + reference model already in tb_vpu_pkg: add them to 'instrs')
//
// Per test point (instr, SEW, LMUL, AVL, vs2 pattern, vs1[0]):
//   1. vsetvli  SEW, LMUL=1, vl = VLMAX
//      vle<SEW> vd  <- OLD pattern          (known "previous" content of vd)
//      vle<SEW> vs1 <- SRC1 (element 0 = accumulator, rest = junk that must be ignored)
//   2. vsetvli  SEW, LMUL,   vl = VLMAX
//      vle<SEW> vs2 <- SRC2 pattern         (incrementing or pseudo-random)
//   3. vsetvli  SEW, LMUL,   vl = min(AVL, VLMAX)
//   4. vred<op>.vs vd, vs2, vs1
//   5. observe vd (one register, LMUL is ignored for vd/vs1) and compare:
//        vl  > 0 : vd[0] = vs1[0] OP vs2[0] OP ... OP vs2[vl-1]
//        vl == 0 : vd[0] unchanged
//        0 < i < VLEN/SEW : tail -> old value (vta=0) or old value / all ones (vta=1)
//
// RVV rules: vd and vs1 are single registers (EMUL=1) so any register number is
// legal; vs2 is a register group (EMUL=LMUL) and must be aligned to it.
//
// Negative tests (LMUL > 1): vs2 misaligned must be REJECTED, no bus traffic.
// Positive "alignment" tests (LMUL > 1): odd vd / vs1 must be ACCEPTED.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef VPU_VRF_BYTE
  `define VPU_VRF_BYTE
`endif

module tb_vpu_top_vreduction;

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
    localparam hartid_t     HARTID        = 1;

    localparam bit          CHECK_TAIL    = 1'b1;       // check vd elements 1 .. VLEN/SEW-1
    localparam bit          TEST_VL0      = 1'b1;       // include vl = 0 points (vd must be untouched)
    localparam bit          VERBOSE_PASS  = 1'b0;       // print a line for every passing case
    localparam int unsigned RAND_SEED     = 32'hC0FFEE;

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] OLD_BASE  = 32'h0000_1000;   // previous content of vd
    localparam logic [31:0] SRC1_BASE = 32'h0000_2000;   // content of vs1 (element 0 = accumulator)
    localparam logic [31:0] SRC2_BASE = 32'h0000_3000;   // content of vs2 (group)
    localparam logic [31:0] DST_BASE  = 32'h0000_4000;   // dump of vd
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int LMUL_LOG2_MIN = -2;   // vpu_pkg::lmul_e has no 1/8

    // Registers (vs2 group aligned for any LMUL up to 8)
    localparam int VD_REG  = 8;
    localparam int VS1_REG = 4;
    localparam int VS2_REG = 16;    // v16..v23

    // vs2 data patterns
    typedef enum int { PAT_INCR, PAT_RAND } pattern_e;

    `include "tb_vpu_common.svh"
    `ifdef VPU_VRF_BYTE
        // Width of one fragment of the DUT's vreg = VPU_N_IPU * ELEN
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
            end
            return v;
        endfunction
    `endif

    //----------------------------------------------------------------------
    // Test point
    //----------------------------------------------------------------------
    typedef struct {
        rvv_instr_pkg::vec_instr_e instr;      // VRED*_VS
        int          sew;
        int          lmul_log2;
        int          avl;
        int          vd;
        int          vs1;
        int          vs2;
        pattern_e    pat;                      // content of vs2
        logic [31:0] acc;                      // vs1[0] (truncated to SEW)
    } red_case_t;

    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    function automatic string red_name(input rvv_instr_pkg::vec_instr_e instr);
        case (instr)
            rvv_instr_pkg::VREDSUM_VS:  return "vredsum.vs";
            rvv_instr_pkg::VREDAND_VS:  return "vredand.vs";
            rvv_instr_pkg::VREDOR_VS:   return "vredor.vs";
            rvv_instr_pkg::VREDXOR_VS:  return "vredxor.vs";
            rvv_instr_pkg::VREDMINU_VS: return "vredminu.vs";
            rvv_instr_pkg::VREDMIN_VS:  return "vredmin.vs";
            rvv_instr_pkg::VREDMAXU_VS: return "vredmaxu.vs";
            rvv_instr_pkg::VREDMAX_VS:  return "vredmax.vs";
            default:                    return instr.name();
        endcase
    endfunction

    // Write one SEW element (little endian) into the memory model
    function automatic void write_elem(input logic [31:0] base, input int idx, input int sew,
                                       input logic [31:0] val);
        for (int b = 0; b < sew / 8; b++)
            mem.write8(base + idx * (sew / 8) + b, val[8*b +: 8]);
    endfunction

    task automatic run_red_case(input red_case_t c);
        int lmul_x8    = vtb_lmul_x8(c.lmul_log2);
        bit vs2_ok     = vtb_vreg_aligned(c.vs2, lmul_x8);
        bit legal      = vs2_ok;                               // vd / vs1 are EMUL=1
        int vlmax      = vtb_vlmax(VLEN, c.sew, c.lmul_log2);  // elements of vs2
        int vlmax1     = VLEN / c.sew;                         // elements of vd / vs1
        int exp_vl     = vtb_expected_vl(c.avl, vlmax);
        int grp_bytes  = vlmax  * c.sew / 8;
        int reg_bytes  = VLEN / 8;
        bit same_reg   = (c.vd == c.vs1);
        logic [31:0] old_base = same_reg ? SRC1_BASE : OLD_BASE;   // vd content before the reduction
        logic [31:0] acc      = vtb_trunc(c.acc, c.sew);
        logic [31:0] exp0, all_ones;
        bit          accepted;
        string       tag;

        all_ones = vtb_trunc('1, c.sew);
        $display("all ones = %0h", all_ones);

        tag = $sformatf("%s v%0d,v%0d,v%0d SEW=%0d LMUL=%s avl=%0d vl=%0d pat=%s acc=%0h",
                        red_name(c.instr), c.vd, c.vs2, c.vs1,
                        c.sew, lmul_str(c.lmul_log2), c.avl, exp_vl, c.pat.name(), acc);

        case_errors = 0;
        case_count++;

        //  memory setup
        mem.clear_mem();
        mem.fill_incr(OLD_BASE,  reg_bytes, 8'h40);          // OLD[i]  = 0x40 + i
        mem.fill_incr(SRC1_BASE, reg_bytes, 8'h60);          // vs1[i>0] must be ignored
        write_elem(SRC1_BASE, 0, c.sew, acc);                // vs1[0]  = accumulator
        case (c.pat)
            PAT_INCR: mem.fill_incr(SRC2_BASE, grp_bytes, 8'h01);
            default:  for (int b = 0; b < grp_bytes; b++) mem.write8(SRC2_BASE + b, 8'($urandom));
        endcase
        mem.fill(DST_BASE, reg_bytes + 16, SENTINEL);

        // preload vd / vs1 (single registers, LMUL=1) and vs2 (group, LMUL under test)
        if (legal) begin
            configure_vtype(c.sew, 0, AVL_MAX, vlmax1);
            if (!same_reg)
                issue_instr(vtb_vle(c.sew, 5'(c.vd), X_ADDR), OLD_BASE, 1'b1,
                            {"preload vd: ", tag}, accepted);
            issue_instr(vtb_vle(c.sew, 5'(c.vs1), X_ADDR), SRC1_BASE, 1'b1,
                        {"preload vs1: ", tag}, accepted);
            configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
            issue_instr(vtb_vle(c.sew, 5'(c.vs2), X_ADDR), SRC2_BASE, 1'b1,
                        {"preload vs2: ", tag}, accepted);
        end

        // reference result
        exp0 = acc;
        for (int i = 0; i < exp_vl; i++)
            exp0 = vtb_red_step(c.instr, exp0, read_elem(SRC2_BASE, i, c.sew), c.sew);

        //  the reduction itself, with the vl under test
        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);
        mem.clear_log();
        issue_instr(vtb_enc_red(c.instr, 5'(c.vd), 5'(c.vs2), 5'(c.vs1)), '0, legal, tag, accepted);

        if (legal && accepted) begin
            check(mem.access_log.size() == 0, {"reduction touched the bus: ", tag});

        `ifndef VPU_VRF_BYTE
            // dump the whole vd register and compare
            configure_vtype(c.sew, 0, AVL_MAX, vlmax1);
            issue_instr(vtb_vse(c.sew, 5'(c.vd), X_ADDR), DST_BASE, 1'b1,
                        {"dump vd: ", tag}, accepted);
        `endif
            for (int i = 0; i < vlmax1; i++) begin
        `ifdef VPU_VRF_BYTE
                logic [31:0] got = vrf_elem(c.vd, i, c.sew);          // straight from the DUT
        `else
                logic [31:0] got = read_elem(DST_BASE, i, c.sew);      // through mem
        `endif
                logic [31:0] old = read_elem(old_base, i, c.sew);
                if (i == 0) begin
                    logic [31:0] exp = (exp_vl > 0) ? exp0 : old;
                    if (got !== exp) begin
                        fail($sformatf("%s: vd[0] = %0h, expected %0h%s", tag, got, exp,
                                       (exp_vl > 0) ? "" : " (vl=0: unchanged)"));
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
            check(mem.access_log.size() == 0, {"rejected reduction touched the bus: ", tag});
        end

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s  [%s]", $time, case_errors ? "FAIL" : "PASS", tag,
                     legal ? "legal" : "illegal: vs2 misaligned");
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    rvv_instr_pkg::vec_instr_e instrs [1] = '{rvv_instr_pkg::VREDSUM_VS};
    // rvv_instr_pkg::vec_instr_e instrs [8] = '{rvv_instr_pkg::VREDSUM_VS,  rvv_instr_pkg::VREDAND_VS,
    //                                           rvv_instr_pkg::VREDOR_VS,   rvv_instr_pkg::VREDXOR_VS,
    //                                           rvv_instr_pkg::VREDMINU_VS, rvv_instr_pkg::VREDMIN_VS,
    //                                           rvv_instr_pkg::VREDMAXU_VS, rvv_instr_pkg::VREDMAX_VS};
    int          sews     [3] = '{8, 16, 32};
    pattern_e    pats     [2] = '{PAT_INCR, PAT_RAND};
    // accumulators (truncated to SEW): zero, generic, all ones, sign bit set at every SEW
    logic [31:0] accs     [4] = '{32'h0000_0000, 32'h1234_5678, 32'hFFFF_FFFF, 32'h8000_8080};

    initial begin
        red_case_t c;
        int        vlmax, regs;
        int        avls [4];

        void'($urandom(RAND_SEED));
        do_reset();

        foreach (instrs[n]) foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            regs  = vtb_emul_regs(vtb_lmul_x8(l));
            avls  = '{0, 1, vlmax / 2 + 1, vlmax};   // empty / single element / partial / full

            foreach (avls[a]) begin
                if (avls[a] == 0 && !TEST_VL0) continue;

                foreach (pats[p]) foreach (accs[k]) begin
                    c = '{instr    : instrs[n],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : avls[a],
                          vd       : VD_REG,
                          vs1      : VS1_REG,
                          vs2      : VS2_REG,
                          pat      : pats[p],
                          acc      : accs[k]};
                    run_red_case(c);
                end

                // vd == vs1 (accumulate in place), once per (SEW, LMUL, AVL)
                c = '{instr    : instrs[n],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : avls[a],
                      vd       : VD_REG,
                      vs1      : VD_REG,
                      vs2      : VS2_REG,
                      pat      : PAT_RAND,
                      acc      : 32'h0BAD_F00D};
                run_red_case(c);
            end

            if (regs > 1) begin
                // vd / vs1 are EMUL=1: odd registers must be ACCEPTED even with LMUL > 1
                c = '{instr    : instrs[n],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : vlmax,
                      vd       : VD_REG + 1,
                      vs1      : VS1_REG + 1,
                      vs2      : VS2_REG,
                      pat      : PAT_INCR,
                      acc      : 32'h1};
                run_red_case(c);

                // Negative test: vs2 not aligned to the register group
                c.vd  = VD_REG;
                c.vs1 = VS1_REG;
                c.vs2 = VS2_REG + 1;
                run_red_case(c);
            end
        end

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_vreduction: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule
