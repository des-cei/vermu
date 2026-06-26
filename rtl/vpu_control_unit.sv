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
#(
    parameter  int unsigned NrRgprPorts         = 2,
    parameter  int unsigned XLEN                = 32,
    //X_ID_WIDTH?
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
    // CVXIF Interface  //TODO: Not sure all this XIF assigned here
    input  logic              issue_valid_i,
		output logic              issue_ready_o,
		input  x_issue_req_t      issue_req_i,
		output x_issue_resp_t     issue_resp_o,
    input  logic              register_valid_i,
		input  x_register_t       register_i,
		input  logic              commit_valid_i,
		input  x_commit_t         commit_i,
		output logic              result_valid_o,
		input  logic              result_ready_i,
		output x_result_t         result_o,
);


  buff_dec_t buff_dec;
  logic writeback, accept;
  readregflags_t register_read;

  vpu_xif_decoder #(
    .readregflags_t (readregflags_t),
    .vec_instr_e    (vec_instr_e)
  ) i_vpu_xif_decoder (
    .instr_i          (x_issue_req_i.instr),
    .accept_o         (accept),     
    .writeback_o      (writeback),
    .register_read_o  (register_read),
    .vec_instr_o      (buff_dec.instr_enum) 
  );

  // CV-X-IF response
  assign x_issue_resp_o.writeback     = writeback;
  assign x_issue_resp_o.accept        = accept;       // TODO: should check illegality before accept (CSRs)
  assign x_issue_resp_o.register_read = register_read

  // Decoded context to buffer
  assign buff_dec.writeback       = writeback;  //?

  always_comb begin: extract_rs_data
    if (register_read  = 2'b1) buff_dec.rs[0] = register_i[0];
    else if (register_read  = 2'b3) buff_dec.rs = register_i;
    else buff_dec = '0;
  end

  // Instruction queue
  //    buff_dec_i
  //    hartid_i
  //    id_i 
  //    buff_dec_o
  //    hartid_o
  //    id_o 

  // vpu_decoder #(

  // )i_vpu_decoder (

  // );



endmodule: vpu_control_unit


//   /////////
//   // CSR //
//   /////////
// // TODO: activar writeback para CFG
//   always_comb begin
//     vtype_supported = 1'b1;
//     csr_we_d        = 1'b0;
//     csr_valid_d     = 1'b0;
//     vlmax_d         = vlmax_q;
//     vtype_d         = vtype_q; 
//     vl_d            = vl_q;
//     vstart_d        = vstart_q;
//     issue_rs1       = '0;
//     issue_rd        = '0; 
//     result_d        = '0;

//     if (state_o == S_BUSY) begin
//         unique case (vpu_req_o.opcode)
//           VSETVLI,
//           VSETIVLI, 
//           VSETVL: begin
//             csr_valid_d = ~csr_valid_q;           
//             issue_rs1 = vpu_req_o.rs1;
//             issue_rd  = vpu_req_o.rd;
//             vstart_d  = '0;
//           end
//           default: ; 
//         endcase
//     end else begin
//         csr_valid_d = 1'b0; 
//     end

//     // Check for unsupported configuration    
//     unique case (vpu_req_o.csr_vtype.vsew) 
//       SEW_8, SEW_16, SEW_32: ; 
//       default: begin 
//         vtype_supported = 1'b0;
//       end
//     endcase

//     unique case (vpu_req_o.csr_vtype.vlmul) 
//       LMUL_F4: int_lmul4 = 1;   // 1/4 LMUL
//       LMUL_F2: int_lmul4 = 2;   // 1/2 LMUL
//       LMUL_1:  int_lmul4 = 4;   // 1 LMUL
//       default: begin 
//         vtype_supported = 1'b0;
//         int_lmul4 = 0;
//       end
//     endcase

//     if (vpu_req_o.csr_vtype.vta === 1'bx || vpu_req_o.csr_vtype.vma === 1'bx ) begin
//       vtype_supported = 1'b0;
//     end
 
//     // begin: AVL assignation 
//     if (csr_valid_d && !vtype_supported) begin  
//       vtype_d      = '0;
//       vl_d         = '0;
//       vlmax_d      = 32'd0;
//       vtype_d.vill = 1'b1;
//       csr_we_d     = 1'b1;    
//       result_d     = '0;
//     end else if (csr_valid_d) begin
      
//       vtype_d = vpu_req_o.csr_vtype;
//       vlmax_d = compute_vlmax(vtype_d.vsew);  

//       // Decode AVL
//       if (vpu_req_o.opcode == VSETIVLI) begin 
//         avl_int = issue_rs1;
//       end else begin           // vsetvli / vsetvl
//         if ( rs1_addr_q == 5'd0) begin 
//           if (issue_rd == 5'd0) begin
//             avl_int = vl_q;
//             // Reserved if new VLMAX would shrink the current vl.
//             if ((vlmax_d < vl_q) || vtype_q.vill || vlmax_d != vlmax_q) begin
//               vtype_d.vill = 1'b1;
//             end 
//           end else begin
//             // rs1 == x0 && rd != x0 -> AVL treated as ~0 to request VLMAX
//             avl_int = 32'hFFFFFFFF;
//           end
//         end else begin
//           // rs1 != x0: AVL is the unsigned integer in x[rs1]
//           avl_int = issue_rs1;
//         end
//       end

//       // rs1==x0 && rd==x0 case, skip normal update
//       if (!vtype_d.vill) begin
//         if (avl_int == 32'hFFFFFFFF) begin
//           new_vl_int = vlmax_d;
//         end else begin
//           new_vl_int = compute_new_vl(avl_int, vlmax_d);
//         end
//         vl_d        = new_vl_int;
//         csr_we_d    = 1'b1;
//         if ((issue_rd == 5'h0) && (issue_rs1 == 5'h0)) begin 
//           csr_we_d    = 1'b0;
//         end

//         // normal success clears vill bit
//         vtype_d.vill = 1'b0;

//         // Assertions to validate VL rules:
//         // a) VL = 0 if AVL = 0
//         if (avl_int == 0) begin
//             assert (new_vl_int == 0) else $fatal("vpu_csr assertion (a) failed: AVL==0 but VL=%0d", new_vl_int);
//         end
//         // b) VL > 0 if AVL > 0
//         if (avl_int > 0) begin
//             assert (new_vl_int > 0) else $fatal("vpu_csr assertion (b) failed: AVL=%0d but VL=%0d", avl_int, new_vl_int);
//         end
//         // c) VL ≤ VLMAX
//         assert (new_vl_int <= vlmax_d) else $fatal("vpu_csr assertion (c) failed: VL=%0d > VLMAX=%0d (AVL=%0d)", new_vl_int, vlmax_d, avl_int);
//         // d) VL ≤ AVL
//         if (avl_int != -1) begin
//             assert (new_vl_int <= avl_int) else $fatal("vpu_csr assertion (d) failed: VL=%0d > AVL=%0d (VLMAX=%0d)", new_vl_int, avl_int, vlmax_d);
//         end

//       end else begin
//         vl_d          = '0;
//         vtype_d       = '0; 
//         vtype_d.vill  = 1'b1;
//       end

//       if (vpu_req_d.opcode == VMV_XS) begin
//         csr_we_d = 1'b1; 
//       end

//       result_d = vl_d; 
//     //end  : AVL assignation
//     end else if (vpu_req_d.mopcode == system) begin  

//       // CSRR 
//       unique case (csr_target) 
//         CSR_VLENB: begin                        //TODO: other CSRs  
//           if (csr_handle.read_CSR && ! csr_handle.write_CSR) begin
//             result_d = VLENB;
//             csr_we_d = 1'b1; 
//           end else begin
//             result_d = 1'b0;
//           end
//         end
//         default:;
//       endcase
//     end   
//   end


//   always_ff  @(posedge clk_i or negedge rst_ni) begin 
//     if(!rst_ni) begin
//       vtype_q    <= '0;
//       vl_q       <= '0;
//       vstart_q   <= '0;
//       rs1_addr_q <= '0;
//       result_q   <= '0;
//       vlmax_q    <= '0;
//       csr_we_q   <= '0;
//       csr_valid_q <= '0;
//       illegal_req_q <= '0;
//     end else begin
//       vtype_q     <= vtype_d;
//       vl_q        <= vl_d;
//       vstart_q    <= vstart_d;
//       rs1_addr_q  <= rs1_addr_d;
//       result_q    <= result_d;
//       vlmax_q     <= vlmax_d;
//       csr_we_q    <= csr_we_d;
//       csr_valid_q <= csr_valid_d;
//       illegal_req_q <= illegal_req_d;
//     end
//   end

  

