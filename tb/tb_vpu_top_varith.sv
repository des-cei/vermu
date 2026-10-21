// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// tb_vpu_top_varith : single-width integer arithmetic / logic / shift / min-max (OPI*)
//
//   vadd.vv/vx/vi    vsub.vv/vx       vrsub.vx/vi
//   vand.vv/vx/vi    vor.vv/vx/vi     vxor.vv/vx/vi
//   vsll.vv/vx/vi    vsrl.vv/vx/vi    vsra.vv/vx/vi
//   vminu.vv/vx      vmin.vv/vx       vmaxu.vv/vx      vmax.vv/vx
//
// Per test point (instr, SEW, LMUL, AVL, operand, register aliasing):
//   1. vsetvli  vl = VLMAX
//   2. vle<SEW> vd  <- OLD pattern          (tail reference)
//      vle<SEW> vs1 <- SRC1 pattern         (.vv only, if vs1 != vd)
//      vle<SEW> vs2 <- SRC2 pattern         (if vs2 is not vd / vs1)
//   3. vsetvli  vl = AVL  (vtb_expected_vl)
//   4. v<op>.v{v,x,i}  vd, vs2, <vs1 | rs1 | imm5>
//   5. read vd back (register file peek, or vsetvli VLMAX + vse<SEW> -> DST)
//   6. compare element by element:
//        i <  vl : vtb_opi_elem(instr, vs1[i] | trunc(rs1) | sext(simm5), vs2[i])
//        i >= vl : tail -> old value (vta=0) or old value / all ones (vta=1)
//        vl = 0  : whole group must be left untouched
//
// Aliasing cases: vs1 == vs2, vs2 == vd, vs1 == vd (each operand reads the value
// the register held BEFORE the instruction).
//
// Negative tests (LMUL > 1): vd, vs1 or vs2 not aligned to the register group must
// be REJECTED by the VPU, with no bus traffic.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef VPU_VRF_BYTE
  `define VPU_VRF_BYTE
`endif

