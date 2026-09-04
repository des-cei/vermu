// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Based on xif_wrapper.sv from the INTERA-GROUP/xif_wrapper project
// (licensed under the Apache License 2.0).
// Modifications by Ane Corral (ane.corral@upm.es).

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
import rvv_instr_pkg::*;
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
    // if_xif_exe.xif_wrapper if_wrapper_exe,
    if_xif_exe.xif_wrapper if_wrapper_exe_valu,
    if_xif_exe.xif_wrapper if_wrapper_exe_vlsu,
    if_xif_exe.xif_wrapper if_wrapper_exe_vsld
);

    //////////////////////////////
    // User application signals //
    //////////////////////////////

    vec_instr_e vec_instr;
    logic disp_ready;
    x_issue_fifo_res_t vpu_fifo_res;

    // CSR signals
    vtype_t vtype_d, vtype_q;
    vl_t vl_d, vl_q;
    vl_t vstart_d, vstart_q;
    logic [VLENB_W-1:0] vlenb_d, vlenb_q;
    // vxsat --NA
    // vxrm  --NA
    // vcsr  --NA

    vec_instr_e issue_instr_op;
    logic vtype_valid, vtype_supported;
    x_issue_fifo_res_t csr_fifo_res;
    logic csr_lecture_valid;
    logic [X_RFW_WIDTH-1:0] csr_lecture;

    /////////////////////////
    // xif_wrapper signals //
    /////////////////////////

    x_issue_t  temp_x_issue_i;
    x_issue_resp_t resp_instr_predecoder;
    logic     rs_valid_flag;                  

    // ISSUE FIFO signals (First FIFO INTERA)
    vpu_issue_t   issue_commit_i;         // Input to FIFO commit
    vpu_issue_t   issue_commit_o;         // Output from FIFO_commit - Input to FIFO_instr if POP in FIFO_commit + ~kill + accept
    logic       fifo_commit_full;
    logic       fifo_commit_empty;
    logic [1:0] fifo_commit_usage;
    logic       fifo_commit_push;
    logic       fifo_commit_pop;

    // TASK FIFO signals (Second FIFO INTERA)
    vpu_issue_t   issue_instr_o;          //Output from FIFO_instr - Input to execution block
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
    vpu_decoded_t decoder_req;
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
    assign issue_commit_i.instr_issue.req      = temp_x_issue_i.req;  // Request to COMMIT_FIFO. Possibility to change FIFO input data.
    // assign issue_commit_i.resp     = x_issue_resp_o; // Corresponding Issue resp goes to the fifo as well
    assign issue_commit_i.instr_issue.resp     = x_issue_resp_o;
    assign issue_commit_i.instr_issue.register = x_register_i;
    assign issue_commit_i.vec_instr            = vec_instr;

    // POP when commit_valid + issue transaction in progress or already done, if issue transaction has not happened yet then wait - All the commit transactions are in order matching with issue transactions
    assign fifo_commit_pop = ~fifo_commit_empty & x_commit_valid_i & (x_commit_i.id == issue_commit_o.instr_issue.req.id) & ~(x_commit_i.id == temp_x_issue_i.req.id && x_issue_valid_i && ~x_issue_ready_o);
  
    // INSTR FIFO                                                                         
    assign fifo_instr_push = fifo_commit_pop && !fifo_instr_full && !x_commit_i.commit_kill && issue_commit_o.instr_issue.resp.accept && !fifo_commit_empty; // We input data from FIFO_commit when fifo_commit_pop + no kill (commit) + accept instr.

    // RESULT FIFO
    // assign fifo_res_push = x_fifo_res_i.result_valid_exec_o & ~fifo_res_full;   // Result coming from execution block
    assign fifo_res_push = (issue_instr_op == VSETVLI || issue_instr_op == VSETIVLI || issue_instr_op == VSETVL || issue_instr_op == CSRRS) 
                                ? ((vtype_valid || csr_lecture_valid) & ~fifo_res_full)  // Result from CSRs
                                : (x_fifo_res_i.result_valid_exec_o & ~fifo_res_full);   // Result from execution block TODO:under dev. 
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
        .dtype       (vpu_issue_t)           // We will input req and resp per instr
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
        .dtype       (vpu_issue_t)          // We will input req and resp per instr
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

    // Single Interface mode
    // assign if_wrapper_exe.wrapper_exe_instr_valid = ~fifo_instr_empty;
    // assign if_wrapper_exe.wrapper_exe_instr_issue = issue_instr_o;
    // assign fifo_instr_pop = if_wrapper_exe.exe_wrapper_recv_instr_ready && ~fifo_instr_empty;
    // Interface: Execution block <-> FIFO_result
    // assign if_wrapper_exe.wrapper_exe_recv_result_ready = ~fifo_res_full;       
    // assign x_fifo_res_i = if_wrapper_exe.exe_wrapper_result;  // TODO: not in case of the CSRs

    // Multiple interface mode  //TODO: under dev
    // assign fifo_instr_pop = disp_ready && ~fifo_instr_empty;    // TODO: not in case of the CSRs
    assign fifo_instr_pop = ((issue_instr_op == VSETVLI)  || 
                             (issue_instr_op == VSETIVLI) || 
                             (issue_instr_op == VSETVL)   || 
                             (issue_instr_op == CSRRS)    || 
                              disp_ready)
                            && ~fifo_instr_empty;
    // Interface: Execution block <-> FIFO_result
    // assign if_wrapper_exe_valu.wrapper_exe_recv_result_ready = ~fifo_res_full;
    // assign if_wrapper_exe_vlsu.wrapper_exe_recv_result_ready = ~fifo_res_full;
    // assign if_wrapper_exe_vsld.wrapper_exe_recv_result_ready = ~fifo_res_full;
    assign x_fifo_res_i = ((issue_instr_op == VSETVLI) || 
                          (issue_instr_op == VSETIVLI) || 
                          (issue_instr_op == VSETVL)   ||
                          (issue_instr_op == CSRRS)     ) ? csr_fifo_res : vpu_fifo_res; // TODO: not in case of the CSRs. 

    always_comb begin
        x_result_valid_o  = ~fifo_res_empty;
        x_result_o.hartid = x_fifo_res_o.issue_exec_o.req.hartid; 
        x_result_o.id     = x_fifo_res_o.issue_exec_o.req.id; // Giving back the instr id
        x_result_o.rd     = x_fifo_res_o.issue_exec_o.req.instr[11:7]; // Giving back the dest reg
        x_result_o.we     = x_fifo_res_o.issue_exec_o.resp.writeback;
        x_result_o.data   = x_fifo_res_o.result_data_exec_o;  // Data processed by the custom instr
    end

    assign  issue_instr_op = issue_instr_o.vec_instr;

    ///////////////////
    // CSR Registers //
    ///////////////////
    
    logic [XLEN-1:0] prov_avl, avl;
    logic [XLEN-1:0] vlmax_d, vlmax_q;
    logic [5:0] int_lmul4;

    function automatic logic [MAXVL_W-1:0] compute_vlmax(sew_e       vsew,
                                                         logic [5:0] int_lmul4);
        begin
            case (vsew)
                SEW_8:  compute_vlmax = (VPU_VLEN / 8)  * int_lmul4 / 4;  
                SEW_16: compute_vlmax = (VPU_VLEN / 16) * int_lmul4 / 4; 
                SEW_32: compute_vlmax = (VPU_VLEN / 32) * int_lmul4 / 4; 
                default: compute_vlmax = 0;
            endcase
        end
    endfunction

    function automatic int ceil_div2(input int v);
        begin
            ceil_div2 = (v + 1) >> 1;
        end
    endfunction

    // Compute vl according to the RISC-V rules (AVL, VLMAX)
    function automatic logic [MAXVL_W-1:0] compute_new_vl(input int avl, input int vlmax);
        begin
            if (avl == 0) begin
                compute_new_vl = 0;
            end else if (avl <= vlmax) begin
                compute_new_vl = avl; 
            end else if (avl >= 2 * vlmax) begin
                compute_new_vl = vlmax;
            end else begin
                compute_new_vl = ceil_div2(avl);
            end
        end
    endfunction

    // vlenb CSR
    assign vlenb_d = VLENB;

    // vtype, vl CSRs  
    always_comb begin: csr_assignation
        
        vtype_valid     = 1'b0;
        vtype_supported = 1'b0;
        avl             = '0;
        int_lmul4       = '0;
        vtype_d         = vtype_q;
        vl_d            = vl_q;
        vlmax_d         = vlmax_q;

        if (fifo_instr_pop  && (issue_instr_op == VSETVLI || issue_instr_op == VSETIVLI || issue_instr_op == VSETVL )) begin
            vtype_valid = 1'b1;
            vtype_supported = 1'b1;

            // Check for unsupported configuration (sew, lmul, vta/vma) 
            unique case (decoder_req.vtype.vsew) 
                SEW_8, SEW_16, SEW_32: ; 
                default: begin 
                    vtype_supported = 1'b0;
                end
            endcase

            unique case (decoder_req.vtype.vlmul) 
                LMUL_F4:  int_lmul4 = 1;    
                LMUL_F2:  int_lmul4 = 2;    
                LMUL_1:   int_lmul4 = 4;    
                LMUL_2:   int_lmul4 = 8; 
                LMUL_4:   int_lmul4 = 16; 
                LMUL_8:   int_lmul4 = 32; 
                default: begin 
                    vtype_supported = 1'b0;
                    int_lmul4 = 0;
                end
            endcase

            if (decoder_req.vtype.vta === 1'bx || decoder_req.vtype.vma === 1'bx ) begin
                vtype_supported = 1'b0;
            end

            // AVL assignation.
            if (!vtype_supported) begin
                vtype_d.vill = 1'b1;
            end else begin

                vtype_d = decoder_req.vtype;
                vlmax_d = compute_vlmax(decoder_req.vtype.vsew, int_lmul4);

                if (issue_instr_op == VSETIVLI) begin
                    avl = prov_avl;
                end else begin 
                    if (decoder_req.vs1 == '0) begin
                        if (decoder_req.vd == '0) begin
                            avl = vl_q;
                            // Reserved if new VLMAX would shrink the current vl.
                            if ((vlmax_d < vl_q) || vtype_q.vill || (vlmax_d != vlmax_q)) begin
                                vtype_d.vill = 1'b1;
                            end
                        end else begin
                            // rs1 == x0 && rd != x0 -> AVL treated as ~0 to request VLMAX
                            avl = 32'hFFFFFFFF;
                        end
                    end else begin
                        // rs1 != x0: AVL is the unsigned integer in x[rs1]
                        avl = prov_avl;
                    end
                end
            end

            // Normal vl update
            if (!vtype_d.vill) begin
                if (avl == 32'hFFFFFFFF) begin
                    vl_d  = vlmax_d;
                end else begin
                    vl_d = compute_new_vl(avl, vlmax_d);
                end

            end else begin 
                vl_d          = '0;
                vtype_d       = '0; 
                vtype_d.vill  = 1'b1;
            end
        end

    end : csr_assignation

    // vstart
    // TODO: - modify after trap of vector instruction
    //       - trap of invalid vstart
    always_comb begin: vstart_csr

        vstart_d = vstart_q; 

        if (fifo_instr_pop  && (issue_instr_op == VSETVLI || issue_instr_op == VSETIVLI || issue_instr_op == VSETVL )) begin
            vstart_d = '0;
        end else if (fifo_res_push) begin  // Reset after instr execution
            vstart_d = '0;
        end
    end

    // System CSR lecture
    always_comb begin : read_csrs

        csr_lecture = '0;
        csr_lecture_valid ='0;
        
        if (fifo_instr_pop  && (issue_instr_op == CSRRS)) begin
            csr_lecture_valid = 1'b1;
            // write data of csrs in result interface
            unique case (csr_addr_e'(decoder_req.rs1_data[11:0]))
                CSR_VSTART: csr_lecture = X_RFW_WIDTH'(vstart_q);
                CSR_VL:     csr_lecture = X_RFW_WIDTH'(vl_q);
                CSR_VTYPE:  csr_lecture = X_RFW_WIDTH'(vtype_q);
                CSR_VLENB:  csr_lecture = X_RFW_WIDTH'(vlenb_q);
                default:;
            endcase
        end
    end 

    // Check the computed next state after combinational FIFO/decoder signals settle.
    always_ff @(posedge clk_i) begin
        if (rst_ni && fifo_instr_pop &&
            (issue_instr_op == VSETVLI || issue_instr_op == VSETIVLI || issue_instr_op == VSETVL) &&
            !vtype_d.vill) begin
            if (avl == 0)
                assert (vl_d == 0)
                    else $fatal(1, "vpu_csr assertion (a) failed: AVL==0 but VL=%0d", vl_d);
            if (avl > 0)
                assert (vl_d > 0)
                    else $fatal(1, "vpu_csr assertion (b) failed: AVL=%0d but VL=%0d", avl, vl_d);
            assert (vl_d <= vlmax_d)
                else $fatal(1, "vpu_csr assertion (c) failed: VL=%0d > VLMAX=%0d (AVL=%0d)", vl_d, vlmax_d, avl);
            assert (vl_d <= avl)
                else $fatal(1, "vpu_csr assertion (d) failed: VL=%0d > AVL=%0d (VLMAX=%0d)", vl_d, avl, vlmax_d);
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin 
        if (!rst_ni) begin
            vlmax_q <= '0;
            vtype_q <= '0;
            vl_q <= '0;
            vstart_q <= '0;
            vlenb_q <= '0;
        end  else begin
            vlmax_q <= vlmax_d;
            vtype_q <= vtype_d;
            vl_q <= vl_d;
            vstart_q <= vstart_d;
            vlenb_q <= vlenb_d;  
        end
    end


    always_comb begin
        if (issue_instr_op == CSRRS) begin
            csr_fifo_res.result_data_exec_o = csr_lecture;
        end else if (!((issue_instr_op != VSETIVLI) &&
                       (decoder_req.vs1 == '0)      &&
                       (decoder_req.vd == '0))) begin
            csr_fifo_res.result_data_exec_o = X_RFW_WIDTH'(vl_d);
        end else begin
            csr_fifo_res.result_data_exec_o = '0;
        end
        csr_fifo_res.result_valid_exec_o = (vtype_valid || csr_lecture_valid);
        csr_fifo_res.issue_exec_o.req = issue_instr_o.instr_issue.req;  
        csr_fifo_res.issue_exec_o.resp = issue_instr_o.instr_issue.resp; 
        csr_fifo_res.issue_exec_o.register = issue_instr_o.instr_issue.register;    
    end

    //////////////////////
    // Extended decoder //
    //////////////////////

    vpu_decoder #(
        .NrRgprPorts (NrRgprPorts),
        .id_t        (id_t),
        .hartid_t    (hartid_t),
        // .registers_t (registers_t),
        .vpu_issue_t (vpu_issue_t)
        // .vec_instr_e (vec_instr_e)
    ) vpu_decoder_i (
        .clk_i             (clk_i),
        .req_valid_i       (fifo_instr_pop),
        .instr_req_i       (issue_instr_o),
        // .vec_instr_i       (vec_instr),
        .vtype_i           (vtype_q),
        .vl_i              (vl_q),
        .dec_resp_valid_o  (decoder_valid), // To data hazard detection 
        .decoded_req_o     (decoder_req),
        .avl_o             (prov_avl)
    );

    ////////////////////////////
    // Instruction dispatcher //
    ////////////////////////////
    
    vpu_dispatch
    #(
        .NUM_BANKS (),
        .MAX_INFLIGHT ()
    ) vpu_dispatch_i (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .disp_valid_i     (~fifo_instr_empty),
        .disp_decoded_i   (decoder_req),
        .disp_issue_i     (issue_instr_o),  
        .disp_ready_o     (disp_ready),
        .kill_valid_i     ('0),
        .kill_hartid_i    ('0),
        .kill_id_i        ('0),
        .x_fifo_res_full_i(fifo_res_full),
        .x_fifo_res_o     (vpu_fifo_res),
        .fu_valu          (if_wrapper_exe_valu),
        .fu_vlsu          (if_wrapper_exe_vlsu),
        .fu_vsld          (if_wrapper_exe_vsld)
    );


endmodule: vpu_control_unit