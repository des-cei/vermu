// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// Widening integer multiply:
//   vwmulu.vv / vwmulu.vx / vwmul.vv / vwmul.vx / vwmulsu.vv / vwmulsu.vx
//   vd (2*SEW, EMUL=2*LMUL) = ext(vs2) * ext(vs1[i] | rs1)   (vs1, vs2: SEW, EMUL=LMUL)


`timescale 1ns/1ps

`ifndef VPU_VRF_BYTE
  `define VPU_VRF_BYTE
`endif

module tb_vpu_top_vwmul;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;
    import tb_vpu_pkg::*;

    //----------------------------------------------------------------------
    // Configuration  (match your VPU build)
    //----------------------------------------------------------------------
    localparam int unsigned VLEN          = VPU_VLEN;
    localparam int unsigned ELEN          = 32;
    localparam int unsigned NUM_PORTS     = VPU_N_IPU;
    localparam int unsigned OBI_DATA_W    = 32;
    localparam bit          VTA           = 1'b1;
    localparam bit          VMA           = 1'b1;
    localparam hartid_t     HARTID        = 1;

    localparam bit          CHECK_TAIL    = 1'b1;
    localparam bit          TEST_VL0      = 1'b1;
    localparam bit          TEST_ALIAS    = 1'b1;
    // SEW=32 and an illegal vd/vs1, vd/vs2 overlap are reserved 
    localparam bit          TEST_EW_REJECT = 1'b1;
    localparam bit          VERBOSE_PASS  = 1'b0;

    // Stress knobs for the memory model
    localparam int unsigned GNT_STALL_PCT = 0;
    localparam int unsigned RSP_LATENCY   = 1;
    localparam int unsigned RSP_EXTRA_MAX = 0;

    // Memory map used by the tests
    localparam logic [31:0] OLD_BASE  = 32'h0000_1000;   // vd                                    (2*SEW)
    localparam logic [31:0] SRC1_BASE = 32'h0000_2000;   // vs1                                   (SEW)
    localparam logic [31:0] SRC2_BASE = 32'h0000_3000;   // vs2                                   (SEW)
    localparam logic [31:0] DST_BASE  = 32'h0000_4000;   // vd dump (no VPU_VRF_BYTE)
    localparam logic [7:0]  SENTINEL  = 8'hAA;

    localparam int LMUL_LOG2_MIN = -2;   // vpu_pkg::lmul_e has no 1/8
    localparam int LMUL_LOG2_MAX = 2;    // 2*LMUL <= 8

    // Register groups (aligned for a wide EMUL up to 8)
    localparam int VD_REG  = 8;     // v8..v15
    localparam int VS2_REG = 16;    // v16..v19
    localparam int VS1_REG = 24;    // v24..v27

    localparam int VREG_B = VLEN / 8;

    `include "tb_vpu_common.svh"
    `ifdef VPU_VRF_BYTE
        localparam int VRF_FRAG_W = VPU_N_IPU * ELEN;

        function automatic logic [7:0] vrf_byte(input int vreg_i, input int byte_i);
            logic [VRF_FRAG_W-1:0] frag;
            frag = dut.vregfile_i.vreg[vreg_i][(byte_i * 8) / VRF_FRAG_W];
            return frag[((byte_i * 8) % VRF_FRAG_W) +: 8];
        endfunction

        function automatic logic [31:0] vrf_elem(input int base_reg, input int idx, input int sew);
            logic [31:0] v = '0;
            for (int b = 0; b < sew / 8; b++) begin
                int n = idx * (sew / 8) + b;
                v[8*b +: 8] = vrf_byte(base_reg + n / VREG_B, n % VREG_B);
            end
            return v;
        endfunction
    `endif

    //----------------------------------------------------------------------
    // Register file model: what the preloads put in each register. Expected operands are
    // read from here, so aliased groups (vs1/vs2 inside vd, vs1 = vs2) need no special casing.
    //----------------------------------------------------------------------
    logic [7:0] vmodel [32][VREG_B];

    function automatic logic [31:0] model_elem(input int base_reg, input int idx, input int eew);
        logic [31:0] v = '0;
        for (int b = 0; b < eew / 8; b++) begin
            int n = idx * (eew / 8) + b;
            v[8*b +: 8] = vmodel[base_reg + n / VREG_B][n % VREG_B];
        end
        return v;
    endfunction

    // Bytes with both sign bits, even in the 4-byte groups of LMUL=1/4
    function automatic void fill_mix(input logic [31:0] base, input int n, input logic [7:0] seed);
        for (int i = 0; i < n; i++) mem.write8(base + i, 8'(seed + i * 8'h5B));
    endfunction

    // vle of 'nelem' elements of 'eew' bits into vreg (vtype already set), mirrored in vmodel
    task automatic preload(input int vreg, input int eew, input logic [31:0] base,
                           input int nelem, input string tag);
        bit accepted;
        issue_instr(vtb_vle(eew, 5'(vreg), X_ADDR), base, 1'b1, tag, accepted);
        for (int b = 0; b < nelem * eew / 8; b++)
            vmodel[vreg + b / VREG_B][b % VREG_B] = mem.read8(base + b);
    endtask

    //----------------------------------------------------------------------
    // Test point
    //----------------------------------------------------------------------
    typedef struct {
        rvv_instr_pkg::vec_instr_e instr;      // VWMUL{,U,SU}_{VV,VX}
        int          sew;                      // narrow SEW; vd is 2*SEW
        int          lmul_log2;
        int          avl;
        int          vd;
        int          vs1;
        int          vs2;
        logic [31:0] scalar;
    } vwmul_case_t;

    function automatic string lmul_str(input int lmul_log2);
        return (lmul_log2 >= 0) ? $sformatf("%0d", 1 << lmul_log2)
                                : $sformatf("1/%0d", 1 << -lmul_log2);
    endfunction

    function automatic bit is_vv_form(input rvv_instr_pkg::vec_instr_e instr);
        return instr inside {rvv_instr_pkg::VWMULU_VV, rvv_instr_pkg::VWMUL_VV,
                             rvv_instr_pkg::VWMULSU_VV};
    endfunction

    function automatic string op_name(input rvv_instr_pkg::vec_instr_e instr);
        case (instr)
            rvv_instr_pkg::VWMULU_VV:  return "vwmulu.vv";
            rvv_instr_pkg::VWMULU_VX:  return "vwmulu.vx";
            rvv_instr_pkg::VWMUL_VV:   return "vwmul.vv";
            rvv_instr_pkg::VWMUL_VX:   return "vwmul.vx";
            rvv_instr_pkg::VWMULSU_VV: return "vwmulsu.vv";
            rvv_instr_pkg::VWMULSU_VX: return "vwmulsu.vx";
            default:                   return instr.name();
        endcase
    endfunction

    // assembly order: vwmul.vv vd, vs2, vs1  /  vwmul.vx vd, vs2, rs1
    function automatic string case_tag(input vwmul_case_t c, input int exp_vl);
        bit is_vv = is_vv_form(c.instr);
        return $sformatf("%s v%0d,v%0d,%s SEW=%0d LMUL=%s avl=%0d vl=%0d%s", op_name(c.instr),
                         c.vd, c.vs2, is_vv ? $sformatf("v%0d", c.vs1) : "x12",
                         c.sew, lmul_str(c.lmul_log2), c.avl, exp_vl,
                         is_vv ? "" : $sformatf(" rs1=%08h", c.scalar));
    endfunction

    // Part 1: legal widening multiply, result checked element by element
    task automatic run_vwmul_case(input vwmul_case_t c);
        bit is_vv     = is_vv_form(c.instr);
        int w         = 2 * c.sew;
        int vlmax     = vtb_vlmax(VLEN, c.sew, c.lmul_log2);    // same for (SEW,LMUL) and (2SEW,2LMUL)
        int exp_vl    = vtb_expected_vl(c.avl, vlmax);
        int vd_regs   = vtb_emul_regs(vtb_lmul_x8(c.lmul_log2 + 1));
        int wide_b    = vlmax * w / 8;
        int narrow_b  = vlmax * c.sew / 8;
        logic [4:0]  op1      = is_vv ? 5'(c.vs1) : X_SCALAR;
        logic [31:0] rs1_val  = is_vv ? '0 : c.scalar;
        logic [31:0] all_ones = vtb_trunc('1, w);
        logic [31:0] exp_v [];
        bit          accepted;
        string       tag;
    `ifdef VPU_VRF_BYTE
        logic [7:0]  snap [32][VREG_B];
    `endif

        tag = case_tag(c, exp_vl);

        case_errors = 0;
        case_count++;

        // memory setup
        mem.clear_mem();
        fill_mix(OLD_BASE,  wide_b,   8'h40);
        fill_mix(SRC1_BASE, narrow_b, 8'h81);
        fill_mix(SRC2_BASE, narrow_b, 8'hC7);
        mem.fill(DST_BASE, wide_b + 16, SENTINEL);

        // preload: vd under (2*SEW, 2*LMUL) so the tail / vl=0 checks have a known old value,
        // then the narrow sources under (SEW, LMUL), so a source placed inside vd overwrites
        // the part of vd it shares
        foreach (vmodel[r, b]) vmodel[r][b] = 'x;
        configure_vtype(w, c.lmul_log2 + 1, AVL_MAX, vlmax);
        preload(c.vd, w, OLD_BASE, vlmax, {"preload vd: ", tag});
        configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
        preload(c.vs2, c.sew, SRC2_BASE, vlmax, {"preload vs2: ", tag});
        if (is_vv && c.vs1 != c.vs2) preload(c.vs1, c.sew, SRC1_BASE, vlmax, {"preload vs1: ", tag});

        // expected result from the operands as they stand before the instruction
        exp_v = new[vlmax];
        for (int i = 0; i < vlmax; i++) begin
            logic [31:0] a = is_vv ? model_elem(c.vs1, i, c.sew) : c.scalar;
            exp_v[i] = (i < exp_vl) ? vtb_wmul_elem(c.instr, a, model_elem(c.vs2, i, c.sew), c.sew)
                                    : model_elem(c.vd, i, w);
        end

        configure_vtype(c.sew, c.lmul_log2, c.avl, exp_vl);
    `ifdef VPU_VRF_BYTE
        foreach (snap[r, b]) snap[r][b] = vrf_byte(r, b);
    `endif
        mem.clear_log();
        issue_instr(vtb_enc_wmul(c.instr, 5'(c.vd), 5'(c.vs2), op1), rs1_val, 1'b1, tag, accepted);

        if (accepted) begin
            check(mem.access_log.size() == 0, {"instruction touched the bus: ", tag});

        `ifdef VPU_VRF_BYTE
            // nothing outside the 2*LMUL vd group may change
            for (int r = 0; r < 32; r++) begin
                if (r >= c.vd && r < c.vd + vd_regs) continue;
                for (int b = 0; b < VREG_B; b++)
                    if (vrf_byte(r, b) !== snap[r][b]) begin
                        fail($sformatf("%s: v%0d byte %0d = %0h, expected untouched %0h (outside vd group v%0d..v%0d)",
                                       tag, r, b, vrf_byte(r, b), snap[r][b], c.vd, c.vd + vd_regs - 1));
                        // break;
                    end
            end
        `else
            configure_vtype(w, c.lmul_log2 + 1, AVL_MAX, vlmax);
            issue_instr(vtb_vse(w, 5'(c.vd), X_ADDR), DST_BASE, 1'b1, {"dump vd: ", tag}, accepted);
        `endif

            for (int i = 0; i < vlmax; i++) begin
        `ifdef VPU_VRF_BYTE
                logic [31:0] got = vrf_elem(c.vd, i, w);
        `else
                logic [31:0] got = read_elem(DST_BASE, i, w);
        `endif
                logic [31:0] old = model_elem(c.vd, i, w);
                if (i < exp_vl) begin
                    if (got !== exp_v[i])
                        fail($sformatf("%s: element %0d = %0h, expected %0h (vs2=%0h op1=%0h)",
                                       tag, i, got, exp_v[i], model_elem(c.vs2, i, c.sew),
                                       is_vv ? model_elem(c.vs1, i, c.sew) : c.scalar));
                end else if (exp_vl == 0) begin
                    if (got !== old)
                        fail($sformatf("%s: vl=0 but element %0d = %0h, expected untouched %0h",
                                       tag, i, got, old));
                end else if (CHECK_TAIL) begin
                    if (!(got === old || (VTA && got === all_ones)))
                        fail($sformatf("%s: tail element %0d = %0h, expected %0h%s",
                                       tag, i, got, old, VTA ? " or all ones" : ""));
                end
            end
        end

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s", $time, case_errors ? "FAIL" : "PASS", tag);
    endtask

    // Part 2: reserved encoding, must be rejected without touching the bus or the VRF
    task automatic run_reject_case(input vwmul_case_t c, input string why);
        bit          is_vv = is_vv_form(c.instr);
        logic [4:0]  op1   = is_vv ? 5'(c.vs1) : X_SCALAR;
        int          vlmax = vtb_vlmax(VLEN, c.sew, c.lmul_log2);
        string       tag   = {case_tag(c, vlmax), " [", why, "]"};
        bit          accepted;
    `ifdef VPU_VRF_BYTE
        logic [7:0]  snap [32][VREG_B];
    `endif

        case_errors = 0;
        case_count++;

        configure_vtype(c.sew, c.lmul_log2, AVL_MAX, vlmax);
    `ifdef VPU_VRF_BYTE
        foreach (snap[r, b]) snap[r][b] = vrf_byte(r, b);
    `endif
        mem.clear_log();
        issue_instr(vtb_enc_wmul(c.instr, 5'(c.vd), 5'(c.vs2), op1), is_vv ? '0 : c.scalar,
                    1'b0, tag, accepted);

        check(mem.access_log.size() == 0, {"rejected instruction touched the bus: ", tag});
    `ifdef VPU_VRF_BYTE
        if (!accepted)
            foreach (snap[r, b])
                if (vrf_byte(r, b) !== snap[r][b]) begin
                    fail($sformatf("%s: rejected instruction changed v%0d byte %0d", tag, r, b));
                    // break;
                end
    `endif

        if (case_errors) case_failed++;
        if (case_errors || VERBOSE_PASS)
            $display("[%0t] %s  %s", $time, case_errors ? "FAIL" : "PASS", tag);
    endtask

    //----------------------------------------------------------------------
    // Test sequence
    //----------------------------------------------------------------------
    int          sews     [2] = '{8, 16};
    rvv_instr_pkg::vec_instr_e vv_instrs [3] = '{rvv_instr_pkg::VWMULU_VV, rvv_instr_pkg::VWMUL_VV,
                                                 rvv_instr_pkg::VWMULSU_VV};

    rvv_instr_pkg::vec_instr_e vx_instrs [3] = '{rvv_instr_pkg::VWMULU_VX, rvv_instr_pkg::VWMUL_VX,
                                                 rvv_instr_pkg::VWMULSU_VX};

    // 0 / 1 / -1 / big pattern (truncation to SEW) / sign bit of SEW=8 only / sign bit of SEW=16 only
    logic [31:0] scalars  [6] = '{32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF,
                                  32'hDEAD_BEEF, 32'h1234_5683, 32'h0000_8000};

    task automatic run_sweep();
        vwmul_case_t c;
        int          vlmax, regs;
        int          avls [4];

        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= LMUL_LOG2_MAX; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;

            vlmax = vtb_vlmax(VLEN, sews[s], l);
            regs  = vtb_emul_regs(vtb_lmul_x8(l));      // vs1/vs2 group; vd is twice this
            avls  = '{0, 1, vlmax / 2 + 1, vlmax};

            foreach (avls[a]) begin
                if (avls[a] == 0 && !TEST_VL0) continue;

                foreach (vv_instrs[k]) begin
                    c = '{instr    : vv_instrs[k],
                          sew      : sews[s],
                          lmul_log2: l,
                          avl      : avls[a],
                          vd       : VD_REG,
                          vs1      : VS1_REG,
                          vs2      : VS2_REG,
                          scalar   : '0};
                    run_vwmul_case(c);
                    if (TEST_ALIAS && a == 2) begin
                        // vs1 = vs2: same EEW, always legal (squares)
                        c.vs1 = VS2_REG;                        run_vwmul_case(c);
                        // a source in the highest-numbered half of vd (legal when LMUL >= 1)
                        if (l >= 0) begin
                            c.vs1 = VD_REG + regs;              run_vwmul_case(c);
                            c.vs1 = VS1_REG; c.vs2 = VD_REG + regs; run_vwmul_case(c);
                            // both sources in the high half of vd
                            c.vs1 = VD_REG + regs;              run_vwmul_case(c);
                        end
                    end
                end

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
                        run_vwmul_case(c);
                    end
                    if (TEST_ALIAS && a == 2 && l >= 0) begin
                        c.vs2 = VD_REG + regs;                  run_vwmul_case(c);
                    end
                end
            end
        end
    endtask

    task automatic run_rejects();
        vwmul_case_t c;
        int          regs;

        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= 3; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;
            regs = vtb_emul_regs(vtb_lmul_x8(l));

            foreach (vv_instrs[k]) begin
                c = '{instr    : vv_instrs[k],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : VS1_REG,
                      vs2      : VS2_REG,
                      scalar   : '0};
                if (l == 3) begin
                    run_reject_case(c, "2*LMUL = 16");
                    continue;
                end
                // 2*LMUL group alignment of vd (whenever 2*LMUL >= 2)
                if (l >= 0) begin
                    c.vd  = VD_REG + regs;                   run_reject_case(c, "vd misaligned to 2*LMUL");
                    c.vd  = VD_REG;
                end
                // LMUL group alignment of vs1 / vs2
                if (regs > 1) begin
                    c.vs1 = VS1_REG + 1;                     run_reject_case(c, "vs1 misaligned to LMUL");
                    c.vs1 = VS1_REG; c.vs2 = VS2_REG + 1;    run_reject_case(c, "vs2 misaligned to LMUL");
                end
            end

            foreach (vx_instrs[k]) begin
                c = '{instr    : vx_instrs[k],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : 0,
                      vs2      : VS2_REG,
                      scalar   : 32'h3};
                if (l == 3) begin
                    run_reject_case(c, "2*LMUL = 16");
                    continue;
                end
                if (l >= 0) begin
                    c.vd  = VD_REG + regs;                   run_reject_case(c, "vd misaligned to 2*LMUL");
                    c.vd  = VD_REG;
                end
                if (regs > 1) begin
                    c.vs2 = VS2_REG + 1;                     run_reject_case(c, "vs2 misaligned to LMUL");
                end
            end
        end

        // Checked last: fail() stops the simulation
        if (!TEST_EW_REJECT) return;

        // vs1 / vs2 (SEW) in the lowest-numbered part of vd (2*SEW), or source EMUL < 1 (RVV 5.2)
        foreach (sews[s]) for (int l = LMUL_LOG2_MIN; l <= LMUL_LOG2_MAX; l++) begin
            if (!vtb_vtype_legal(sews[s], l, ELEN)) continue;
            foreach (vv_instrs[k]) begin
                c = '{instr    : vv_instrs[k],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : VD_REG,
                      vs2      : VS2_REG,
                      scalar   : '0};
                run_reject_case(c, "vs1 overlaps low part of vd");
                c.vs1 = VS1_REG; c.vs2 = VD_REG;
                run_reject_case(c, "vs2 overlaps low part of vd");
            end
            foreach (vx_instrs[k]) begin
                c = '{instr    : vx_instrs[k],
                      sew      : sews[s],
                      lmul_log2: l,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : 0,
                      vs2      : VD_REG,
                      scalar   : 32'h3};
                run_reject_case(c, "vs2 overlaps low part of vd");
            end
        end

        // 2*SEW = 64 > ELEN
        begin
            foreach (vv_instrs[k]) begin
                c = '{instr    : vv_instrs[k],
                      sew      : 32,
                      lmul_log2: 0,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : VS1_REG,
                      vs2      : VS2_REG,
                      scalar   : '0};
                run_reject_case(c, "2*SEW = 64");
            end
            foreach (vx_instrs[k]) begin
                c = '{instr    : vx_instrs[k],
                      sew      : 32,
                      lmul_log2: 0,
                      avl      : AVL_MAX,
                      vd       : VD_REG,
                      vs1      : 0,
                      vs2      : VS2_REG,
                      scalar   : 32'h3};
                run_reject_case(c, "2*SEW = 64");
            end
        end
    endtask

    initial begin
        int unsigned fn_cases, fn_failed, fn_errors;

        do_reset();

        $display("---- part 1: vwmul[u|su].v[vx] functional sweep");
        run_sweep();
        fn_cases  = case_count;
        fn_failed = case_failed;
        fn_errors = error_count;

        $display("---- part 2: reserved encodings (must be rejected)");
        run_rejects();

        // summary
        repeat (5) @(posedge clk_i);
        $display("--------------------------------------------------------------");
        $display("tb_vpu_top_vwmul part 1 (functional): %0d cases, %0d failed, %0d errors",
                 fn_cases, fn_failed, fn_errors);
        $display("tb_vpu_top_vwmul part 2 (rejects)   : %0d cases, %0d failed, %0d errors",
                 case_count - fn_cases, case_failed - fn_failed, error_count - fn_errors);
        $display("tb_vpu_top_vwmul total: %0d cases, %0d failed, %0d errors",
                 case_count, case_failed, error_count);
        if (error_count == 0) $display("PASS");
        else                  $fatal(1, "FAIL");
        $finish;
    end

endmodule
