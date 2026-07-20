// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

/*
    THINGS TO BEAR IN MIND
    Pendanto to handle instruction illegality. In cases in which instruction encoding is reserved,
    instruction should not be accepted. Conditions:
    -> OP-V
    -> Load-Store:
      - EMUL = (EEW/SEW)*LMUL. EMUL>8 or EMUL<1/8 is out-of-range
    -> CSRs

*/

module vpu_control_unit
import cvxif_types_pkg::*;
import rvv_instr_pkg::vec_instr_e;
import vpu_pkg::*;
#(
    parameter  int unsigned NrRgprPorts         = 2,
    parameter  int unsigned XLEN                = 32,
    //X_ID_WIDTH?
    parameter               INSTR_DEPTH         = 4,
    parameter  type         readregflags_t      = logic,
    parameter  type         writeregflags_t     = logic,
    parameter  type         id_t                = logic,
    parameter  type         hartid_t            = logic,
    parameter  type         x_issue_req_t       = logic,
    parameter  type         x_issue_resp_t      = logic,
    parameter  type         x_register_t        = logic,
    parameter  type         x_commit_t          = logic,
    parameter  type         x_result_t          = logic,
    localparam type         registers_t         = logic [NrRgprPorts-1:0][XLEN-1:0]
)(
    input  logic              clk_i,
    input  logic              rst_ni,
    // CVXIF Interface 
    // Issue interface
    input  logic           x_issue_valid_i,
	output logic           x_issue_ready_o,
	input  x_issue_req_t   x_issue_req_i,
	output x_issue_resp_t  x_issue_resp_o,
    // Register interface
    input  logic           x_register_valid_i,
	input  x_register_t    x_register_i,
    output logic           x_register_ready_o,
    // Commit interface
	input  logic           x_commit_valid_i,
	input  x_commit_t      x_commit_i,
    // Result interface
	output logic           x_result_valid_o,
	input  logic           x_result_ready_i,
	output x_result_t      x_result_o,
    if_xif_exe.xif_wrapper if_wrapper_exe
);

    //////////////////////////////
    // User application signals //
    //////////////////////////////

    vec_instr_e vec_instr;

    /////////////////////////
    // xif_wrapper signals //
    /////////////////////////

    x_issue_t  temp_x_issue_i;
    x_issue_resp_t resp_instr_predecoder;
    logic     rs_valid_flag;                  

    // ISSUE FIFO signals (First FIFO INTERA)
    x_issue_t   issue_commit_i;         // Input to FIFO commit
    x_issue_t   issue_commit_o;         // Output from FIFO_commit - Input to FIFO_instr if POP in FIFO_commit + ~kill + accept
    logic       fifo_commit_full;
    logic       fifo_commit_empty;
    logic [1:0] fifo_commit_usage;
    logic       fifo_commit_push;
    logic       fifo_commit_pop;

    // TASK FIFO signals (Second FIFO INTERA)
    x_issue_t   issue_instr_o;          //Output from FIFO_instr - Input to execution block
    logic       fifo_instr_full;
    logic       fifo_instr_empty;
    logic [1:0] fifo_instr_usage;
    logic       fifo_instr_push;
    logic       fifo_instr_pop;

    // RESULT FIFO signals (Third FIFO INTERA)
    x_issue_fifo_res_t x_fifo_res_i; // Output from the execution block - Input to the FIFO_result
    x_issue_fifo_res_t x_fifo_res_o; // Output from the FIFO_result - Input to Result interface
    logic       fifo_res_full;
    logic       fifo_res_empty;
    logic [1:0] fifo_res_usage;
    logic       fifo_res_push;
    logic       fifo_res_pop;

    // Extended decoder
    vec_decoded_t decoder_req;
    logic         decoder_valid;         

    ///////////////////////////////
    // xif_wrapper control logic //
    ///////////////////////////////
    // assign  temp_x_issue_i.req      = x_issue_req_i;
    assign  temp_x_issue_i.req.instr  = x_issue_req_i.instr;
    assign  temp_x_issue_i.req.hartid = x_issue_req_i.hartid;
    assign  temp_x_issue_i.req.id     = x_issue_req_i.id;

    assign  temp_x_issue_i.resp     = '0;
    assign  temp_x_issue_i.register = x_register_i;

    vpu_xif_decoder #(
        .NrRgprPorts    (NrRgprPorts),
        .readregflags_t (readregflags_t),
        .x_issue_resp_t (x_issue_resp_t)   
    ) i_vpu_xif_decoder (
        .issue_valid_i  (x_issue_valid_i),
        .instr_i        (temp_x_issue_i.req.instr),
        .x_issue_resp_o (resp_instr_predecoder),
        .vec_instr_o    (vec_instr) 
    );



    assign x_register_ready_o           = x_issue_ready_o;
    assign x_issue_resp_o.accept        = resp_instr_predecoder.accept;
    assign x_issue_resp_o.writeback     = resp_instr_predecoder.writeback;
    assign x_issue_resp_o.register_read = resp_instr_predecoder.register_read;

    //rs_valid_flag goes high when the required source registers are available
    assign rs_valid_flag = &(temp_x_issue_i.register.rs_valid | ~ x_issue_resp_o.register_read); // Reduction over the 'or' of rs_valid + not(rs_valid_mask) // Obtained with a Truth table and corresponding Karnough map

    // COMMIT FIFO
    assign x_issue_ready_o = ~fifo_commit_full && ~fifo_instr_full && ~fifo_res_full && (fifo_commit_usage + fifo_instr_usage + fifo_res_usage < INSTR_DEPTH) && rs_valid_flag && rst_ni; // REAL FUNCTIONALITY, UNCOMMENT WHEN PROBLEM IS SORTED OUT! (rs_valid left out to avoid comb loops on the CPU side)

    // Fire issue. Fire when the issue is valid, is ready to accept and the issue is ready. 
    assign fifo_commit_push = x_issue_valid_i && x_issue_ready_o && x_issue_resp_o.accept; //If issue transaction then issue_req and issue_resp go to fifo, if not accepted or kill they will be discarded later on
    // USER: Assign data to be sent to fifo_commit     
    assign issue_commit_i.req      = temp_x_issue_i.req;  // Request to COMMIT_FIFO. Possibility to change FIFO input data.
    // assign issue_commit_i.resp     = x_issue_resp_o; // Corresponding Issue resp goes to the fifo as well
    assign issue_commit_i.resp     = x_issue_resp_o;
    assign issue_commit_i.register = x_register_i;

    // POP when commit_valid + issue transaction in progress or already done, if issue transaction has not happened yet then wait - All the commit transactions are in order matching with issue transactions
    assign fifo_commit_pop = ~fifo_commit_empty & x_commit_valid_i & (x_commit_i.id == issue_commit_o.req.id) & ~(x_commit_i.id == temp_x_issue_i.req.id && x_issue_valid_i && ~x_issue_ready_o);
  
    // INSTR FIFO                                                                         
    assign fifo_instr_push = fifo_commit_pop && !fifo_instr_full && !x_commit_i.commit_kill && issue_commit_o.resp.accept && !fifo_commit_empty; // We input data from FIFO_commit when fifo_commit_pop + no kill (commit) + accept instr.

    // RESULT FIFO
    assign fifo_res_push = x_fifo_res_i.result_valid_exec_o & ~fifo_res_full;   // Result coming from execution block
    assign fifo_res_pop  =  x_result_ready_i & ~fifo_res_empty; // Pop from result FIFO when FIFO is not empty and the result is accepted by the CPU


    ////////////////////
    // FIFO Instances //
    ////////////////////

    // First FIFO to go through the issue and commit stages
    // Inputs data when issue transaction, outputs data when commit_valid + issue transaction done or in progress
    fifo_v3 #(
        .FALL_THROUGH(1),                    //Combinational path if FIFO is empty
    //    .DATA_WIDTH  (64),
        .DEPTH       (INSTR_DEPTH),          // Maximum 4 instr to accept
        .dtype       (x_issue_t)           // We will input req and resp per instr
    //     .FPGA_EN     (CVA6Cfg.FPGA_EN) -> in the CVA6 repo there is an optimization for FPGA fifos, could be interesting
    ) fifo_commit_i (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),                   // TODO - if necessary to flush in new x-if standard when kill a batch of offloaded instructions
        .testmode_i(1'b0),
        .full_o    (fifo_commit_full),
        .empty_o   (fifo_commit_empty),
        .usage_o   (fifo_commit_usage),
        .data_i    (issue_commit_i),
        .push_i    (fifo_commit_push),       // We input data when issue is fired
        .data_o    (issue_commit_o),
        .pop_i     (fifo_commit_pop)
    );

    // Second FIFO to go through decode/execution and result stages when commit has been asserted
    fifo_v3 #(
    //   .FALL_THROUGH(1),                  // STANDARD FIFO, generates the required clock latency by the x-if
        .FALL_THROUGH(1),                   //Combinational path if FIFO is empty
    //   .DATA_WIDTH  (64),
        .DEPTH       (INSTR_DEPTH),         // Maximum 4 instr to execute
        .dtype       (x_issue_t)          // We will input req and resp per instr
    //   .FPGA_EN     (CVA6Cfg.FPGA_EN) -> in the CVA6 repo there is an optimization for FPGA fifos, could be interesting
    ) fifo_instruction_i (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (fifo_instr_full),
        .empty_o   (fifo_instr_empty),
        .usage_o   (fifo_instr_usage),
        .data_i    (issue_commit_o),
        .push_i    (fifo_instr_push),
        .data_o    (issue_instr_o),
        .pop_i     (fifo_instr_pop)
    );

    // Third FIFO to store the data comming from the execution block in case the CPU is not ready to receive it yet
    fifo_v3 #(
        .FALL_THROUGH(1),            //Combinational path if FIFO is empty
    //   .DATA_WIDTH  (64),
        .DEPTH       (INSTR_DEPTH),  // Maximum 4 instr to execute //
        .dtype       (x_issue_fifo_res_t)        // We will input req and resp per instr
    //   .FPGA_EN     (CVA6Cfg.FPGA_EN) -> in the CVA6 repo there is an optimization for FPGA fifos, could be interesting
    ) fifo_result_i (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (fifo_res_full),
        .empty_o   (fifo_res_empty),
        .usage_o   (fifo_res_usage),
        .data_i    (x_fifo_res_i),
        .push_i    (fifo_res_push), 
        .data_o    (x_fifo_res_o),
        .pop_i     (fifo_res_pop)
    );

    // TODO: Executer should be output of hazards detection logic
    // Send instruction to execution unit
    assign if_wrapper_exe.wrapper_exe_instr_valid = ~fifo_instr_empty;
    assign if_wrapper_exe.wrapper_exe_instr_issue = issue_instr_o;
    assign fifo_instr_pop = if_wrapper_exe.exe_wrapper_recv_instr_ready && ~fifo_instr_empty;
    //Interface: Execution block <-> FIFO_result
    assign if_wrapper_exe.wrapper_exe_recv_result_ready = ~fifo_res_full;       
    assign x_fifo_res_i = if_wrapper_exe.exe_wrapper_result;  // TODO: not in case of the CSRs

    always_comb begin
        x_result_valid_o  = ~fifo_res_empty;
        x_result_o.hartid = x_fifo_res_o.issue_exec_o.req.hartid; 
        x_result_o.id     = x_fifo_res_o.issue_exec_o.req.id; // Giving back the instr id
        x_result_o.rd     = x_fifo_res_o.issue_exec_o.req.instr[11:7]; // Giving back the dest reg
        x_result_o.we     = x_fifo_res_o.issue_exec_o.resp.writeback;
        x_result_o.data   = x_fifo_res_o.result_data_exec_o;  // Data processed by the custom instr
    end


    //////////////////////
    // Extended decoder //
    //////////////////////

    vpu_decoder #(
        .NrRgprPorts (NrRgprPorts),
        .id_t        (id_t),
        .hartid_t    (hartid_t),
        .registers_t (registers_t),
        .x_issue_t   (x_issue_t),
        .vec_instr_e (vec_instr_e)
    ) vpu_decoder_i (
        .clk_i             (clk_i),
        .req_valid_i       (fifo_instr_pop),
        .instr_req_i       (issue_instr_o),
        .vec_instr_i       (vec_instr),
        .dec_resp_valid_o  (decoder_valid), // To data hazard detection 
        .decoded_req_o     (decoder_req)
    );

endmodule: vpu_control_unit