module tb_vpu_top_varith;

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
    localparam bit          TEST_VL0      = 1'b1;       // include vl = 0 points (vd must be untouched)
    localparam bit          TEST_ALIAS    = 1'b1;       // include vs1/vs2/vd aliasing points
    localparam bit          VERBOSE_PASS  = 1'b0;       // print a line for every passing case

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;     // try 30
    localparam int unsigned RSP_LATENCY   = 1;     // try 3
    localparam int unsigned RSP_EXTRA_MAX = 0;     // try 2

    // Memory map used by the tests
    localparam logic [31:0] OLD_BASE  = 32'h0000_1000;   // previous content of vd
    localparam logic [31:0] SRC1_BASE = 32'h0000_2000;   // content of vs1
    localparam logic [31:0] SRC2_BASE = 32'h0000_3000;   // content of vs2
    localparam logic [31:0] DST_BASE  = 32'h0000_4000;   // dump of vd
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int LMUL_LOG2_MIN = -2;   // vpu_pkg::lmul_e has no 1/8

    // Register groups (aligned for any LMUL up to 8)
    localparam int VD_REG  = 8;     // v8..v15
    localparam int VS1_REG = 16;    // v16..v23
    localparam int VS2_REG = 24;    // v24..v31

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
            end
            return v;
        endfunction
    `endif
    //----------------------------------------------------------------------
    // Test point
    //----------------------------------------------------------------------
    typedef enum {FORM_VV, FORM_VX, FORM_VI} opi_form_e;

    typedef struct {
        rvv_instr_pkg::vec_instr_e instr;      // V<op>_{VV,VX,VI}
        int          sew;
        int          lmul_log2;
        int          avl;
        int          vd;
        int          vs1;                      // .vv only
        int          vs2;
        logic [31:0] scalar;                   // .vx : value of rs1   .vi : imm5 in [4:0]
    } varith_case_t;

    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    // Operand form taken from the enum suffix (_VV / _VX / _VI)
    function automatic opi_form_e form_of(input rvv_instr_pkg::vec_instr_e instr);
        string n   = instr.name();
        string sfx = n.substr(n.len() - 2, n.len() - 1);
        case (sfx)
            "VV":    return FORM_VV;
            "VX":    return FORM_VX;
            "VI":    return FORM_VI;
            default: $fatal(1, "form_of: unexpected instruction %s", n);
        endcase
    endfunction

    // VADD_VV -> "vadd.vv"
    function automatic string op_name(input rvv_instr_pkg::vec_instr_e instr);
        string n = instr.name().tolower();
        for (int i = 0; i < n.len(); i++) if (n[i] == "_") n[i] = ".";
        return n;
    endfunction

    task automatic run_varith_case(input varith_case_t c);
        opi_form_e form   = form_of(c.instr);
        bit is_vv         = (form == FORM_VV);
        bit is_vi         = (form == FORM_VI);
        int lmul_x8       = vtb_lmul_x8(c.lmul_log2);
        bit vd_ok         = vtb_vreg_aligned(c.vd,  lmul_x8);
        bit vs1_ok        = !is_vv || vtb_vreg_aligned(c.vs1, lmul_x8);
        bit vs2_ok        = vtb_vreg_aligned(c.vs2, lmul_x8);
        bit legal         = vd_ok && vs1_ok && vs2_ok;
        int vlmax         = vtb_vlmax(VLEN, c.sew, c.lmul_log2);
        int exp_vl        = vtb_expected_vl(c.avl, vlmax);
        int grp_bytes     = vlmax * c.sew / 8;
        // Where the value each source register holds before the instruction comes from
        bit vs1_is_vd = is_vv && (c.vs1 == c.vd);
        bit vs2_is_vd = (c.vs2 == c.vd);
        bit vs2_is_s1 = is_vv && !vs2_is_vd && (c.vs2 == c.vs1);
        logic [31:0] vs1_base = vs1_is_vd ? OLD_BASE : SRC1_BASE;
        logic [31:0] vs2_base = vs2_is_vd ? OLD_BASE : (vs2_is_s1 ? vs1_base : SRC2_BASE);
        logic [4:0]  op1;
        logic [31:0] rs1_val;
        logic [31:0] scalar_elem;              // .vx / .vi operand as a SEW element
        logic [31:0] all_ones;
        bit          accepted;
        string       op1_str;
        string       tag;

        case (form)
            FORM_VV: begin op1 = 5'(c.vs1);      rs1_val = '0;       op1_str = $sformatf("v%0d", c.vs1); end
            FORM_VX: begin op1 = X_SCALAR;       rs1_val = c.scalar; op1_str = "x12";                    end
            FORM_VI: begin op1 = c.scalar[4:0];  rs1_val = '0;
                           op1_str = $sformatf("%0d", $signed(c.scalar[4:0]));                           end
        endcase
        scalar_elem = is_vi ? vtb_elem_from_simm5(c.scalar[4:0], c.sew)
                            : vtb_elem_from_x(c.scalar, c.sew);
        all_ones    = vtb_trunc('1, c.sew);

        // assembly operand order: "vd, vs2, vs1|rs1|imm"
        tag = $sformatf("%s v%0d,v%0d,%s SEW=%0d LMUL=%s avl=%0d vl=%0d%s", op_name(c.instr),
                        c.vd, c.vs2, op1_str, c.sew, lmul_str(c.lmul_log2), c.avl, exp_vl,
                        (form == FORM_VX) ? $sformatf(" rs1=%08h", c.scalar) : "");

        case_errors = 0;
        case_count++;

        //  memory setup
        mem.clear_mem();
        mem.fill_incr(OLD_BASE,  grp_bytes, 8'h40);    // OLD[i]  = 0x40 + i
        mem.fill_incr(SRC1_BASE, grp_bytes, 8'h81);    // SRC1[i] = 0x81 + i  (sign bit set)
        mem.fill_incr(SRC2_BASE, grp_bytes, 8'hC7);    // SRC2[i] = 0xC7 + i  (wraps through 0)
        mem.fill(DST_BASE, grp_bytes + 16, SENTINEL);

        // preload vd / vs1 / vs2 with known data (legal cases only)
        if (legal) begin
            configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
            issue_instr(vtb_vle(c.sew, 5'(c.vd), X_ADDR), OLD_BASE, 1'b1,
                        {"preload vd: ", tag}, accepted);
            if (is_vv && !vs1_is_vd)
                issue_instr(vtb_vle(c.sew, 5'(c.vs1), X_ADDR), SRC1_BASE, 1'b1,
                            {"preload vs1: ", tag}, accepted);
            if (!vs2_is_vd && !vs2_is_s1)
                issue_instr(vtb_vle(c.sew, 5'(c.vs2), X_ADDR), SRC2_BASE, 1'b1,
                            {"preload vs2: ", tag}, accepted);
        end

        //  the instruction under test, with the vl under test
        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);
        mem.clear_log();
        issue_instr(vtb_enc_opi(c.instr, 5'(c.vd), 5'(c.vs2), op1),
                    rs1_val, legal, tag, accepted);

        if (legal && accepted) begin
            check(mem.access_log.size() == 0, {"instruction touched the bus: ", tag});

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
                logic [31:0] old = read_elem(OLD_BASE, i, c.sew);
                logic [31:0] a   = is_vv ? read_elem(vs1_base, i, c.sew) : scalar_elem;
                logic [31:0] b   = read_elem(vs2_base, i, c.sew);
                logic [31:0] exp;
                if (i < exp_vl) begin
                    exp = vtb_opi_elem(c.instr, a, b, c.sew);
                    if (got !== exp)
                        fail($sformatf("%s: element %0d = %0h, expected %0h (vs2=%0h op1=%0h)",
                                       tag, i, got, exp, b, a));
                end else if (exp_vl == 0) begin
                    // vstart >= vl: no element is updated, tail included
                    if (got !== old)
                        fail($sformatf("%s: vl=0 but element %0d = %0h, expected untouched %0h",
                                       tag, i, got, old));
                end else if (CHECK_TAIL) begin
                    if (!(got === old || (VTA && got === all_ones)))
                        fail($sformatf("%s: tail element %0d = %0h, expected %0h%s",
                                       tag, i, got, old, VTA ? " or all ones" : ""));
                end
            end
        end else if (!legal && !accepted) begin
            check(mem.access_log.size() == 0, {"rejected instruction touched the bus: ", tag});
        end

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s  [%s]", $time, case_errors ? "FAIL" : "PASS", tag,
                     legal   ? "legal" :
                     !vd_ok  ? "illegal: vd misaligned" :
                     !vs1_ok ? "illegal: vs1 misaligned" : "illegal: vs2 misaligned");
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int sews [3] = '{8, 16, 32};

    rvv_instr_pkg::vec_instr_e vv_instrs [12] = '{
        rvv_instr_pkg::VADD_VV,  rvv_instr_pkg::VSUB_VV,
        rvv_instr_pkg::VAND_VV,  rvv_instr_pkg::VOR_VV,   rvv_instr_pkg::VXOR_VV,
        rvv_instr_pkg::VSLL_VV,  rvv_instr_pkg::VSRL_VV,  rvv_instr_pkg::VSRA_VV,
        rvv_instr_pkg::VMINU_VV, rvv_instr_pkg::VMIN_VV,
        rvv_instr_pkg::VMAXU_VV, rvv_instr_pkg::VMAX_VV};

    rvv_instr_pkg::vec_instr_e vx_instrs [13] = '{
        rvv_instr_pkg::VADD_VX,  rvv_instr_pkg::VSUB_VX,  rvv_instr_pkg::VRSUB_VX,
        rvv_instr_pkg::VAND_VX,  rvv_instr_pkg::VOR_VX,   rvv_instr_pkg::VXOR_VX,
        rvv_instr_pkg::VSLL_VX,  rvv_instr_pkg::VSRL_VX,  rvv_instr_pkg::VSRA_VX,
        rvv_instr_pkg::VMINU_VX, rvv_instr_pkg::VMIN_VX,
        rvv_instr_pkg::VMAXU_VX, rvv_instr_pkg::VMAX_VX};

    rvv_instr_pkg::vec_instr_e vi_instrs [8] = '{
        rvv_instr_pkg::VADD_VI,  rvv_instr_pkg::VRSUB_VI,
        rvv_instr_pkg::VAND_VI,  rvv_instr_pkg::VOR_VI,   rvv_instr_pkg::VXOR_VI,
        rvv_instr_pkg::VSLL_VI,  rvv_instr_pkg::VSRL_VI,  rvv_instr_pkg::VSRA_VI};

    // 0 / 1 / -1 (identity, max shift) / big pattern (truncation, shift by low bits) /
    // sign bit only in the low byte
    logic [31:0] scalars [5] = '{32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF,
                                 32'hDEAD_BEEF, 32'h1234_5683};
    // 0 / 1 / -1 / max positive (15) / most negative (-16)
    logic [4:0]  imms    [5] = '{5'h00, 5'h01, 5'h1F, 5'h0F, 5'h10};

    // Full SEW x LMUL x AVL sweep, with aliasing and misaligned-group (reject) cases
    task automatic run_sweep();
        varith_case_t c;
        int           vlmax, regs;
        int           avls [4];

        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;   // vsetvli itself would set vill

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            regs  = vtb_emul_regs(vtb_lmul_x8(l));
            avls  = '{0, 1, vlmax / 2 + 1, vlmax};   // empty / single element / partial / full

            foreach (avls[a]) begin
                if (avls[a] == 0 && !TEST_VL0) continue;

                // .vv : separate groups, plus aliasing on the partial-vl point
                foreach (vv_instrs[k]) begin
                    c = '{instr    : vv_instrs[k],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : avls[a],
                          vd       : VD_REG,
                          vs1      : VS1_REG,
                          vs2      : VS2_REG,
                          scalar   : '0};
                    run_varith_case(c);
                    if (TEST_ALIAS && a == 2) begin
                        c.vs2 = VS1_REG;                  run_varith_case(c);   // vs1 == vs2
                        c.vs2 = VD_REG;                   run_varith_case(c);   // vs2 == vd
                        c.vs2 = VS2_REG; c.vs1 = VD_REG;  run_varith_case(c);   // vs1 == vd
                    end
                end

                // .vx : several scalar patterns (truncation / sign / identity)
                foreach (vx_instrs[k]) begin
                    foreach (scalars[n]) begin
                        c = '{instr    : vx_instrs[k],
                              sew      : sews[s],
                              lmul_log2: l,
                              avl      : avls[a],
                              vd       : VD_REG,
                              vs1      : 0,
                              vs2      : VS2_REG,
                              scalar   : scalars[n]};
                        run_varith_case(c);
                    end
                    if (TEST_ALIAS && a == 2) begin
                        c.vs2 = VD_REG;                   run_varith_case(c);   // vs2 == vd
                    end
                end

                // .vi : immediate patterns (sign extension / shift amount)
                foreach (vi_instrs[k]) begin
                    foreach (imms[n]) begin
                        c = '{instr    : vi_instrs[k],
                              sew      : sews[s],
                              lmul_log2: l,
                              avl      : avls[a],
                              vd       : VD_REG,
                              vs1      : 0,
                              vs2      : VS2_REG,
                              scalar   : 32'(imms[n])};
                        run_varith_case(c);
                    end
                    if (TEST_ALIAS && a == 2) begin
                        c.vs2 = VD_REG;                   run_varith_case(c);   // vs2 == vd
                    end
                end
            end

            // Negative tests: register groups not aligned to LMUL
            if (regs > 1) begin
                foreach (vv_instrs[k]) begin
                    c = '{instr    : vv_instrs[k],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : vlmax,
                          vd       : VD_REG + 1,
                          vs1      : VS1_REG,
                          vs2      : VS2_REG,
                          scalar   : '0};
                    run_varith_case(c);                                        // vd misaligned
                    c.vd  = VD_REG;  c.vs1 = VS1_REG + 1;  run_varith_case(c); // vs1 misaligned
                    c.vs1 = VS1_REG; c.vs2 = VS2_REG + 1;  run_varith_case(c); // vs2 misaligned
                end
                foreach (vx_instrs[k]) begin
                    c = '{instr    : vx_instrs[k],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : vlmax,
                          vd       : VD_REG + 1,
                          vs1      : 0,
                          vs2      : VS2_REG,
                          scalar   : 32'h3};
                    run_varith_case(c);                                        // vd misaligned
                    c.vd  = VD_REG;  c.vs2 = VS2_REG + 1;  run_varith_case(c); // vs2 misaligned
                end
                foreach (vi_instrs[k]) begin
                    c = '{instr    : vi_instrs[k],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : vlmax,
                          vd       : VD_REG + 1,
                          vs1      : 0,
                          vs2      : VS2_REG,
                          scalar   : 32'h3};
                    run_varith_case(c);                                        // vd misaligned
                    c.vd  = VD_REG;  c.vs2 = VS2_REG + 1;  run_varith_case(c); // vs2 misaligned
                end
            end
        end
    endtask

    initial begin
        do_reset();

        run_sweep();

        // ---- summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_varith: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule
