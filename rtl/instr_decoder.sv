// Copyright 2024 Thales DIS France SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Guillaume Chauvon

`include "utils_macros.svh"

module instr_decoder 
  import vpu_pkg::*;
  import rvv_instr_pkg::*;
  import vector_ops_pkg::*;
#(
    parameter type               copro_issue_resp_t          = logic,
    parameter type               opcode_t                    = logic, 
    parameter int                NbInstr                     = 1,
    parameter copro_issue_resp_t CoproInstr        [NbInstr] = {0},
    parameter int unsigned       NrRgprPorts                 = 2,
    parameter type               hartid_t                    = logic,
    parameter type               id_t                        = logic,
    parameter type               x_issue_req_t               = logic,
    parameter type               x_issue_resp_t              = logic,
    parameter type               x_register_t                = logic,
    parameter type               registers_t                 = logic
)(
    input  logic                clk_i,
    input  logic                rst_ni,
    // XIF
    input  logic                issue_valid_i,
    input  x_issue_req_t        issue_req_i,
    output logic                issue_ready_o,
    input  logic                issue_result_valid_i,
    output x_issue_resp_t       issue_resp_o,
    input  logic                register_valid_i, 
    input  x_register_t         register_i,
    output registers_t          registers_o,
    //VPU
    input  logic                op_valid_ls_i,  
    input  logic                done_wi,
    input  logic                vmv_active_i,
    input addr_t                vmv_offset_i,
    input addr_t                nreg_i,
    input logic                 waiting_for_done_i,
    output logic                vrf_op_valid_o,
    output logic                vrf_we_d,
    output hartid_t             hartid_o,
    output id_t                 id_o,
    output vpu_req_t            vpu_req_o,
    output op_e                 operation_o,
    output xif_fsm_e            state_o,
    output logic                vrf_we_o,
    output logic                op_valid_simd_o, 
    output logic                illegal_req_o,
    output vl_t                 vl_o,
    output xlen_t               vlmax_o,
    output vtype_t              vtype_o,
    output vl_t                 vstart_o,
    output logic                csr_we_o,
    output logic                csr_result_valid_o,
    output xlen_t               result_o,
    output logic                state_was_busy_o
);

  logic [NbInstr-1:0] sel;
  hartid_t            hartid_d, hartid_q;
  id_t                id_d, id_q;
  vpu_req_t           vpu_req_d, vpu_req_q;
  elen_t              vsetvl_rs2;
  xlen_t              scalar_val;

  // CSR 
  addr_t          rs1_addr_d, rs1_addr_q;
  logic           vtype_supported;
  logic           csr_we_d, csr_we_q, csr_valid_d, csr_valid_q; 
  vtype_t         vtype_d, vtype_q;
  vl_t            vl_d, vl_q;
  vl_t            vstart_d, vstart_q;
  elen_t          issue_rs1, issue_rd;
  xlen_t          result_d, result_q;
  xlen_t          vlmax_d, vlmax_q;
  int             avl_int, new_vl_int;
  csr_handle_t    csr_handle;
  csr_addr_e      csr_target;
  logic [5:0]     int_lmul4;  

  //VRF request
  logic op_valid_simd_d, op_valid_simd_q, vrf_op_valid_d, vrf_op_valid_q, vrf_we_q; 
  logic illegal_req_d, illegal_req_q;

  // FSM
  xif_fsm_e state_d, state_q;

  assign vtype_o               = vtype_q;
  assign vl_o                  = vl_q;
  assign vstart_o              = vstart_q;
  assign result_o              = result_q; 
  assign vlmax_o               = vlmax_q;
  assign csr_we_o              = csr_we_q;
  assign csr_result_valid_o    = csr_valid_q;

  assign op_valid_simd_o       = op_valid_simd_q; 
  assign vrf_op_valid_o        = vrf_op_valid_q; 
  assign vrf_we_o              = vrf_we_q; 

  assign illegal_req_o         = illegal_req_q;

  // CSR Functions
  function automatic int compute_vlmax(input logic [2:0] vsew);
    begin
      case (vsew)
        3'b00: compute_vlmax = VLEN / 8  * int_lmul4 / 4;  
        3'b01: compute_vlmax = VLEN / 16 * int_lmul4 / 4; 
        3'b10: compute_vlmax = VLEN / 32 * int_lmul4 / 4; 
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
  function automatic int compute_new_vl(input int avl, input int vlmax);
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

  assign hartid_o  = hartid_q;
  assign id_o      = id_q;
  assign vpu_req_o = vpu_req_q;
  assign state_o   = state_q;

  /////////////
  // Decoder //
  /////////////

  for (genvar i = 0; i < NbInstr; i++) begin : gen_predecoder_selector
    assign sel[i] = ((CoproInstr[i].mask & issue_req_i.instr) == CoproInstr[i].instr);
  end

  always_comb begin :decoding
    issue_resp_o.accept        = '0;      
    issue_resp_o.writeback     = '0;    
    issue_resp_o.register_read = '0;    
    registers_o                = '0;
    hartid_d                   = hartid_q;
    id_d                       = id_q;
    vpu_req_d                  = '0; 
    rs1_addr_d                 = '0;
    vsetvl_rs2                 = '0;
    illegal_req_d              = '0;
    csr_handle                 = '0;

    for (int unsigned i = 0; i < NbInstr; i++) begin
      if (sel[i] && issue_valid_i && issue_ready_o) begin       
        issue_resp_o.accept = CoproInstr[i].resp.accept;
        issue_resp_o.writeback = CoproInstr[i].resp.writeback;
        issue_resp_o.register_read = CoproInstr[i].resp.register_read; // Warning :  potential 3 bits vector into 2 bits one
        vpu_req_d.is_writeback = CoproInstr[i].resp.writeback;
        if (issue_resp_o.accept) begin        
          vpu_req_d.mopcode = major_opcode_e'(issue_req_i.instr[6:0]);
          //Arithmetic Opcode
          if (vpu_req_d.mopcode == op_v) begin
            vpu_req_d.funct3  = encode_funct3_e'(issue_req_i.instr[14:12]); 
            //CSRs configuration
            if(vpu_req_d.funct3 == OPCFG_CSRRCI) begin
              // Extract vtype
              vpu_req_d.rd  = issue_req_i.instr[11:7];
              //vsetvli
              if (issue_req_i.instr[31] == 1'b0) begin 
                vpu_req_d.csr_vtype = {1'b0, issue_req_i.instr[27:20]};
                vpu_req_d.rs1 = register_i.rs[0];                          
                rs1_addr_d = issue_req_i.instr[19:15];
              //vsetivli  
              end else if (issue_req_i.instr[31:30] == 2'b11) begin 
                vpu_req_d.csr_vtype = {1'b0, issue_req_i.instr[27:20]};
                vpu_req_d.rs1 = elen_t'(issue_req_i.instr[19:15]);
              //vsetvl
              end else if (issue_req_i.instr[31:25] == 7'b1000000) begin  
                vsetvl_rs2 = register_i.rs[1];
                vpu_req_d.rs2 = register_i.rs[1];
                vpu_req_d.csr_vtype = {1'b0, register_i.rs[1][7:0]};    
                vpu_req_d.rs1 = register_i.rs[0];               
              end 

              // Suppress writeback for vsetvli/vsetvl when rd==0 and rs1_addr==0 (no-op)
              if ((issue_req_i.instr[31] == 1'b0 || issue_req_i.instr[31:25] == 7'b1000000) &&
                vpu_req_d.rd == '0 &&
                rs1_addr_d == '0) begin
                issue_resp_o.writeback = 1'b0;
              end
            end else begin
              
              //Arithmetic             
              vpu_req_d.vs2 = issue_req_i.instr[24:20]; 
              vpu_req_d.vm  = issue_req_i.instr[25];
              unique case (vpu_req_d.funct3)
                OPIVV,
                OPMVV_CSRRS: begin
                  vpu_req_d.vd  = issue_req_i.instr[11:7];  
                  vpu_req_d.vs1 = issue_req_i.instr[19:15]; 
                end
                OPIVI_CSRRC: begin
                  vpu_req_d.vd  = issue_req_i.instr[11:7];
                  vpu_req_d.rs1 = elen_t'(signed'(issue_req_i.instr[19:15]));
                end
                OPIVX,
                OPMVX_CSRRSI: begin
                  vpu_req_d.vd  = issue_req_i.instr[11:7]; 
                  unique case (vtype_o.vsew)
                    SEW_8:  vpu_req_d.rs1 = {27'b0,register_i.rs[0][7:0]};
                    SEW_16: vpu_req_d.rs1 = {16'b0,register_i.rs[0][15:0]};
                    default: vpu_req_d.rs1 = register_i.rs[0];
                  endcase
                end
                default: ;
              endcase
            end            
          end else if (vpu_req_d.mopcode == load_fp || vpu_req_d.mopcode == store_fp) begin      

            vpu_req_d.funct3  = NOP_FUNCT3; 
            // Load-store
            vpu_req_d.vd    = issue_req_i.instr[11:7];         
            vpu_req_d.rs1   = register_i.rs[0];                 
            rs1_addr_d      =  issue_req_i.instr[19:15];
            vpu_req_d.width = width_e'(issue_req_i.instr[14:12]); 
            vpu_req_d.lumop = issue_req_i.instr[24:20]; 
            vpu_req_d.vm    = issue_req_i.instr[25];
            vpu_req_d.mop   = issue_req_i.instr[27:26];
            vpu_req_d.mew   = issue_req_i.instr[28];
            vpu_req_d.nf    = issue_req_i.instr[31:29];
            //Unit-stride
            if (vpu_req_d.mop == 2'b00) begin   
              vpu_req_d.rs2 = 32'h4; 
            //Stride
            end else if (vpu_req_d.mop == 2'b10) begin   
              vpu_req_d.rs2 = register_i.rs[1]; 
            // TODO: Indexed
            end else begin                      
              vpu_req_d.rs2 = 32'h0;        
            end

          end else if (vpu_req_d.mopcode == system) begin
            //CSRR access
            vpu_req_d.rd      = issue_req_i.instr[11:7];
            vpu_req_d.funct3  = encode_funct3_e'(issue_req_i.instr[14:12]);
            csr_target        = csr_addr_e'(issue_req_i.instr[31:20]);
            unique case (vpu_req_d.funct3)
              OPFVV_CSRRW,
              OPMVV_CSRRS,
              OPIVI_CSRRC:begin
                vpu_req_d.rs1 = register_i.rs[0];                          
                rs1_addr_d = issue_req_i.instr[19:15];
              end 
              OPFVF_CSRRWI,
              OPMVX_CSRRSI,
              OPCFG_CSRRCI:begin
                  vpu_req_d.rs1 = elen_t'(unsigned'(issue_req_i.instr[19:15]));
              end
              default: ; 
            endcase

            unique case (vpu_req_d.funct3)
              OPFVV_CSRRW,
              OPFVF_CSRRWI: begin
                  csr_handle.write_CSR =  1'b1;
                  if (vpu_req_d.rd == '0) begin
                    csr_handle.read_CSR = 1'b0;
                  end else begin
                    csr_handle.read_CSR = 1'b1;
                  end
              end
              OPMVV_CSRRS,
              OPIVI_CSRRC: begin 
                  csr_handle.read_CSR = 1'b1;
                  if(rs1_addr_d == '0) begin
                    csr_handle.write_CSR =  1'b0;
                  end else begin
                    csr_handle.write_CSR =  1'b1;
                  end
              end
              OPMVX_CSRRSI,
              OPCFG_CSRRCI: begin 
                  csr_handle.read_CSR = 1'b1;
                  if(vpu_req_d.rs1 == '0) begin
                    csr_handle.write_CSR =  1'b0;
                  end else begin
                    csr_handle.write_CSR =  1'b1;
                  end
              end
              default: csr_handle = '0;
            endcase

          end else begin
            vpu_req_d = '0;
          end
        end
        vpu_req_d.opcode  = CoproInstr[i].opcode; 
        hartid_d          = issue_req_i.hartid;
        id_d              = issue_req_i.id;
        for (int unsigned j = 0; j < NrRgprPorts; j++) begin
          registers_o[j] = issue_resp_o.register_read[j] ? register_i.rs[j] : '0;
        end
      end                                                                                   
    end 
    
    unique case (vpu_req_d.opcode)
      VMIN_VV,
      VMIN_VX,
      VMAX_VV,
      VMAX_VX,
      VMSLT_VV,
      VMSLT_VX,
      VMUL_VV,
      VMUL_VX,
      VMULH_VV,
      VMULH_VX,
      VMULHSU_VV,
      VMULHSU_VX:  vpu_req_d.is_signed = 1'b1;
      VMV1R_V,
      VMV2R_V,
      VMV4R_V,
      VMV8R_V:     vpu_req_d.is_vmv_nr = 1'b1;
      default: begin 
          vpu_req_d.is_signed= 1'b0;
          vpu_req_d.is_vmv_nr = 1'b0;
      end
    endcase

    unique case(vpu_req_o.opcode)
      VADD_VV,
      VADD_VI,
      VADD_VX:    operation_o = VADD;
      VSUB_VV, 
      VSUB_VX:    operation_o = VSUB;
      VRSUB_VI, 
      VRSUB_VX:   operation_o = VRSUB;
      VAND_VV,   
      VAND_VI,   
      VAND_VX:    operation_o = VAND;
      VOR_VV, 
      VOR_VI, 
      VOR_VX:     operation_o = VOR;
      VXOR_VV,  
      VXOR_VI,  
      VXOR_VX:    operation_o = VXOR; 
      VSLL_VV,  
      VSLL_VX,  
      VSLL_VI:    operation_o = VSLL;
      VSRL_VV,  
      VSRL_VX,  
      VSRL_VI:    operation_o = VSRL;
      VSRA_VV,  
      VSRA_VX,  
      VSRA_VI:    operation_o = VSRA; 
      VMINU_VV,  
      VMINU_VX:   operation_o = VMINU;
      VMIN_VV,  
      VMIN_VX:    operation_o = VMIN;
      VMAXU_VV,  
      VMAXU_VX:   operation_o = VMAXU;
      VMAX_VV,  
      VMAX_VX:    operation_o = VMAX;
      VMSEQ_VV,  
      VMSEQ_VX,  
      VMSEQ_VI:   operation_o = VMSEQ;
      VMSNE_VV,  
      VMSNE_VX,  
      VMSNE_VI:   operation_o = VMSNE;
      VMSLTU_VV, 
      VMSLTU_VX:  operation_o = VMSLTU;
      VMSLT_VV, 
      VMSLT_VX:   operation_o = VMSLT;
      VMUL_VV, 
      VMUL_VX:    operation_o = VMUL;
      VMULH_VV,
      VMULH_VX:   operation_o = VMULH;
      VMULHU_VV,
      VMULHU_VX:  operation_o = VMULHU;
      VMULHSU_VV,
      VMULHSU_VX: operation_o = VMULHSU;
      VMACC_VV,
      VMACC_VX:   operation_o = VMACC;
      VNMSAC_VV,
      VNMSAC_VX:  operation_o = VNMSAC;
      VMADD_VV,
      VMADD_VX:   operation_o = VMADD;
      VMERGE_VVM,
      VMERGE_VXM,
      VMERGE_VIM,
      VMV_VV,
      VMV_VX,
      VMV_VI, 
      VMV_XS,
      VMV_SX:     operation_o = VMV;
      VMV1R_V,
      VMV2R_V,
      VMV4R_V,
      VMV8R_V:    operation_o = VMV;
      VREDSUM_VS: operation_o = VREDSUM;
      default:    operation_o = vector_ops_pkg::NOP;
    endcase

    scalar_val = '0;
    //Immediate decoding
    if (vpu_req_d.funct3 == OPIVI_CSRRC || vpu_req_d.funct3 == OPIVX || vpu_req_d.funct3 == OPMVX_CSRRSI) begin
        // Select and optionally sign-extend the scalar source
        case (vtype_d.vsew)
            SEW_8:  scalar_val = (vpu_req_d.funct3 == OPIVI_CSRRC) ? 
                                $signed(vpu_req_d.rs1[7:0])  : vpu_req_d.rs1[7:0];
            SEW_16: scalar_val = (vpu_req_d.funct3 == OPIVI_CSRRC) ? 
                                $signed(vpu_req_d.rs1[15:0]) : vpu_req_d.rs1[15:0];
            SEW_32: scalar_val = vpu_req_d.rs1;
            default: scalar_val = '0;
        endcase

        // Replicate scalar across all elements
        case (vtype_d.vsew)
            SEW_8:  for (int i = 0; i < vl_d && i < MAXVL;       i++) vpu_req_d.rs_rdata1[i*8  +: 8]  = scalar_val[7:0];
            SEW_16: for (int i = 0; i < vl_d && i < (MAXVL/2);   i++) vpu_req_d.rs_rdata1[i*16 +: 16] = scalar_val[15:0];
            SEW_32: for (int i = 0; i < vl_d && i < (MAXVL/4);   i++) vpu_req_d.rs_rdata1[i*32 +: 32] = scalar_val[31:0];
            default: ;
        endcase
    end    

    if (vtype_q.vill ) begin  
      illegal_req_d = 1'b1;
    end  

  end : decoding


  /////////
  // CSR //
  /////////

  always_comb begin
    vtype_supported = 1'b1;
    csr_we_d        = 1'b0;
    csr_valid_d     = 1'b0;
    vlmax_d         = vlmax_q;
    vtype_d         = vtype_q; 
    vl_d            = vl_q;
    vstart_d        = vstart_q;
    issue_rs1       = '0;
    issue_rd        = '0; 
    result_d        = '0;

    if (state_o == S_BUSY) begin
        unique case (vpu_req_o.opcode)
          VSETVLI,
          VSETIVLI, 
          VSETVL: begin
            csr_valid_d = ~csr_valid_q;           
            issue_rs1 = vpu_req_o.rs1;
            issue_rd  = vpu_req_o.rd;
            vstart_d  = '0;
          end
          default: ; 
        endcase
    end else begin
        csr_valid_d = 1'b0; 
    end

    // Check for unsupported configuration    
    unique case (vpu_req_o.csr_vtype.vsew) 
      SEW_8, SEW_16, SEW_32: ; 
      default: begin 
        vtype_supported = 1'b0;
      end
    endcase

    unique case (vpu_req_o.csr_vtype.vlmul) 
      LMUL_F4: int_lmul4 = 1;   // 1/4 LMUL
      LMUL_F2: int_lmul4 = 2;   // 1/2 LMUL
      LMUL_1:  int_lmul4 = 4;   // 1 LMUL
      default: begin 
        vtype_supported = 1'b0;
        int_lmul4 = 0;
      end
    endcase

    if (vpu_req_o.csr_vtype.vta === 1'bx || vpu_req_o.csr_vtype.vma === 1'bx ) begin
      vtype_supported = 1'b0;
    end
 
    // begin: AVL assignation 
    if (csr_valid_d && !vtype_supported) begin  
      vtype_d      = '0;
      vl_d         = '0;
      vlmax_d      = 32'd0;
      vtype_d.vill = 1'b1;
      csr_we_d     = 1'b1;    
      result_d     = '0;
    end else if (csr_valid_d) begin
      
      vtype_d = vpu_req_o.csr_vtype;
      vlmax_d = compute_vlmax(vtype_d.vsew);  

      // Decode AVL
      if (vpu_req_o.opcode == VSETIVLI) begin 
        avl_int = issue_rs1;
      end else begin           // vsetvli / vsetvl
        if ( rs1_addr_q == 5'd0) begin 
          if (issue_rd == 5'd0) begin
            avl_int = vl_q;
            // Reserved if new VLMAX would shrink the current vl.
            if ((vlmax_d < vl_q) || vtype_q.vill || vlmax_d != vlmax_q) begin
              vtype_d.vill = 1'b1;
            end 
          end else begin
            // rs1 == x0 && rd != x0 -> AVL treated as ~0 to request VLMAX
            avl_int = 32'hFFFFFFFF;
          end
        end else begin
          // rs1 != x0: AVL is the unsigned integer in x[rs1]
          avl_int = issue_rs1;
        end
      end

      // rs1==x0 && rd==x0 case, skip normal update
      if (!vtype_d.vill) begin
        if (avl_int == 32'hFFFFFFFF) begin
          new_vl_int = vlmax_d;
        end else begin
          new_vl_int = compute_new_vl(avl_int, vlmax_d);
        end
        vl_d        = new_vl_int;
        csr_we_d    = 1'b1;
        if ((issue_rd == 5'h0) && (issue_rs1 == 5'h0)) begin 
          csr_we_d    = 1'b0;
        end

        // normal success clears vill bit
        vtype_d.vill = 1'b0;

        // Assertions to validate VL rules:
        // a) VL = 0 if AVL = 0
        if (avl_int == 0) begin
            assert (new_vl_int == 0) else $fatal("vpu_csr assertion (a) failed: AVL==0 but VL=%0d", new_vl_int);
        end
        // b) VL > 0 if AVL > 0
        if (avl_int > 0) begin
            assert (new_vl_int > 0) else $fatal("vpu_csr assertion (b) failed: AVL=%0d but VL=%0d", avl_int, new_vl_int);
        end
        // c) VL ≤ VLMAX
        assert (new_vl_int <= vlmax_d) else $fatal("vpu_csr assertion (c) failed: VL=%0d > VLMAX=%0d (AVL=%0d)", new_vl_int, vlmax_d, avl_int);
        // d) VL ≤ AVL
        if (avl_int != -1) begin
            assert (new_vl_int <= avl_int) else $fatal("vpu_csr assertion (d) failed: VL=%0d > AVL=%0d (VLMAX=%0d)", new_vl_int, avl_int, vlmax_d);
        end

      end else begin
        vl_d          = '0;
        vtype_d       = '0; 
        vtype_d.vill  = 1'b1;
      end

      if (vpu_req_d.opcode == VMV_XS) begin
        csr_we_d = 1'b1; 
      end

      result_d = vl_d; 
    //end  : AVL assignation
    end else if (vpu_req_d.mopcode == system) begin  

      // CSRR 
      unique case (csr_target) 
        CSR_VLENB: begin                        //TODO: other CSRs  
          if (csr_handle.read_CSR && ! csr_handle.write_CSR) begin
            result_d = VLENB;
            csr_we_d = 1'b1; 
          end else begin
            result_d = 1'b0;
          end
        end
        default:;
      endcase
    end   
  end


  always_ff  @(posedge clk_i or negedge rst_ni) begin 
    if(!rst_ni) begin
      vtype_q    <= '0;
      vl_q       <= '0;
      vstart_q   <= '0;
      rs1_addr_q <= '0;
      result_q   <= '0;
      vlmax_q    <= '0;
      csr_we_q   <= '0;
      csr_valid_q <= '0;
      illegal_req_q <= '0;
    end else begin
      vtype_q     <= vtype_d;
      vl_q        <= vl_d;
      vstart_q    <= vstart_d;
      rs1_addr_q  <= rs1_addr_d;
      result_q    <= result_d;
      vlmax_q     <= vlmax_d;
      csr_we_q    <= csr_we_d;
      csr_valid_q <= csr_valid_d;
      illegal_req_q <= illegal_req_d;
    end
  end


  /////////
  // FSM //
  /////////
  
  always_comb begin
    state_d          = state_q;
    issue_ready_o    = 1'b0;
    op_valid_simd_d  = 1'b0;
    vrf_op_valid_d   = 1'b0;
    vrf_we_d         = 1'b0; 
     
    unique case (state_q)   
      S_IDLE: begin
        if (issue_valid_i) begin
          issue_ready_o = 1'b1;
          if (|sel)
            state_d = S_BUSY;
        end
      end
      S_BUSY: begin
          unique case(vpu_req_q.mopcode)
            load_fp,  
            store_fp: begin
                if (!illegal_req_o) begin
                  vrf_op_valid_d = 1'b1;
                end
            end
            op_v:  begin
              // Arithmetic 
              if ( !state_was_busy_o && (vpu_req_q.funct3 != OPCFG_CSRRCI) && !illegal_req_o) begin   
                  op_valid_simd_d = 1'b1;      
                  vrf_op_valid_d = 1'b1;
                  vrf_we_d = 1'b1; 
              end 
              // For VMV<n>R.V:
              if (vpu_req_q.is_vmv_nr) begin
                if (vmv_active_i && (vmv_offset_i < nreg_i) && (vmv_offset_i != (nreg_i - 1))  && done_wi) begin
                  op_valid_simd_d = 1'b1;      
                  vrf_op_valid_d = 1'b1;
                  vrf_we_d = 1'b1; 
                end 
              end
            end
            default: ;
          endcase  

          if(issue_result_valid_i) begin  
            state_d = S_IDLE;
          end else begin
            state_d = S_BUSY;
          end
      end 
      default: state_d = S_IDLE;
    endcase
  end  

  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      vpu_req_q      <= '0;
      hartid_q       <= 1'b0;
      id_q           <= 1'b0; 
      state_was_busy_o <= 1'b0;
    end else begin 

      state_q <= state_d;
      state_was_busy_o <= (state_q == S_BUSY); 

      //Update when new instruction ready to proccess
      if(state_q == S_IDLE) begin   
        vpu_req_q <= vpu_req_d;
        hartid_q  <= hartid_d;
        id_q      <= id_d;
      end 
    end
  end
  
  //External module activation
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin
      op_valid_simd_q <= 1'b0;
      vrf_op_valid_q <= 1'b0;
      vrf_we_q <= 1'b0;
    end else begin 
      op_valid_simd_q <= op_valid_simd_d;
      vrf_op_valid_q    <= vrf_op_valid_d;
      vrf_we_q        <= vrf_we_d;
    end
  end


  assert property (@(posedge clk_i) $onehot0(sel))
  else
    `ASSERT_WARNING("This offloaded instruction is valid for multiple coprocessor instructions !");

endmodule
