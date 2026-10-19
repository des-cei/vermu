// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_top
import rvv_instr_pkg::*;
import vpu_pkg::*;
#(
    // CVXIF Types
    parameter  int unsigned NrRgprPorts         = 3,
    parameter  int unsigned XLEN                = 32,
    parameter  type         readregflags_t      = logic,
    parameter  type         writeregflags_t     = logic,
    parameter  type         id_t                = logic,
    parameter  type         hartid_t            = logic,
    parameter  type         x_issue_req_t       = logic,
    parameter  type         x_issue_resp_t      = logic,
    parameter  type         x_register_t        = logic,
    parameter  type         x_commit_t          = logic,
    parameter  type         x_result_t          = logic,
    localparam type         registers_t         = logic [NrRgprPorts-1:0][XLEN-1:0],
    parameter  type         obi_req_t           = logic,
    parameter  type         obi_resp_t          = logic,
    parameter  int unsigned EXT_XBAR_NMASTER    = VPU_N_IPU
    
) ( 

    input logic               clk_i,   
    input logic               rst_ni,
    // CVXIF Interface
    input  logic              x_issue_valid_i,
    output logic              x_issue_ready_o,
    input  x_issue_req_t      x_issue_req_i,
    output x_issue_resp_t     x_issue_resp_o,
    input  x_register_t       x_register_i,
    input  logic              x_register_valid_i,
    output logic              x_register_ready_o,
    input  logic              x_commit_valid_i,
    input  x_commit_t         x_commit_i,
    output logic              x_result_valid_o,
    input  logic              x_result_ready_i,
    output x_result_t         x_result_o,

    input  obi_resp_t [EXT_XBAR_NMASTER-1:0] masters_resp_i,
    output obi_req_t  [EXT_XBAR_NMASTER-1:0] masters_req_o
);

    // Issue interface signals
    x_issue_req_t  issue_req;
    x_issue_resp_t issue_resp;
    logic issue_valid, issue_ready;

    // Register interface signals   
    x_register_t register;
    logic register_valid, register_ready;

    // Commit interface signals
    x_commit_t commit;
    logic commit_valid;

    //Result interface
    x_result_t result;
    logic result_valid, result_ready;

    // Issue and Register interface
    assign x_issue_ready_o      = issue_ready; 
    assign x_issue_resp_o       = issue_resp;
    assign x_register_ready_o   = register_ready;
    assign x_result_o           = result;
    assign x_result_valid_o     = result_valid;

    assign issue_req            = x_issue_req_i;
    assign issue_valid          = x_issue_valid_i;
    assign register             = x_register_i;
    assign register_valid       = x_register_valid_i;
    assign commit               = x_commit_i;
    assign commit_valid         = x_commit_valid_i;
    assign result_ready         = x_result_ready_i;


    ///////////////
    // VERMU 2.0 //
    ///////////////

    //Interface instance 
    if_xif_exe xif_exe_valu_i ();
    if_xif_exe xif_exe_vlsu_i ();
    if_xif_exe xif_exe_vsld_i ();

    vpu_control_unit #(
        .NrRgprPorts      (NrRgprPorts),
        .readregflags_t   (readregflags_t),
        .writeregflags_t  (writeregflags_t),
        .id_t             (id_t),
        .hartid_t         (hartid_t),
        .x_issue_req_t    (x_issue_req_t),
        .x_issue_resp_t   (x_issue_resp_t),
        .x_register_t     (x_register_t),
        .x_commit_t       (x_commit_t),
        .x_result_t       (x_result_t),
        .registers_t      (registers_t)
    ) i_vpu_control_unit (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .x_issue_valid_i     (issue_valid),
        .x_issue_ready_o     (issue_ready),
        .x_issue_req_i       (issue_req),
        .x_issue_resp_o      (issue_resp),
        .x_register_valid_i  (register_valid),
        .x_register_i        (register),
        .x_register_ready_o  (register_ready),
        .x_commit_valid_i    (commit_valid),
        .x_commit_i          (commit),
        .x_result_valid_o    (result_valid),
        .x_result_ready_i    (result_ready),
        .x_result_o          (result),  
        .if_wrapper_exe_valu (xif_exe_valu_i.xif_wrapper),
        .if_wrapper_exe_vlsu (xif_exe_vlsu_i.xif_wrapper),
        .if_wrapper_exe_vsld (xif_exe_vsld_i.xif_wrapper)
    );

    dw_t vrf_wdata   [2:0];
    dw_t vrf_rdata1  [2:0];
    dw_t vrf_rdata2  [2:0];
    dw_t vrf_vd_data [2:0];

    dw_t simd_result, vlsu_result, vsld_result;

    assign vrf_wdata[FU_VALU] = simd_result;
    assign vrf_wdata[FU_VLSU] = vlsu_result;
    assign vrf_wdata[FU_VSLD] = vsld_result;

    vpu_vregfile vregfile_i(
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .wdata_i         (vrf_wdata),
        .rdata1_o        (vrf_rdata1),
        .rdata2_o        (vrf_rdata2),
        .rdata_vd_o      (vrf_vd_data),
        .if_monitor_valu (xif_exe_valu_i.register_file),
        .if_monitor_vlsu (xif_exe_vlsu_i.register_file),
        .if_monitor_vsld (xif_exe_vsld_i.register_file)
    );

    simd_controller simd_controller_i (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .op_s1_i          (vrf_rdata1[FU_VALU]),
        .op_s2_i          (vrf_rdata2[FU_VALU]),
        .op_d_i           (vrf_vd_data[FU_VALU]), 
        .is_signed_i      ('0), // TODO  
        .carry_i          ('0), // TODO   
        .result_o         (simd_result),  
        .if_exe_wrapper   (xif_exe_valu_i.exe_unit)
    );

    obi_lsu_top #(
        .obi_req_t       (obi_req_t),
        .obi_resp_t      (obi_resp_t),
        .EXT_XBAR_NMASTER(EXT_XBAR_NMASTER)
    ) obi_lsu_top_i (
        .clk_i             (clk_i),   
        .rst_ni            (rst_ni),
        .data_i            (vrf_rdata1[FU_VLSU]),   // TODO: rdata1?
        .data_o            (vlsu_result),
        .if_exe_wrapper    (xif_exe_vlsu_i.exe_unit),
        .masters_resp_i    (masters_resp_i),
        .masters_req_o     (masters_req_o) 
    );
    
    vpu_sldu vsld_i (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .op_s1_i        (vrf_rdata1[FU_VSLD]),
        .op_s2_i        (vrf_rdata2[FU_VSLD]),
        .op_d_i         (vrf_vd_data[FU_VSLD]),
        .result_o       (vsld_result),
        .if_exe_wrapper (xif_exe_vsld_i.exe_unit)
    );

endmodule