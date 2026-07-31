// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_top
import rvv_instr_pkg::*;
import vpu_pkg::*;
#(
    // CVXIF Types
    parameter  int unsigned NrRgprPorts         = 2,
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
    parameter  int unsigned EXT_XBAR_NMASTER    = 1
    
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
    if_xif_exe xif_exe_i ();
    if_xif_exe xif_exe_valu_i ();
    // if_xif_exe xif_exe_vlsu_i ();
    // if_xif_exe xif_exe_vsld_i ();

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
        .if_wrapper_exe (xif_exe_i.xif_wrapper), 
        .if_wrapper_exe_valu (xif_exe_valu_i.xif_wrapper)
        // .if_wrapper_exe_vlsu (xif_exe_vlsu_i.xif_wrapper),
        // .if_wrapper_exe_vsld (xif_exe_vsld_i.xif_wrapper)
    );

    // execution_units execution_units_i 
    // (
    //     .clk_i,
    //     .rst_ni,
    //     .if_exe_wrapper (xif_exe_i.exe_unit)
    //     // .instr_accept_o (instr_accept),  // TODO: assign
    //     // .result_valid_i (result_valid)
    // );

    execution_units valu_i 
    (
        .clk_i,
        .rst_ni,
        .if_exe_wrapper (xif_exe_valu_i.exe_unit)
        // .instr_accept_o (instr_accept),  // TODO: assign
        // .result_valid_i (result_valid)
    );

    // execution_units vlsu_i 
    // (
    //     .clk_i,
    //     .rst_ni,
    //     .if_exe_wrapper (xif_exe_vlsu_i.exe_unit)
    //     // .instr_accept_o (instr_accept),  // TODO: assign
    //     // .result_valid_i (result_valid)
    // );

    // execution_units vsld_i 
    // (
    //     .clk_i,
    //     .rst_ni,
    //     .if_exe_wrapper (xif_exe_vsld_i.exe_unit)
    //     // .instr_accept_o (instr_accept),  // TODO: assign
    //     // .result_valid_i (result_valid)
    // );

