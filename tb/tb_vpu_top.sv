// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module tb_vpu_top;

    import cvxif_types_pkg::*;
    import obi_pkg::*;

    logic clk_i;
    logic rst_ni;

    // Clock generation
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; // 100MHz clock
    end

    // Reset sequence
    initial begin
        rst_ni = 0;
        #20 rst_ni = 1;
    end

    // CVXIF interface
    logic          issue_valid, issue_ready;
    x_issue_req_t  issue_req;
    x_issue_resp_t issue_resp;
    x_register_t   register;
    logic          register_valid, register_ready, commit_valid;
    x_commit_t     commit;
    logic          result_valid, result_ready;
    x_result_t     result; 

    vpu_stimulus_gen #(
        .NrRgprPorts(cvxif_types_pkg::X_NUM_RS),
        .XLEN(32),
        .readregflags_t(readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t(id_t),
        .hartid_t(hartid_t),
        .x_issue_req_t(x_issue_req_t),
        .x_issue_resp_t(x_issue_resp_t),
        .x_register_t(x_register_t),
        .x_commit_t(x_commit_t),
        .x_result_t(x_result_t)
    ) i_stim_gen (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .x_issue_valid_o   (issue_valid),
        .x_issue_ready_i   (issue_ready),
        .x_issue_req_o     (issue_req),
        .x_issue_resp_i    (issue_resp),
        .x_register_o      (register),
        .x_register_valid_o(register_valid),
        .x_register_ready_i(register_ready),
        .x_commit_valid_o  (commit_valid),
        .x_commit_o        (commit),
        .x_result_valid_i  (result_valid),
        .x_result_ready_o  (result_ready),
        .x_result_i        (result)
    );

    vpu_top #(
        .NrRgprPorts    (cvxif_types_pkg::X_NUM_RS),
        .XLEN           (cvxif_types_pkg::X_RFR_WIDTH),
        .readregflags_t (cvxif_types_pkg::readregflags_t),
        .writeregflags_t(cvxif_types_pkg::writeregflags_t),
        .id_t           (cvxif_types_pkg::id_t),
        .hartid_t       (cvxif_types_pkg::hartid_t),
        .x_issue_req_t  (cvxif_types_pkg::x_issue_req_t),
        .x_issue_resp_t (cvxif_types_pkg::x_issue_resp_t),
        .x_register_t   (cvxif_types_pkg::x_register_t),
        .x_commit_t     (cvxif_types_pkg::x_commit_t),
        .x_result_t     (cvxif_types_pkg::x_result_t),
        .obi_req_t      (obi_pkg::obi_req_t),
        .obi_resp_t     (obi_pkg::obi_resp_t)
    ) i_vpu (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .x_issue_valid_i   (issue_valid),
        .x_issue_ready_o   (issue_ready),
        .x_issue_req_i     (issue_req),
        .x_issue_resp_o    (issue_resp),
        .x_register_i      (register),
        .x_register_valid_i(register_valid),
        .x_register_ready_o(register_ready),
        .x_commit_valid_i  (commit_valid),
        .x_commit_i        (commit),
        .x_result_valid_o  (result_valid),
        .x_result_ready_i  (result_ready),
        .x_result_o        (result),
        .masters_resp_i    (),
        .masters_req_o     ()
    );

    vpu_pipeline_checker #(
        .NrRgprPorts    (cvxif_types_pkg::CVE2Cfg.X_NUM_RS),
        .XLEN           (32),
        .readregflags_t (readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t           (id_t),
        .hartid_t       (hartid_t),
        .x_issue_req_t  (x_issue_req_t),
        .x_issue_resp_t (x_issue_resp_t),
        .x_register_t   (x_register_t),
        .x_commit_t     (x_commit_t),
        .x_result_t     (x_result_t)
    ) i_checker (
        .clk_i                      (clk_i),
        .rst_ni                     (rst_ni),
        .x_issue_req_i              (issue_req),
        .vpu_dbg_operation_i        (i_vpu.debug_if.operation),
        .vpu_dbg_is_narrowing_i     (1'b0),
        .vpu_dbg_rdata1_i           (i_vpu.debug_if.rdata1),
        .vpu_dbg_rdata2_i           (i_vpu.debug_if.vrf_rdata2),
        .vpu_dbg_vd_old_i           (i_vpu.debug_if.vrf_vd_data),
        .vpu_dbg_simd_result_valid_i(i_vpu.debug_if.simd_result_valid),
        .vpu_dbg_result_i           (i_vpu.debug_if.result)
    );

endmodule