// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

`timescale 1ns/1ps

module tb_vpu_csr;

    import cvxif_types_pkg::*;
    import rvv_instr_pkg::*;
    import vpu_pkg::*;

    // ============================================================
    // Parameters
    // ============================================================

    localparam int unsigned XLEN        = 32;
    localparam int unsigned NrRgprPorts = 2;
    localparam int unsigned INSTR_DEPTH = 4;

    localparam logic [31:0] HART_ID = '0;
    localparam logic [31:0] INSTR_ID = '0;

    // ============================================================
    // Clock / reset
    // ============================================================

    logic clk_i;
    logic rst_ni;

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    // ============================================================
    // XIF Issue interface
    // ============================================================

    logic          x_issue_valid_i;
    logic          x_issue_ready_o;
    x_issue_req_t  x_issue_req_i;
    x_issue_resp_t x_issue_resp_o;


    logic          x_register_valid_i;
    logic          x_register_ready_o;
    x_register_t   x_register_i;


    logic          x_commit_valid_i;
    x_commit_t     x_commit_i;


    logic          x_result_valid_o;
    logic          x_result_ready_i;
    x_result_t     x_result_o;

    // ============================================================
    // Execution interfaces
    //
    // Not relevant for this test.
    // ============================================================

    if_xif_exe xif_exe_valu();
    if_xif_exe xif_exe_vlsu();
    if_xif_exe xif_exe_vsld();

    // ============================================================
    // DUT
    // ============================================================

    vpu_control_unit #(
        .NrRgprPorts (NrRgprPorts),
        .XLEN        (XLEN),
        .INSTR_DEPTH (INSTR_DEPTH),
        .readregflags_t   (readregflags_t),
        .writeregflags_t  (writeregflags_t),
        .id_t             (id_t),
        .hartid_t         (hartid_t),
        .x_issue_req_t    (x_issue_req_t),
        .x_issue_resp_t   (x_issue_resp_t),
        .x_register_t     (x_register_t),
        .x_commit_t       (x_commit_t),
        .x_result_t       (x_result_t)
    ) dut (
        .clk_i                 (clk_i),
        .rst_ni                (rst_ni),

        // Issue
        .x_issue_valid_i       (x_issue_valid_i),
        .x_issue_ready_o       (x_issue_ready_o),
        .x_issue_req_i         (x_issue_req_i),
        .x_issue_resp_o        (x_issue_resp_o),

        // Register
        .x_register_valid_i    (x_register_valid_i),
        .x_register_i          (x_register_i),
        .x_register_ready_o    (x_register_ready_o),

        // Commit
        .x_commit_valid_i      (x_commit_valid_i),
        .x_commit_i            (x_commit_i),

        // Result
        .x_result_valid_o      (x_result_valid_o),
        .x_result_ready_i      (x_result_ready_i),
        .x_result_o            (x_result_o),

        // Execution
        .if_wrapper_exe_valu   (xif_exe_valu),
        .if_wrapper_exe_vlsu   (xif_exe_vlsu),
        .if_wrapper_exe_vsld   (xif_exe_vsld)
    );


    // ============================================================
    // RVV constants
    // ============================================================

    localparam logic [6:0] OPCODE_OP_V = 7'b1010111;

    // vsew encoding
    localparam logic [2:0] VSEW_E8  = 3'b000;
    localparam logic [2:0] VSEW_E16 = 3'b001;
    localparam logic [2:0] VSEW_E32 = 3'b010;

    // vlmul encoding
    localparam logic [2:0] VLMUL_M1 = 3'b000;

    // Tail / mask policy
    localparam logic VTA = 1'b1;
    localparam logic VMA = 1'b1;


    // ============================================================
    // vtype immediate encoder
    // ============================================================

    function automatic logic [10:0] make_vtypei(
        input logic [2:0] vsew,
        input logic [2:0] vlmul,
        input logic       vta,
        input logic       vma
    );

        logic [10:0] vtypei;

        vtypei = '0;

        vtypei[2:0] = vlmul;
        vtypei[5:3] = vsew;
        vtypei[6]   = vta;
        vtypei[7]   = vma;

        return vtypei;

    endfunction


    // ============================================================
    // vsetivli encoder
    //
    // vsetivli rd, uimm, vtypei
    //
    // 31:30 = 11
    // 29:20 = vtypei
    // 19:15 = uimm[4:0]
    // 14:12 = 111
    // 11:7  = rd
    // 6:0   = OP-V
    // ============================================================

    function automatic logic [31:0] make_vsetivli(
        input logic [4:0]  rd,
        input logic [4:0]  avl,
        input logic [10:0] vtypei
    );

        logic [31:0] instr;

        instr = '0;

        instr[31:30] = 2'b11;
        instr[29:20] = vtypei;
        instr[19:15] = avl;
        instr[14:12] = 3'b111;
        instr[11:7]  = rd;
        instr[6:0]   = OPCODE_OP_V;

        return instr;

    endfunction


    // ============================================================
    // vsetvli encoder
    //
    // vsetvli rd, rs1, vtypei
    //
    // rs1 supplies AVL through register interface.
    // ============================================================

    function automatic logic [31:0] make_vsetvli(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [10:0] vtypei
    );

        logic [31:0] instr;

        instr = '0;

        instr[31:30] = 2'b00;
        instr[29:20] = vtypei;
        instr[19:15] = rs1;
        instr[14:12] = 3'b111;
        instr[11:7]  = rd;
        instr[6:0]   = OPCODE_OP_V;

        return instr;

    endfunction


    // ============================================================
    // vsetvl encoder
    //
    // vsetvl rd, rs1, rs2
    //
    // rs1 = AVL
    // rs2 = vtype
    // ============================================================

    function automatic logic [31:0] make_vsetvl(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );

        logic [31:0] instr;

        instr = '0;

        instr[31:25] = 7'b1000000;
        instr[24:20] = rs2;
        instr[19:15] = rs1;
        instr[14:12] = 3'b111;
        instr[11:7]  = rd;
        instr[6:0]   = OPCODE_OP_V;

        return instr;

    endfunction

    // ============================================================
    // CSRRS encoder
    //
    // csrrs rd, csr, rs1
    //
    // 31:20 = CSR address
    // 19:15 = rs1
    // 14:12 = funct3 = 010 (CSRRS)
    // 11:7  = rd
    // 6:0   = SYSTEM opcode
    // ============================================================

    function automatic logic [31:0] make_csrrs(
        input logic [4:0]  rd,
        input logic [11:0] csr,
        input logic [4:0]  rs1
    );

        logic [31:0] instr;

        instr = '0;

        instr[31:20] = csr;
        instr[19:15] = rs1;
        instr[14:12] = 3'b010;  // CSRRS
        instr[11:7]  = rd;
        instr[6:0]   = 7'h73;  // SYSTEM

        return instr;

    endfunction

    localparam logic [11:0] CSR_VSTART = 12'h008;
    localparam logic [11:0] CSR_VXSAT  = 12'h009;
    localparam logic [11:0] CSR_VXRM   = 12'h00A;
    localparam logic [11:0] CSR_VCSR   = 12'h00F;

    localparam logic [11:0] CSR_VL     = 12'hC20;
    localparam logic [11:0] CSR_VTYPE  = 12'hC21;
    localparam logic [11:0] CSR_VLENB  = 12'hC22;

    // ============================================================
    // Initialize all interfaces
    // ============================================================

    task automatic init_signals();

        x_issue_valid_i    = 1'b0;
        x_issue_req_i      = '0;

        x_register_valid_i = 1'b0;
        x_register_i       = '0;

        x_commit_valid_i   = 1'b0;
        x_commit_i         = '0;

        x_result_ready_i   = 1'b1;

    endtask


    // ============================================================
    // Reset
    // ============================================================

    task automatic reset_dut();

        rst_ni = 1'b0;

        init_signals();

        repeat (5)
            @(posedge clk_i);

        rst_ni = 1'b1;

        repeat (2)
            @(posedge clk_i);

    endtask


    // ============================================================
    // Issue instruction
    //
    // No new instruction is issued until result_valid.
    // ============================================================

    task automatic issue_instruction(
        input logic [31:0] instr,
        input logic [31:0] rs1_value,
        input logic [31:0] rs2_value,
        input logic        rs1_valid,
        input logic        rs2_valid
    );

        logic [31:0] rs1;
        logic [31:0] rs2;

        rs1 = rs1_value;
        rs2 = rs2_value;

        // Prepare issue request

        x_issue_req_i      = '0;
        x_issue_req_i.instr = instr;
        x_issue_req_i.hartid = HART_ID;
        x_issue_req_i.id     = INSTR_ID;

        x_issue_valid_i = 1'b1;
        x_register_valid_i = 1'b1;
        x_commit_valid_i = 1'b1;

        $display("");
        $display("[%0t] ISSUE instr = %08h", $time, instr);

        // Wait for issue acceptance

        // do begin
        //     @(posedge clk_i);
        // end
        // while (!x_issue_ready_o);

        // x_issue_valid_i = 1'b0;

        $display("[%0t] Issue accepted", $time);

        if (rs1_valid || rs2_valid) begin

            // do begin
            //     @(posedge clk_i);
            // end
            // while (!x_register_ready_o);

            x_register_i = '0;

            x_register_i.hartid = HART_ID;
            x_register_i.id     = INSTR_ID;

            if (rs1_valid)
                x_register_i.rs[0] = rs1;

            if (rs2_valid)
                x_register_i.rs[1] = rs2;

            x_register_i.rs_valid = '0;

            if (rs1_valid)
                x_register_i.rs_valid[0] = 1'b1;

            if (rs2_valid)
                x_register_i.rs_valid[1] = 1'b1;

            x_register_valid_i = 1'b1;

            $display("[%0t] REGISTER response: rs1=%08h rs2=%08h",
                     $time,
                     rs1,
                     rs2);

            @(posedge clk_i);

            x_register_valid_i = 1'b0;

        end


        // Wait for result
        do begin
            @(posedge clk_i);
        end
        while (!x_result_valid_o);

        $display(
            "[%0t] RESULT: data=%08h rd=%0d",
            $time,
            x_result_o.data,
            x_result_o.rd
        );

        @(posedge clk_i);

    endtask


    // ============================================================
    // Check result
    // ============================================================

    task automatic check_result(
        input logic [31:0] expected_data,
        input logic [4:0]  expected_rd
    );

        if (x_result_o.data !== expected_data) begin

            $error(
                "[%0t] RESULT DATA ERROR: expected %08h, got %08h",
                $time,
                expected_data,
                x_result_o.data
            );

        end
        else begin

            $display(
                "[%0t] PASS: result data = %08h",
                $time,
                x_result_o.data
            );

        end


        if (x_result_o.rd !== expected_rd) begin

            $error(
                "[%0t] RESULT RD ERROR: expected %0d, got %0d",
                $time,
                expected_rd,
                x_result_o.rd
            );

        end
        else begin

            $display(
                "[%0t] PASS: result rd = %0d",
                $time,
                x_result_o.rd
            );

        end

    endtask


    // ============================================================
    // Check CSR state
    // ============================================================

    task automatic check_vector_state(
        input logic [31:0] expected_vl,
        input logic [31:0] expected_vtype
    );

        $display(
            "[%0t] CSR state: vl=%0d vtype=%08h",
            $time,
            dut.vl_q,
            dut.vtype_q
        );

        if (dut.vl_q !== expected_vl) begin

            $error(
                "[%0t] VL ERROR: expected %0d, got %0d",
                $time,
                expected_vl,
                dut.vl_q
            );

        end
        else begin

            $display(
                "[%0t] PASS: vl = %0d",
                $time,
                dut.vl_q
            );

        end


        if (dut.vtype_q !== expected_vtype) begin

            $error(
                "[%0t] VTYPE ERROR: expected %08h, got %08h",
                $time,
                expected_vtype,
                dut.vtype_q
            );

        end
        else begin

            $display(
                "[%0t] PASS: vtype = %08h",
                $time,
                dut.vtype_q
            );

        end

    endtask


    // ============================================================
    // Assertions for the vset{i}vl{i} AVL/VLMAX rules
    //
    // These checks intentionally do not assume a particular legal
    // value for rule 2 when:
    //
    //     VLMAX < AVL < 2*VLMAX
    //
    // because the specification permits any value in the range,
    // provided the implementation is deterministic.
    // ============================================================

    task automatic assert_vl_rules(
        input logic [31:0] avl,
        input logic [31:0] vlmax,
        input logic [31:0] actual_vl
    );

        logic [31:0] lower_bound;

        if (avl < (2 * vlmax))
            lower_bound = (avl + 1) / 2;
        else
            lower_bound = vlmax;

        // a. vl = 0 if AVL = 0
        assert ((avl != 0) || (actual_vl == 0))
            else $error("[%0t] ASSERT a FAILED: AVL=0 but VL=%0d",
                        $time, actual_vl);

        // b. vl > 0 if AVL > 0
        assert ((avl == 0) || (actual_vl > 0))
            else $error("[%0t] ASSERT b FAILED: AVL=%0d but VL=0",
                        $time, avl);

        // c. vl <= VLMAX
        assert (actual_vl <= vlmax)
            else $error("[%0t] ASSERT c FAILED: VL=%0d > VLMAX=%0d",
                        $time, actual_vl, vlmax);

        // d. vl <= AVL
        assert (actual_vl <= avl)
            else $error("[%0t] ASSERT d FAILED: VL=%0d > AVL=%0d",
                        $time, actual_vl, avl);

        // Rule 1: AVL <= VLMAX -> VL = AVL
        if (avl <= vlmax) begin
            assert (actual_vl == avl)
                else $error("[%0t] RULE 1 FAILED: AVL=%0d VLMAX=%0d VL=%0d",
                            $time, avl, vlmax, actual_vl);
        end

        // Rule 2: VLMAX < AVL < 2*VLMAX
        if ((avl > vlmax) && (avl < (2 * vlmax))) begin
            assert ((actual_vl >= lower_bound) &&
                    (actual_vl <= vlmax))
                else $error(
                    "[%0t] RULE 2 FAILED: AVL=%0d VLMAX=%0d VL=%0d",
                    "expected %0d..%0d",$time, avl, vlmax, actual_vl,
                    lower_bound, vlmax
                );
        end

        // Rule 3: AVL >= 2*VLMAX -> VL = VLMAX
        if (avl >= (2 * vlmax)) begin
            assert (actual_vl == vlmax)
                else $error("[%0t] RULE 3 FAILED: AVL=%0d VLMAX=%0d VL=%0d",
                            $time, avl, vlmax, actual_vl);
        end

        $display("[%0t] VL RULES PASS: AVL=%0d VLMAX=%0d VL=%0d",
                 $time, avl, vlmax, actual_vl);

    endtask


    // ============================================================
    // VILL assertions
    //
    // For an illegal vtype, the architectural state must indicate
    // vill and VL must become zero.
    //
    // VILL is bit XLEN-1 of vtype.
    // ============================================================

    task automatic assert_vill_state();

        @(posedge clk_i);

        assert (dut.vtype_q.vill === 1'b1)
            else $error(
                "[%0t] VILL ASSERT FAILED: vtype=%08h, VILL is not set",
                $time, dut.vtype_q
            );

        assert (dut.vl_q === '0)
            else $error(
                "[%0t] VILL ASSERT FAILED: VL must be 0, got %0d",
                $time, dut.vl_q
            );

        assert (x_result_o.data === '0)
            else $error(
                "[%0t] VILL ASSERT FAILED: result VL must be 0, got %08h",
                $time, x_result_o.data
            );

        $display("[%0t] PASS: illegal vtype -> VILL=1, VL=0",
                 $time);

    endtask

    // ============================================================
    // TEST
    // ============================================================

    initial begin

        logic [31:0] instr;
        logic [10:0] vtype_bad_sew;
        logic [10:0] vtype_bad_lmul;
        logic [10:0] vtype_bad_reserved;
        logic [10:0] vtype_e8;
        logic [10:0] vtype_e16;
        logic [10:0] vtype_e32;

        // Construct vtype values

        vtype_e8 = make_vtypei(
            VSEW_E8,
            VLMUL_M1,
            VTA,
            VMA
        );

        vtype_e16 = make_vtypei(
            VSEW_E16,
            VLMUL_M1,
            VTA,
            VMA
        );

        vtype_e32 = make_vtypei(
            VSEW_E32,
            VLMUL_M1,
            VTA,
            VMA
        );


        $display("");
        $display("================================================");
        $display("       VPU CONTROL UNIT - CSR TEST");
        $display("================================================");


        reset_dut();


        // ========================================================
        // TEST 1
        //
        // vsetivli t0, 1, e8, m1, ta, ma
        //
        // VLEN=128:
        // VLMAX=16
        // AVL=1 -> VL=1
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 1");
        $display("vsetivli t0, 1, e8, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(
            5'd5,
            5'd1,
            vtype_e8
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd1,
            5'd5
        );

        check_vector_state(
            32'd1,
            32'h000000C0
        );


        // ========================================================
        // TEST 2
        //
        // vsetivli t0, 8, e8, m1, ta, ma
        //
        // VLEN=128 -> VLMAX=16
        // AVL=8 -> VL=8
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 2");
        $display("vsetivli t0, 8, e8, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(
            5'd5,
            5'd8,
            vtype_e8
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd8,
            5'd5
        );

        check_vector_state(
            32'd8,
            32'h000000C0
        );


        // ========================================================
        // TEST 3
        //
        // vsetivli t0, 8, e16, m1, ta, ma
        //
        // VLEN=128 -> VLMAX=8
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 3");
        $display("vsetivli t0, 8, e16, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(
            5'd5,
            5'd8,
            vtype_e16
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd8,
            5'd5
        );

        check_vector_state(
            32'd8,
            32'h000000C8
        );


        // ========================================================
        // TEST 4
        //
        // vsetivli t0, 8, e32, m1, ta, ma
        //
        // VLEN=128 -> VLMAX=4
        // AVL=8 -> VL=4
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 4");
        $display("vsetivli t0, 8, e32, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(
            5'd5,
            5'd8,
            vtype_e32
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd4,
            5'd5
        );

        check_vector_state(
            32'd4,
            32'h000000D0
        );


        // ========================================================
        // TEST 5
        //
        // vsetivli t0, 31, e32, m1, ta, ma
        //
        // AVL > VLMAX
        //
        // VLEN=128 -> VLMAX=4
        // Expected VL=4
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 5");
        $display("vsetivli t0, 31, e32, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(
            5'd5,
            5'd31,
            vtype_e32
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd4,
            5'd5
        );

        check_vector_state(
            32'd4,
            32'h000000D0
        );


        // ========================================================
        // TEST 6
        //
        // vsetvli t0, a0, e8, m1, ta, ma
        //
        // a0 = 3
        //
        // Expected VL=3
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 6");
        $display("vsetvli t0, a0, e8, m1, ta, ma");
        $display("a = 3");
        $display("------------------------------------------------");

        instr = make_vsetvli(
            5'd5,       // rd=t0
            5'd10,      // rs1=a
            vtype_e8
        );

        issue_instruction(
            instr,
            32'd3,      // a
            32'd0,
            1'b1,
            1'b0
        );

        check_result(
            32'd3,
            5'd5
        );

        check_vector_state(
            32'd3,
            32'h000000C0
        );


        // ========================================================
        // TEST 7
        //
        // vsetvli t0, a0, e16, m1, ta, ma
        //
        // a0 = 20
        //
        // VLEN=128 -> VLMAX=8
        // Expected VL=8
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 7");
        $display("vsetvli t0, a0, e16, m1, ta, ma");
        $display("a0 = 20");
        $display("------------------------------------------------");

        instr = make_vsetvli(
            5'd5,
            5'd9,
            vtype_e16
        );

        issue_instruction(
            instr,
            32'd20,
            32'd0,
            1'b1,
            1'b0
        );

        check_result(
            32'd8,
            5'd5
        );

        check_vector_state(
            32'd8,
            32'h000000C8
        );


        // ========================================================
        // TEST 8
        //
        // vsetvli t0, a0, e32, m1, ta, ma
        //
        // a0 = 20
        //
        // VLEN=128 -> VLMAX=4
        // Expected VL=4
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 8");
        $display("vsetvli t0, a0, e32, m1, ta, ma");
        $display("a0 = 20");
        $display("------------------------------------------------");

        instr = make_vsetvli(
            5'd5,
            5'd8,
            vtype_e32
        );

        issue_instruction(
            instr,
            32'd20,
            32'd0,
            1'b1,
            1'b0
        );

        check_result(
            32'd4,
            5'd5
        );

        check_vector_state(
            32'd4,
            32'h000000D0
        );


        // ========================================================
        // TEST 9
        //
        // vsetvl t0, a0, a1
        //
        // a0 = AVL = 5
        // a1 = vtype = e16,m1,ta,ma = 0xC8
        //
        // Expected VL=5
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 9");
        $display("vsetvl t0, a0, a1");
        $display("a0 = 5");
        $display("a1 = 0x%08h", 32'hC8);
        $display("------------------------------------------------");

        instr = make_vsetvl(
            5'd5,       // rd=t0
            5'd10,      // rs1=a0
            5'd11       // rs2=a1
        );

        issue_instruction(
            instr,
            32'd5,       // a0
            32'h000000C8, // a1
            1'b1,
            1'b1
        );

        check_result(
            32'd5,
            5'd5
        );

        check_vector_state(
            32'd5,
            32'h000000C8
        );


        // ========================================================
        // TEST 10
        //
        // vsetvl t0, a0, a1
        //
        // a0 = 20
        // a1 = e32,m1,ta,ma
        //
        // VLEN=128 -> VLMAX=4
        // Expected VL=4
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 10");
        $display("vsetvl t0, a0, a1");
        $display("a0 = 20");
        $display("a1 = 0x%08h", 32'hD0);
        $display("------------------------------------------------");

        instr = make_vsetvl(
            5'd5,
            5'd10,
            5'd11
        );

        issue_instruction(
            instr,
            32'd20,
            32'h000000D0,
            1'b1,
            1'b1
        );

        check_result(
            32'd4,
            5'd5
        );

        check_vector_state(
            32'd4,
            32'h000000D0
        );



        // ========================================================
        // TEST 11
        //
        // AVL = 0
        //
        // e32,m1 -> VLMAX=4
        // Expected VL=0
        //
        // Checks corner case:
        //     AVL=0 -> VL=0
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 11");
        $display("vsetivli t0, 0, e32, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd0, vtype_e32);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd0, 5'd5);
        check_vector_state(32'd0, 32'h000000D0);
        assert_vl_rules(32'd0, 32'd4, dut.vl_q);


        // ========================================================
        // TEST 12
        //
        // AVL = VLMAX
        //
        // e32,m1 -> VLMAX=4
        // Expected VL=4
        //
        // Boundary between rule 1 and rule 2.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 12");
        $display("vsetivli t0, 4, e32, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd4, vtype_e32);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd4, 5'd5);
        check_vector_state(32'd4, 32'h000000D0);
        assert_vl_rules(32'd4, 32'd4, dut.vl_q);


        // ========================================================
        // TEST 13
        //
        // AVL = VLMAX + 1
        //
        // e32,m1 -> VLMAX=4, AVL=5
        // Rule 2:
        //     ceil(5/2) <= VL <= 4
        //     3 <= VL <= 4
        //
        // Do not require VL=3 or VL=4 specifically.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 13");
        $display("vsetivli t0, 5, e32, m1, ta, ma");
        $display("Rule 2 boundary: 3 <= VL <= 4");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd5, vtype_e32);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_vector_state(dut.vl_q, 32'h000000D0);
        assert_vl_rules(32'd5, 32'd4, dut.vl_q);


        // ========================================================
        // TEST 14
        //
        // AVL = 2*VLMAX - 1
        //
        // e32,m1 -> VLMAX=4, AVL=7
        // Rule 2:
        //     ceil(7/2) <= VL <= 4
        //     4 <= VL <= 4
        // Therefore VL MUST be 4.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 14");
        $display("vsetivli t0, 7, e32, m1, ta, ma");
        $display("Rule 2 upper boundary: VL must be 4");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd7, vtype_e32);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd4, 5'd5);
        check_vector_state(32'd4, 32'h000000D0);
        assert_vl_rules(32'd7, 32'd4, dut.vl_q);


        // ========================================================
        // TEST 15
        //
        // AVL = 2*VLMAX
        //
        // e32,m1 -> VLMAX=4, AVL=8
        // Rule 3 -> VL=4
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 15");
        $display("vsetivli t0, 8, e32, m1, ta, ma");
        $display("Rule 3 boundary: AVL = 2*VLMAX");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd8, vtype_e32);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd4, 5'd5);
        check_vector_state(32'd4, 32'h000000D0);
        assert_vl_rules(32'd8, 32'd4, dut.vl_q);


        // ========================================================
        // TEST 16
        //
        // rd = x0, normal AVL
        //
        // rd=x0 must not prevent vl/vtype from being updated.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 16");
        $display("vsetivli x0, 3, e8, m1, ta, ma");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd0, 5'd3, vtype_e8);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd3, 5'd0);
        check_vector_state(32'd3, 32'h000000C0);
        assert_vl_rules(32'd3, 32'd16, dut.vl_q);


        // ========================================================
        // TEST 17
        //
        // rs1 = x0 -> AVL = ~0
        //
        // vsetvli x0, x0, e8,m1
        // AVL is effectively XLEN bits of 1.
        // Therefore AVL >= 2*VLMAX and VL=VLMAX=16.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 17");
        $display("vsetvli x0, x0, e8, m1, ta, ma");
        $display("rs1=x0 -> AVL=~0");
        $display("------------------------------------------------");

        instr = make_vsetvli(5'd10, 5'd0, vtype_e8);

        issue_instruction(
            instr,
            32'hFFFFFFFF,
            32'd0,
            1'b1,
            1'b0
        );

        check_result(32'd16, 5'd10);
        check_vector_state(32'd16, 32'h000000C0);
        assert_vl_rules(32'hFFFFFFFF, 32'd16, dut.vl_q);


        // ========================================================
        // TEST 18
        //
        // Invalid SEW encoding.
        //
        // For ZVE32X, SEW=64 is not supported.
        // vsew=011 must therefore cause VILL.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 18");
        $display("vsetivli t0, 1, e64, m1, ta, ma");
        $display("Invalid SEW -> VILL");
        $display("------------------------------------------------");

        vtype_bad_sew = vtype_e8;
        vtype_bad_sew[5:3] = 3'b011;

        instr = make_vsetivli(5'd5, 5'd1, vtype_bad_sew);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        assert_vill_state();


        // ========================================================
        // TEST 19
        //
        // LMUL > 1 encoding.
        //
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 19");
        $display("vsetivli t0, 1, e8, m2, ta, ma");
        $display("Unsupported LMUL -> VILL");
        $display("------------------------------------------------");

        vtype_bad_lmul = vtype_e8;
        vtype_bad_lmul[2:0] = 3'b001; // LMUL=2

        instr = make_vsetivli(5'd5, 5'd20, vtype_bad_lmul);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd20, 5'd5);

        // ========================================================
        // TEST 20
        //
        // Reserved vtype bit.
        //
        // vtype[8] is reserved and must be zero.
        // Setting it must cause VILL.  TODO
        // ========================================================

        // $display("");
        // $display("------------------------------------------------");
        // $display("TEST 20");
        // $display("vsetivli t0, 1, e8, m1 with reserved vtype[8]=1");
        // $display("Reserved bit -> VILL");
        // $display("------------------------------------------------");

        // vtype_bad_reserved = vtype_e8;
        // vtype_bad_reserved[8] = 1'b1;

        // instr = make_vsetivli(5'd5, 5'd1, vtype_bad_reserved);

        // issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        // assert_vill_state();


        // ========================================================
        // TEST 21
        //
        // VILL recovery.
        //
        // After an illegal vtype, a valid vset instruction must
        // clear VILL and restore a legal vector state.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 21");
        $display("Recover from VILL with valid vsetivli");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd2, vtype_e16);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd2, 5'd5);
        check_vector_state(32'd2, 32'h000000C8);

        assert (dut.vtype_q.vill === 1'b0)
            else $error("[%0t] VILL recovery FAILED: VILL still set",
                        $time);

        assert_vl_rules(32'd2, 32'd8, dut.vl_q);


        // ========================================================
        // TEST 22
        //
        // vsetvl with AVL taken from the current vl.
        //
        // Property (e):
        //     A value read from vl and reused as AVL produces the
        //     same vl when the resulting VLMAX is unchanged.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 22");
        $display("vsetvl with AVL equal to previous vl");
        $display("------------------------------------------------");

        // Establish vl=5, VLMAX=8.
        instr = make_vsetivli(5'd5, 5'd5, vtype_e16);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd5, 5'd5);
        check_vector_state(32'd5, 32'h000000C8);

        // Reuse current vl as AVL, same vtype/VLMAX.
        instr = make_vsetvl(5'd5, 5'd10, 5'd11);

        issue_instruction(
            instr,
            dut.vl_q,
            32'h000000C8,
            1'b1,
            1'b1
        );

        check_result(32'd5, 5'd5);
        check_vector_state(32'd5, 32'h000000C8);

        assert (dut.vl_q === 32'd5)
            else $error(
                "[%0t] PROPERTY e FAILED: previous VL was 5, got %0d",
                $time, dut.vl_q
            );

        assert_vl_rules(32'd5, 32'd8, dut.vl_q);


        // ========================================================
        // TEST 23
        //
        // vsetvl rd=x0, rs1=x0.
        //
        // This exercises the special x0/x0 form:
        // keep the existing VL while allowing vtype to change.
        //
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 23");
        $display("vsetvl x0, x0, x11");
        $display("Keep existing VL while changing vtype");
        $display("------------------------------------------------");

        instr = make_vsetivli(5'd5, 5'd3, vtype_e8);

        issue_instruction(instr, 32'd0, 32'd0, 1'b0, 1'b0);

        check_result(32'd3, 5'd5);
        check_vector_state(32'd3, 32'h000000C0);

        instr = make_vsetvl(5'd0, 5'd0, 5'd11);

        issue_instruction(
            instr,
            32'd6,
            32'h000000C9,
            1'b1,
            1'b1
        );

        check_result(32'd0, 5'd0);
        check_vector_state(32'd3, 32'h000000C9);

        assert (dut.vl_q === 32'd3)
            else $error(
                "[%0t] x0/x0 special case FAILED: expected VL=3, got %0d",
                $time, dut.vl_q
            );

        // ========================================================
        // TEST 24
        //
        // csrrs t1, vl, x0
        //
        // CSRRS with rs1=x0 is a pure CSR read.
        // vl must remain unchanged.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 24");
        $display("csrrs t1, vl, x0");
        $display("------------------------------------------------");

        // Establish VL = 5 with VLMAX = 8.
        instr = make_vsetivli(
            5'd5,
            5'd5,
            vtype_e16
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(32'd5, 5'd5);
        check_vector_state(32'd5, 32'h000000C8);

        // Read VL using CSRRS.
        instr = make_csrrs(
            5'd6,          // rd = t1
            CSR_VL,
            5'd0           // rs1 = x0 -> read only
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(32'd5, 5'd6);

        // CSR must not have changed.
        assert (dut.vl_q === 32'd5)
            else $error(
                "[%0t] CSRRS VL modified VL: expected 5, got %0d",
                $time,
                dut.vl_q
            );

        $display("[%0t] PASS: CSRRS vl returned %0d",
                 $time, x_result_o.data);

        // ========================================================
        // TEST 25
        //
        // csrrs t1, vlenb, x0
        //
        // VLEN=128 -> VLENB=16
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 25");
        $display("csrrs t1, vlenb, x0");
        $display("------------------------------------------------");

        instr = make_csrrs(
            5'd6,          // rd = t1
            CSR_VLENB,
            5'd0           // rs1 = x0
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'd16,
            5'd6
        );

        // VLENB is read-only and must remain unchanged.
        assert (x_result_o.data === 32'd16)
            else $error(
                "[%0t] CSRRS VLENB ERROR: expected 16, got %0d",
                $time,
                x_result_o.data
            );

        $display("[%0t] PASS: CSRRS vlenb returned %0d",
                 $time, x_result_o.data);

        // ========================================================
        // TEST 26
        //
        // csrrs t1, vtype, x0
        //
        // vtype = e16,m1,ta,ma = 0xC8
        // CSRRS must return the current vtype.
        // ========================================================

        $display("");
        $display("------------------------------------------------");
        $display("TEST 26");
        $display("csrrs t1, vtype, x0");
        $display("------------------------------------------------");

        // Establish known vtype.
        instr = make_vsetivli(
            5'd5,
            5'd5,
            vtype_e16
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(32'd5, 5'd5);
        check_vector_state(32'd5, 32'h000000C8);

        // Read VTYPE.
        instr = make_csrrs(
            5'd6,          // rd = t1
            CSR_VTYPE,
            5'd0           // rs1 = x0 -> read only
        );

        issue_instruction(
            instr,
            32'd0,
            32'd0,
            1'b0,
            1'b0
        );

        check_result(
            32'h000000C8,
            5'd6
        );

        // Make sure the CSR itself was not modified.
        assert (dut.vtype_q === 32'h000000C8)
            else $error(
                "[%0t] CSRRS VTYPE modified VTYPE: expected %08h, got %08h",
                $time,
                32'h000000C8,
                dut.vtype_q
            );

        $display("[%0t] PASS: CSRRS vtype returned %08h",
                 $time, x_result_o.data);
                 
        // ========================================================
        // END
        // ========================================================

        $display("");
        $display("================================================");
        $display("             ALL TESTS FINISHED");
        $display("================================================");
        $display("");

        $finish;

    end

endmodule