/////// User ////////////
/*
  logic  instr_vrf_we, op_valid_ls, op_valid_simd, done_w, done_r2,
            simd_result_valid, ls_valid, csr_valid, result_valid;
  logic  vrf_we, lsu_vrf_we;
  logic  illegal_req;
  addr_t raddr1, raddr2, waddr; 
  vlen_t vrf_wdata, rdata1, vrf_rdata1, vrf_rdata2, vrf_vd_data, wdata, simd_result, mask;
  op_e   operation;
  vpu_req_t vpu_req;
  logic [XLEN-1:0] gpr_result;

  // load-store
  logic lsu_result_valid;
  logic state_was_busy;

  // CSRs
  vtype_t csr_vtype;
  vl_t    csr_vl, csr_vstart;
  xlen_t  vlmax;

  // FSM 
  xif_fsm_e state;

  // Move
  addr_t nreg;
  logic  vmv_done;
  addr_t vmv_offset;
  logic vrf_op_valid;
  logic vmv_active;
  logic waiting_for_done;
  logic vrf_we_d;

  interface vpu_debug_if;
      op_e          operation;
      logic [VLEN-1:0] rdata1;
      logic [VLEN-1:0] vrf_rdata2;
      logic [VLEN-1:0] vrf_vd_data;
      logic [VLEN-1:0] result; 
      logic simd_result_valid;
  endinterface

///////// Modules ///////////////

  vpu_decoder #(
      .copro_issue_resp_t(rvv_instr_pkg::copro_issue_resp_t),
      .opcode_t          (rvv_instr_pkg::opcode_t),
      .NbInstr           (rvv_instr_pkg::NbInstr),
      .CoproInstr        (rvv_instr_pkg::CoproInstr),
      .NrRgprPorts       (NrRgprPorts),
      .hartid_t          (hartid_t),
      .id_t              (id_t),
      .x_issue_req_t     (x_issue_req_t),
      .x_issue_resp_t    (x_issue_resp_t),
      .x_register_t      (x_register_t),
      .registers_t       (registers_t)
  ) vpu_decoder_i (
      .clk_i               (clk_i),
      .rst_ni              (rst_ni),
      .issue_valid_i       (issue_valid),
      .issue_req_i         (issue_req),
      .issue_ready_o       (issue_ready),
      .issue_result_valid_i(result_valid),
      .issue_resp_o        (issue_resp),
      .register_valid_i    (register_valid),
      .register_i          (register),
      .registers_o         (registers),    
      .op_valid_ls_i       (op_valid_ls),
      .done_wi             (done_w),
      .vmv_active_i        (vmv_active),
      .vmv_offset_i        (vmv_offset),
      .nreg_i              (nreg),
      .waiting_for_done_i  (waiting_for_done),
      .vrf_op_valid_o      (vrf_op_valid),
      .vrf_we_d            (vrf_we_d),
      .hartid_o            (issue_hartid),
      .id_o                (issue_id),
      .vpu_req_o           (vpu_req),      
      .operation_o         (operation),
      .state_o             (state),        
      .vrf_we_o            (instr_vrf_we),
      .op_valid_simd_o     (op_valid_simd),
      .illegal_req_o       (illegal_req),
      //CSRs
      .vl_o                (csr_vl),
      .vlmax_o             (vlmax),
      .vtype_o             (csr_vtype),
      .vstart_o            (csr_vstart),
      .csr_we_o            (we),
      .csr_result_valid_o  (csr_valid),
      .result_o            (csr_result),
      .state_was_busy_o    (state_was_busy)
  );

    obi_lsu_top #(
      .opcode_t   (rvv_instr_pkg::opcode_t),
      .obi_req_t  (obi_req_t),
      .obi_resp_t (obi_resp_t)
    ) obi_lsu_top_i (
      .clk_i             (clk_i),   
      .rst_ni            (rst_ni),
      .vpu_req_i         (vpu_req),
      .vl_i              (csr_vl),
      .vlmax_i           (vlmax),
      .state_was_busy_i  (state_was_busy),
      .vrf_rdata_i       (vrf_rdata2),
      .vrf_rdata_done_i  (done_r2),
      .vrf_wdata_o       (vrf_wdata),
      .lsu_vrf_we_o      (lsu_vrf_we),
      .lsu_rdata_valid_o (),
      .lsu_result_valid_o(lsu_result_valid),
      .masters_resp_i    (masters_resp_i[0]),
      .masters_req_o     (masters_req_o[0])
    );

    vregfile vregfile_i(
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .vpu_req_i   (vpu_req),
        .csr_vtype_i (csr_vtype),  
        .csr_vl_i    (csr_vl),    
        .vstart_i    (csr_vstart),
        .op_valid_i  (vrf_op_valid), 
        .funct3_i    (vpu_req.funct3),
        .waddr_i     (waddr),    
        .we_i        (vrf_we),      
        .wdata_i     (wdata),
        .done_w_o    (done_w),
        .raddr1_i    (raddr1),  
        .raddr2_i    (raddr2),
        .raddr3_i    (vpu_req.vd),  
        .rdata1_o    (vrf_rdata1),  
        .rdata2_o    (vrf_rdata2),
        .rdata3_o    (vrf_vd_data),
        .done_r2_o   (done_r2),
        .mask_o      (mask)  
    );

    simd_controller simd_controller_i (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .operation_i      (operation),
        .operation_valid_i(op_valid_simd), 
        .op_s1_i          (rdata1),
        .op_s2_i          (vrf_rdata2),
        .op_d_i           (vrf_vd_data),
        .is_signed_i      (vpu_req.is_signed), 
        .carry_i          (1'b0), 
        .sew_i            (csr_vtype.vsew),   
        .vl_i             (csr_vl),     
        .result_o         (simd_result),
        .result_valid_o   (simd_result_valid)
    );

////////////////////
// CVXIF RESPONSE //
////////////////////

  always_comb begin
    x_result_valid_o  = result_valid; 
    x_result_o.hartid = issue_hartid;
    x_result_o.id     = issue_id;
    x_result_o.we     = '0;

    if (vpu_req.mopcode == op_v) begin
      x_result_o.data = (vpu_req.funct3 == OPCFG_CSRRCI) ? csr_result : gpr_result; 
    end else if (vpu_req.mopcode == system) begin
      x_result_o.data = csr_result;      
    end else begin
      x_result_o.data = '0; 
    end 

    x_result_o.rd      = (we && vpu_req.mopcode == op_v) ? vpu_req.rd : '0;

    if (vpu_req.is_writeback) begin
      if(vpu_req.mopcode == op_v) begin
        if (vpu_req.funct3 == OPCFG_CSRRCI) begin
          x_result_o.we     = we;
        end else begin
          x_result_o.we     = done_w;
        end 
      end else if ( vpu_req.mopcode == system) begin  
        x_result_o.we     = we;
      end 
    end else begin
      x_result_o.we     = 1'b0; 
    end
    
  end

///////// User  /////////////

  assign raddr1 = (vpu_req.mopcode == op_v) ? 
                  ((vpu_req.funct3 == OPIVV || vpu_req.funct3 == OPMVV_CSRRS) ? vpu_req.vs1 : vpu_req.rs1) : '0;                                                         
  assign vrf_we = (vpu_req.mopcode == load_fp) ? lsu_vrf_we : ((vpu_req.mopcode == op_v) ? ((op_valid_simd && simd_result_valid) || instr_vrf_we): 1'b0); 

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        vmv_active <= 1'b0;
        vmv_offset <= '0;
        vmv_done   <= '0;
        waiting_for_done <= 1'b0;
    end else begin
        vmv_done <= 1'b0;
        if (issue_ready) begin
          vmv_active    <= vpu_req.is_vmv_nr; 
          vmv_offset    <= '0;
          vmv_done      <= 1'b0;
        end else begin
          if (vmv_active && done_w) begin
            if (vmv_offset == (nreg - 1)) begin
                vmv_active <= 1'b0;      
            end else begin
                vmv_offset <= vmv_offset + 1'b1;
            end
          end
          if (vrf_we_d) begin        
              waiting_for_done <= 1'b1;
              vmv_done <= 1'b0;
          end else if (done_w && (vmv_offset == (nreg - 1))) begin     
              waiting_for_done <= 1'b0;  
              vmv_done <= 1'b1; 
          end      
        end
    end
  end

  always_comb begin : addr2_assignation
    nreg = '0;
    if (vpu_req.mopcode == op_v) begin
      if (vpu_req.is_vmv_nr) begin
          nreg = get_nreg(vpu_req.opcode); 
          raddr2 = vpu_req.vs2 + vmv_offset;  
      end else begin
          raddr2 = vpu_req.vs2;      
      end             
    end else if (vpu_req.mopcode == store_fp) begin
        raddr2 = vpu_req.vd;
    end else begin
        raddr2 = '0;
    end
  end

  always_comb begin: waddr_assignation
    if ((vpu_req.mopcode == op_v) || (vpu_req.mopcode == load_fp)) begin
      if (vpu_req.is_vmv_nr) begin
        waddr = vpu_req.vd + vmv_offset;
      end else begin
        waddr = vpu_req.vd;
      end
    end else begin
      waddr = '0;
    end
  end 

  always_comb begin
    if (vpu_req.mopcode == op_v) begin
      unique case (operation)
        VMV: begin
          unique case (vpu_req.opcode)
            VMV1R_V, 
            VMV2R_V,
            VMV4R_V,
            VMV8R_V: begin
              wdata = vrf_rdata2;                      
            end
            VMV_SX: wdata = {96'h0, vpu_req.rs1};
            default: begin
              if(!vpu_req.is_vmv_nr) begin
                  if (vpu_req.vm) begin
                    wdata = rdata1;                       
                  end else begin
                    for (int i = 0; i < VLEN; i++) begin  
                      wdata[i] = mask[i] ? rdata1[i] : vrf_rdata2[i];
                    end
                  end
              end else begin
                wdata = '0;
              end
            end
          endcase
        end
        default: begin
          wdata = simd_result;
        end
      endcase
    end else if (vpu_req.mopcode == load_fp) begin
      wdata = vrf_wdata;
    end else begin
      wdata = '0;
    end
  end

 always_comb begin
    unique case (vpu_req.funct3)
      OPIVV,
      OPMVV_CSRRS: begin
        rdata1 = vrf_rdata1;
      end
      OPIVI_CSRRC,
      OPIVX,
      OPMVX_CSRRSI: begin
        rdata1 = vpu_req.rs_rdata1;
      end
      default: rdata1 = '0; 
    endcase
    
    unique case(vpu_req.mopcode) 
      op_v: begin
          if (vpu_req.funct3 == OPCFG_CSRRCI) begin 
            result_valid = csr_valid;
          end else begin
            if (vpu_req.is_vmv_nr) begin
              result_valid = vmv_done;
            end else begin
              result_valid = done_w; 
            end
          end
      end
      load_fp:  result_valid = ( done_w );
      store_fp: begin
            result_valid = lsu_result_valid; 
      end
      system: begin
        result_valid = we;
      end
      default:  result_valid = 1'b0; 
    endcase
  end
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpr_result <= '0;
    end else begin
      unique case (vpu_req.opcode)
        VMV_XS:begin
          unique case (csr_vtype.vsew)
            SEW_8:   gpr_result <= xlen_t'(signed'(vrf_rdata2[7:0]));
            SEW_16:  gpr_result <= xlen_t'(signed'(vrf_rdata2[15:0]));
            default: gpr_result <= xlen_t'(signed'(vrf_rdata2[31:0]));
          endcase
        end 
        default: ; 
      endcase
    end
  end

  //Verification tb_vpu_top.sv
  vpu_debug_if debug_if();

  assign debug_if.operation         = operation;
  assign debug_if.rdata1            = rdata1;
  assign debug_if.vrf_rdata2        = vrf_rdata2;
  assign debug_if.result            = wdata;
  assign debug_if.vrf_vd_data       = vrf_vd_data;
  assign debug_if.simd_result_valid = simd_result_valid;
  */
endmodule