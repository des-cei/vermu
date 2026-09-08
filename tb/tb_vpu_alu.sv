// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

`timescale 1ns/1ps

module tb_vpu_alu;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;

    logic clk_i;
    logic rst_ni;

    logic         x_issue_valid;
    logic         x_issue_ready;
    x_issue_req_t x_issue_req;
    x_issue_resp_t x_issue_resp;
    logic         x_register_valid;
    logic         x_register_ready;
    x_register_t  x_register;
    logic         x_commit_valid;
    x_commit_t    x_commit;
    logic         x_result_valid;
    logic         x_result_ready;
    x_result_t    x_result;

    localparam logic [6:0] OPCODE_OP_V = 7'h57;
    localparam logic [31:0] EXPECTED_VADD_LANE0 = 32'h4444_4443;

    // Tail / mask policy
    localparam logic VTA = 1'b1;
    localparam logic VMA = 1'b1;

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    vpu_top #(
        .NrRgprPorts    (X_NUM_RS),
        .XLEN           (X_RFR_WIDTH),
        .readregflags_t (readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t           (id_t),
        .hartid_t       (hartid_t),
        .x_issue_req_t  (x_issue_req_t),
        .x_issue_resp_t (x_issue_resp_t),
        .x_register_t   (x_register_t),
        .x_commit_t     (x_commit_t),
        .x_result_t     (x_result_t),
        .obi_req_t      (obi_req_t),
        .obi_resp_t     (obi_resp_t)
    ) dut (
        .clk_i,
        .rst_ni,
        .x_issue_valid_i   (x_issue_valid),
        .x_issue_ready_o   (x_issue_ready),
        .x_issue_req_i     (x_issue_req),
        .x_issue_resp_o    (x_issue_resp),
        .x_register_i      (x_register),
        .x_register_valid_i(x_register_valid),
        .x_register_ready_o(x_register_ready),
        .x_commit_valid_i  (x_commit_valid),
        .x_commit_i        (x_commit),
        .x_result_valid_o  (x_result_valid),
        .x_result_ready_i  (x_result_ready),
        .x_result_o        (x_result),
        .masters_resp_i    ('0),
        .masters_req_o     ()
    );

    cvxif_cpu_model xif_model (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .x_issue_valid_o      (x_issue_valid),
        .x_issue_ready_i      (x_issue_ready),
        .x_issue_req_o        (x_issue_req),
        .x_issue_resp_i       (x_issue_resp),

        .x_register_o         (x_register),
        .x_register_valid_o   (x_register_valid),
        .x_register_ready_i   (x_register_ready),

        .x_commit_valid_o     (x_commit_valid),
        .x_commit_o           (x_commit),

        .x_result_i           (x_result),
        .x_result_valid_i     (x_result_valid),
        .x_result_ready_o     (x_result_ready)
    );

    function automatic logic [10:0] make_vtype(
        input logic [2:0] vsew,
        input logic [2:0] vlmul,
        input logic       vta,
        input logic       vma
    );

        logic [10:0] vtype;

        vtype = '0;

        vtype[2:0] = vlmul;
        vtype[5:3] = vsew;
        vtype[6]   = vta;
        vtype[7]   = vma;

        return vtype;

    endfunction

    function automatic logic [31:0] make_vsetivli(
        input logic [4:0] rd,
        input logic [4:0] avl,
        input logic [10:0] vtype
    );
        make_vsetivli = '0;

        make_vsetivli[31:30] = 2'b11;
        make_vsetivli[29:20] = vtype;
        make_vsetivli[19:15] = avl;
        make_vsetivli[14:12] = FMT_OPCFG_CSRRCI;
        make_vsetivli[11:7]  = rd;
        make_vsetivli[6:0]   = OPCODE_OP_V;

        return make_vsetivli;

    endfunction

    function automatic logic [31:0] make_arith(
        input logic [5:0] opcode,
        input logic [4:0] vd,
        input logic [4:0] vs1,
        input logic [4:0] vs2,
        input logic [2:0] funct3
    );
        make_arith = '0;
        make_arith[31:26] = opcode;
        make_arith[25]    = 1'b1;
        make_arith[24:20] = vs2;
        make_arith[19:15] = vs1;
        make_arith[14:12] = funct3;
        make_arith[11:7]  = vd;
        make_arith[6:0]   = OPCODE_OP_V;
    endfunction

    logic [10:0] vtype;

    initial begin    

        rst_ni = 1'b0;
        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;

        vtype = make_vtype(SEW_32, LMUL_1, VTA, VMA);
        xif_model.send_instruction( make_vsetivli(5'd5, 5'd2, vtype), 1, 4'd7);        

        wait(x_issue_resp.accept);
        xif_model.send_instruction(make_arith(6'b000000, 5'd3, 5'd1, 5'd2, FMT_OPIVV), 1, 4'd8); // vadd.vv

        wait(x_issue_resp.accept);
        xif_model.send_instruction(make_arith(6'b000101, 5'd3, 5'd1, 5'd2, FMT_OPIVV), 1, 4'd9); // vminu.vv

        wait(x_issue_resp.accept);
        xif_model.send_instruction(make_arith(6'b000000, 5'd3, 5'd3, 5'd2, FMT_OPIVI_CSRRC), 1, 4'd10); // vadd.vi

        // Wait for last instruction to finish
        wait(x_result_valid && x_result.id == 4'd10);
        repeat (2) @(posedge clk_i);

        $display("PASS");
        $finish;

    end

endmodule