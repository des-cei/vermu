// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)
//
// TODO: 
//  - Activation of decoder with issue_valid (implement condition?)
//  - Pending to implement the following instructions:
//    vop.v, vwop, vnop, load/store segment (7.8)
//  - Check validity of parameter dependant instructions (Done example: vmv1r.v, vmv2r.v, etc.)
//  - Check validity of SEW/EEW/LMUL conditions (specially in wide/narrow instructions) ?

module vpu_xif_decoder
import rvv_instr_pkg::*;
import vpu_pkg::*;
#(
    parameter int unsigned NrRgprPorts       = 2,
    parameter type         readregflags_t   = logic,
    parameter type         x_issue_resp_t = cvxif_types_pkg::x_issue_resp_t
)(
    input  logic          issue_valid_i,
    input  logic [31:0]   instr_i,
    input  vtype_t       vtype_i,
    output x_issue_resp_t x_issue_resp_o,
    output vec_instr_e    vec_instr_o
);
  
    // Register alignment check functions 
    function automatic logic is_misaligned(
        input logic [4:0] reg_idx,
        input lmul_e      lmul
    );
        unique case (lmul)
            LMUL_2: is_misaligned = reg_idx[0];
            LMUL_4: is_misaligned = |reg_idx[1:0];
            LMUL_8: is_misaligned = |reg_idx[2:0];
            default: is_misaligned = 1'b0;
        endcase
    endfunction

    function automatic lmul_e lmul_x2(
        input lmul_e lmul,
        output logic illegal
    );
        illegal = 1'b0;

        unique case (lmul)
            LMUL_F4: return LMUL_F2;
            LMUL_F2: return LMUL_1;
            LMUL_1:  return LMUL_2;
            LMUL_2:  return LMUL_4;
            LMUL_4:  return LMUL_8;
            default: begin
                illegal = 1'b1;
                return LMUL_8;
            end
        endcase
    endfunction

    function automatic lmul_e lmul_div2(
        input lmul_e lmul,
        output logic illegal
    );
        illegal = 1'b0;

        unique case (lmul)
            LMUL_F2: return LMUL_F4;
            LMUL_1:  return LMUL_F2;
            LMUL_2:  return LMUL_1;
            LMUL_4:  return LMUL_2;
            LMUL_8:  return LMUL_4;
            default: begin
                illegal = 1'b1;
                return LMUL_F4;
            end
        endcase
    endfunction

    logic        uses_vd;
    logic        uses_vs1;
    logic        uses_vs2;
    logic        uses_vs3;
    logic        illegal_align;
    logic        illegal_emul_vd;
    logic        illegal_emul_vs1;
    logic        illegal_emul_vs2;
    logic        illegal_emul_vs3;
    lmul_e       emul_vd;
    lmul_e       emul_vs1;
    lmul_e       emul_vs2;
    lmul_e       emul_vs3;

    /////////////////////////////
    // Instruction Recognition //
    /////////////////////////////
      
    // Recognize if it is vector instruction, and if supported by this VPU.
      
    major_opcode_e major_opcode;
    vec_funct3_e   fmt;
    logic          vm;
    logic [5:0]    funct6;
    logic [2:0]    nf;
    logic          mew;
    logic [1:0]    mop;
    logic [2:0]    width;
    logic [4:0]    umop;

    logic [4:0] vd;
    logic [4:0] vs1;
    logic [4:0] vs2;
    logic [4:0] vs3;


    assign vd  = instr_i[11:7];
    assign vs1 = instr_i[19:15];
    assign vs2 = instr_i[24:20];
    assign vs3 = instr_i[11:7];

    always_comb begin: vproc_decoder
        // Instr parameters
        major_opcode    = OPCODE_NONE;
        fmt             = FMT_OPIVV;
        vm              = '0;
        funct6          = '0;
        nf              = '0;
        mew             = '0;
        mop             = '0;
        width           = '0;
        umop            = '0;
        
        // Helpers
        uses_vd  = 1'b0;
        uses_vs1 = 1'b0;
        uses_vs2 = 1'b0;
        uses_vs3 = 1'b0;
    
        emul_vd  = vtype_i.vlmul;
        emul_vs1 = vtype_i.vlmul;
        emul_vs2 = vtype_i.vlmul;
        emul_vs3 = vtype_i.vlmul;
    
        illegal_emul_vd  = 1'b0;
        illegal_emul_vs1 = 1'b0;
        illegal_emul_vs2 = 1'b0;
        illegal_emul_vs3 = 1'b0;

        illegal_align = 1'b0;
          
        vec_instr_o                  = INSTR_NONE;
        x_issue_resp_o.accept        = 1'b0;
        x_issue_resp_o.writeback     = 1'b0;
        x_issue_resp_o.register_read = '0;
        
        if (issue_valid_i) begin
            major_opcode    = major_opcode_e'(instr_i[6:0]);
            fmt             = vec_funct3_e'(instr_i[14:12]);
            vm              = instr_i[25];
            funct6          = instr_i[31:26];
            nf              = instr_i[31:29];
            mew             = instr_i[28];
            mop             = instr_i[27:26];
            width           = instr_i[14:12];
            umop            = instr_i[24:20];

            unique case (major_opcode)
         
                //////////////////////////////////////////////////////////
                // OP-V : arithmetic / config / mask-logic / reductions //
                //////////////////////////////////////////////////////////
                OPCODE_OP_V: begin
                    unique case (fmt)
        
                    // Integer vector-vector
                        FMT_OPIVV: begin
                            unique case (funct6)
                                6'b000000: begin vec_instr_o = VADD_VV;         x_issue_resp_o.accept = 1'b1; end    
                                6'b000010: begin vec_instr_o = VSUB_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b000100: begin vec_instr_o = VMINU_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b000101: begin vec_instr_o = VMIN_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b000110: begin vec_instr_o = VMAXU_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b000111: begin vec_instr_o = VMAX_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b001001: begin vec_instr_o = VAND_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b001010: begin vec_instr_o = VOR_VV;          x_issue_resp_o.accept = 1'b1; end
                                6'b001011: begin vec_instr_o = VXOR_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b001100: begin vec_instr_o = VRGATHER_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b001110: begin vec_instr_o = VRGATHEREI16_VV; x_issue_resp_o.accept = 1'b1; end 
                                6'b010000: begin vec_instr_o = VADC_VVM;        x_issue_resp_o.accept = (!vm) ? 1'b1 : 1'b0; end 
                                6'b010001: begin 
                                    vec_instr_o = (vm) ? VMADC_VV : VMADC_VVM;                                          // vmadc.vvm / vmadc.vv (vm bit selects variant)
                                    x_issue_resp_o.accept = 1'b1; 
                                end
                                6'b010010: begin vec_instr_o = VSBC_VVM;        x_issue_resp_o.accept = (!vm) ? 1'b1 : 1'b0;; end 
                                6'b010011: begin 
                                    vec_instr_o = (vm) ? VMSBC_VV : VMSBC_VVM;
                                    x_issue_resp_o.accept = 1'b1;
                                end
                                6'b010111: begin 
                                        if (!vm) begin
                                            vec_instr_o = VMERGE_VVM;
                                        end else begin 
                                            vec_instr_o = VMV_VV;
                                        end
                                        x_issue_resp_o.accept = 1'b1;
                                end  
                                6'b011000: begin vec_instr_o = VMSEQ_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b011001: begin vec_instr_o = VMSNE_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b011010: begin vec_instr_o = VMSLTU_VV;       x_issue_resp_o.accept = 1'b1; end
                                6'b011011: begin vec_instr_o = VMSLT_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b011100: begin vec_instr_o = VMSLEU_VV;       x_issue_resp_o.accept = 1'b1; end
                                6'b011101: begin vec_instr_o = VMSLE_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b100000: begin vec_instr_o = VSADDU_VV;       x_issue_resp_o.accept = 1'b1; end
                                6'b100001: begin vec_instr_o = VSADD_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b100010: begin vec_instr_o = VSSUBU_VV;       x_issue_resp_o.accept = 1'b1; end
                                6'b100011: begin vec_instr_o = VSSUB_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b100101: begin vec_instr_o = VSLL_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b100111: begin vec_instr_o = VSMUL_VV;        x_issue_resp_o.accept = 1'b1; end 
                                6'b101000: begin vec_instr_o = VSRL_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b101001: begin vec_instr_o = VSRA_VV;         x_issue_resp_o.accept = 1'b1; end
                                6'b101010: begin vec_instr_o = VSSRL_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b101011: begin vec_instr_o = VSSRA_VV;        x_issue_resp_o.accept = 1'b1; end
                                6'b101100: begin vec_instr_o = VNSRL_WV;        x_issue_resp_o.accept = 1'b1; end 
                                6'b101101: begin vec_instr_o = VNSRA_WV;        x_issue_resp_o.accept = 1'b1; end
                                6'b101110: begin vec_instr_o = VNCLIPU_WV;      x_issue_resp_o.accept = 1'b1; end
                                6'b101111: begin vec_instr_o = VNCLIP_WV;       x_issue_resp_o.accept = 1'b1; end
                                6'b110000: begin vec_instr_o = VWREDSUMU_VS;    x_issue_resp_o.accept = 1'b1; end 
                                6'b110001: begin vec_instr_o = VWREDSUM_VS;     x_issue_resp_o.accept = 1'b1; end
                                default:   ; 
                            endcase
                        end
                
                        // Integer vector-scalar (rs1)
                        FMT_OPIVX: begin
                            x_issue_resp_o.register_read = {1'b0, 1'b1};
                            unique case (funct6)
                                6'b000000: begin vec_instr_o = VADD_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b000010: begin vec_instr_o = VSUB_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b000011: begin vec_instr_o = VRSUB_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b000100: begin vec_instr_o = VMINU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b000101: begin vec_instr_o = VMIN_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b000110: begin vec_instr_o = VMAXU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b000111: begin vec_instr_o = VMAX_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b001001: begin vec_instr_o = VAND_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b001010: begin vec_instr_o = VOR_VX;        x_issue_resp_o.accept = 1'b1; end
                                6'b001011: begin vec_instr_o = VXOR_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b001100: begin vec_instr_o = VRGATHER_VX;   x_issue_resp_o.accept = 1'b1; end
                                6'b001110: begin vec_instr_o = VSLIDEUP_VX;   x_issue_resp_o.accept = 1'b1; end
                                6'b001111: begin vec_instr_o = VSLIDEDOWN_VX; x_issue_resp_o.accept = 1'b1; end
                                6'b010000: begin vec_instr_o = VADC_VXM;      x_issue_resp_o.accept = (!vm) ? 1'b1 : 1'b0; end
                                6'b010001: begin 
                                    vec_instr_o = (vm) ? VMADC_VX : VMADC_VXM;               // vm selects vmadc.vxm vs vmadc.vx
                                    x_issue_resp_o.accept = 1'b1;
                                end 
                                6'b010010: begin vec_instr_o = VSBC_VXM;      x_issue_resp_o.accept = (!vm) ? 1'b1 : 1'b0; end
                                6'b010011: begin 
                                    vec_instr_o = (vm) ? VMSBC_VX : VMSBC_VXM;
                                    x_issue_resp_o.accept = 1'b1;
                                end
                                6'b010111: begin
                                        if (!vm) begin
                                            vec_instr_o = VMERGE_VXM;
                                        end else begin 
                                            vec_instr_o = VMV_VX;
                                        end
                                        x_issue_resp_o.accept = 1'b1;
                                end
                                6'b011000: begin vec_instr_o = VMSEQ_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b011001: begin vec_instr_o = VMSNE_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b011010: begin vec_instr_o = VMSLTU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b011011: begin vec_instr_o = VMSLT_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b011100: begin vec_instr_o = VMSLEU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b011101: begin vec_instr_o = VMSLE_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b011110: begin vec_instr_o = VMSGTU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b011111: begin vec_instr_o = VMSGT_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b100000: begin vec_instr_o = VSADDU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b100001: begin vec_instr_o = VSADD_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b100010: begin vec_instr_o = VSSUBU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b100011: begin vec_instr_o = VSSUB_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b100101: begin vec_instr_o = VSLL_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b100111: begin vec_instr_o = VSMUL_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101000: begin vec_instr_o = VSRL_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b101001: begin vec_instr_o = VSRA_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b101010: begin vec_instr_o = VSSRL_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101011: begin vec_instr_o = VSSRA_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101100: begin vec_instr_o = VNSRL_WX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101101: begin vec_instr_o = VNSRA_WX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101110: begin vec_instr_o = VNCLIPU_WX;    x_issue_resp_o.accept = 1'b1; end
                                6'b101111: begin vec_instr_o = VNCLIP_WX;     x_issue_resp_o.accept = 1'b1; end
                            default:   ;
                            endcase
                        end
                
                        // Integer vector-immediate
                        FMT_OPIVI_CSRRC: begin
                            unique case (funct6)
                                6'b000000: begin vec_instr_o = VADD_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b000011: begin vec_instr_o = VRSUB_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b001001: begin vec_instr_o = VAND_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b001010: begin vec_instr_o = VOR_VI;          x_issue_resp_o.accept = 1'b1; end
                                6'b001011: begin vec_instr_o = VXOR_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b001100: begin vec_instr_o = VRGATHER_VI;     x_issue_resp_o.accept = 1'b1; end
                                6'b001110: begin vec_instr_o = VSLIDEUP_VI;     x_issue_resp_o.accept = 1'b1; end
                                6'b001111: begin vec_instr_o = VSLIDEDOWN_VI;   x_issue_resp_o.accept = 1'b1; end
                                6'b010000: begin vec_instr_o = VADC_VIM;        x_issue_resp_o.accept = (!vm) ? 1'b1 : 1'b0; end
                                6'b010001: begin
                                    vec_instr_o = (vm) ? VMADC_VI : VMADC_VIM;  
                                    x_issue_resp_o.accept = 1'b1;
                                end 
                                6'b010111: begin
                                        if (!vm) begin
                                            vec_instr_o = VMERGE_VIM;
                                        end else begin 
                                            vec_instr_o = VMV_VI;
                                        end
                                        x_issue_resp_o.accept = 1'b1;
                                end
                                6'b011000: begin vec_instr_o = VMSEQ_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b011001: begin vec_instr_o = VMSNE_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b011100: begin vec_instr_o = VMSLEU_VI;       x_issue_resp_o.accept = 1'b1; end
                                6'b011101: begin vec_instr_o = VMSLE_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b011110: begin vec_instr_o = VMSGTU_VI;       x_issue_resp_o.accept = 1'b1; end
                                6'b011111: begin vec_instr_o = VMSGT_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b100000: begin vec_instr_o = VSADDU_VI;       x_issue_resp_o.accept = 1'b1; end
                                6'b100001: begin vec_instr_o = VSADD_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b100101: begin vec_instr_o = VSLL_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b101000: begin vec_instr_o = VSRL_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b101001: begin vec_instr_o = VSRA_VI;         x_issue_resp_o.accept = 1'b1; end
                                6'b101010: begin vec_instr_o = VSSRL_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b101011: begin vec_instr_o = VSSRA_VI;        x_issue_resp_o.accept = 1'b1; end
                                6'b101100: begin vec_instr_o = VNSRL_WI;        x_issue_resp_o.accept = 1'b1; end
                                6'b101101: begin vec_instr_o = VNSRA_WI;        x_issue_resp_o.accept = 1'b1; end
                                6'b101110: begin vec_instr_o = VNCLIPU_WI;      x_issue_resp_o.accept = 1'b1; end
                                6'b101111: begin vec_instr_o = VNCLIP_WI;       x_issue_resp_o.accept = 1'b1; end
                                // vmv<nr>r.v: funct6 = 100111, vm=1, vs2=v0, simm5 encodes nr-1 (0→1reg, 1→2reg, 3→4reg, 7→8reg)
                                // These share funct6=100111 with vsmul but vm=1 AND funct3=OPIVI distinguishes them unambiguously
                                // Zve32x only requires vmv1r; add vmv2r/vmv4r/vmv8r if your implementation supports them.
                                6'b100111: begin
                                    vec_instr_o = VMVNRR_V;
                                    case ({instr_i[19:15], vm})
                                        6'b00000_1, 6'b00001_1, 6'b00011_1, 6'b00111_1: x_issue_resp_o.accept = 1'b1;
                                        default: ; 
                                    endcase 
                                end
                                default:   ;
                            endcase
                        end
                
                        // Mask/multiply vector-vector: mul/div/macc, reductions,
                        // mask-logical ops and widening ops all share this format.
                        FMT_OPMVV_CSRRS: begin
                            unique case (funct6)
                                // reductions
                                6'b000000: begin vec_instr_o = VREDSUM_VS;   x_issue_resp_o.accept = 1'b1; end
                                6'b000001: begin vec_instr_o = VREDAND_VS;   x_issue_resp_o.accept = 1'b1; end
                                6'b000010: begin vec_instr_o = VREDOR_VS;    x_issue_resp_o.accept = 1'b1; end
                                6'b000011: begin vec_instr_o = VREDXOR_VS;   x_issue_resp_o.accept = 1'b1; end
                                6'b000100: begin vec_instr_o = VREDMINU_VS;  x_issue_resp_o.accept = 1'b1; end
                                6'b000101: begin vec_instr_o = VREDMIN_VS;   x_issue_resp_o.accept = 1'b1; end
                                6'b000110: begin vec_instr_o = VREDMAXU_VS;  x_issue_resp_o.accept = 1'b1; end
                                6'b000111: begin vec_instr_o = VREDMAX_VS;   x_issue_resp_o.accept = 1'b1; end
                                6'b001000: begin vec_instr_o = VAADDU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b001001: begin vec_instr_o = VAADD_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b001010: begin vec_instr_o = VASUBU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b001011: begin vec_instr_o = VASUB_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b010111: begin vec_instr_o = VCOMPRESS_VM; x_issue_resp_o.accept = (vm) ? 1'b1 : 1'b0; end
                                6'b011000: begin vec_instr_o = VMANDNOT_MM;  x_issue_resp_o.accept = 1'b1; end      // Todo: change mneumonics? mask-register logical (vs1/vs2 are mask registers, vm field ignored)
                                6'b011001: begin vec_instr_o = VMAND_MM;     x_issue_resp_o.accept = 1'b1; end
                                6'b011010: begin vec_instr_o = VMOR_MM;      x_issue_resp_o.accept = 1'b1; end
                                6'b011011: begin vec_instr_o = VMXOR_MM;     x_issue_resp_o.accept = 1'b1; end
                                6'b011100: begin vec_instr_o = VMORNOT_MM;   x_issue_resp_o.accept = 1'b1; end
                                6'b011101: begin vec_instr_o = VMNAND_MM;    x_issue_resp_o.accept = 1'b1; end
                                6'b011110: begin vec_instr_o = VMNOR_MM;     x_issue_resp_o.accept = 1'b1; end
                                6'b011111: begin vec_instr_o = VMXNOR_MM;    x_issue_resp_o.accept = 1'b1; end
                                6'b100000: begin vec_instr_o = VDIVU_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b100001: begin vec_instr_o = VDIV_VV;      x_issue_resp_o.accept = 1'b1; end
                                6'b100010: begin vec_instr_o = VREMU_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b100011: begin vec_instr_o = VREM_VV;      x_issue_resp_o.accept = 1'b1; end 
                                6'b100100: begin vec_instr_o = VMULHU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b100101: begin vec_instr_o = VMUL_VV;      x_issue_resp_o.accept = 1'b1; end
                                6'b100110: begin vec_instr_o = VMULHSU_VV;   x_issue_resp_o.accept = 1'b1; end
                                6'b100111: begin vec_instr_o = VMULH_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b101001: begin vec_instr_o = VMADD_VV;     x_issue_resp_o.accept = 1'b1; end 
                                6'b101011: begin vec_instr_o = VNMSUB_VV;    x_issue_resp_o.accept = 1'b1; end 
                                6'b101101: begin vec_instr_o = VMACC_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b101111: begin vec_instr_o = VNMSAC_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b110000: begin vec_instr_o = VWADDU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b110001: begin vec_instr_o = VWADD_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b110010: begin vec_instr_o = VWSUBU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b110011: begin vec_instr_o = VWSUB_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b110100: begin vec_instr_o = VWADDU_WV;    x_issue_resp_o.accept = 1'b1; end
                                6'b110101: begin vec_instr_o = VWADD_WV;     x_issue_resp_o.accept = 1'b1; end
                                6'b110110: begin vec_instr_o = VWSUBU_WV;    x_issue_resp_o.accept = 1'b1; end
                                6'b110111: begin vec_instr_o = VWSUB_WV;     x_issue_resp_o.accept = 1'b1; end
                                6'b111000: begin vec_instr_o = VWMULU_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b111010: begin vec_instr_o = VWMULSU_VV;   x_issue_resp_o.accept = 1'b1; end
                                6'b111011: begin vec_instr_o = VWMUL_VV;     x_issue_resp_o.accept = 1'b1; end
                                6'b111100: begin vec_instr_o = VWMACCU_VV;   x_issue_resp_o.accept = 1'b1; end
                                6'b111101: begin vec_instr_o = VWMACC_VV;    x_issue_resp_o.accept = 1'b1; end
                                6'b111111: begin vec_instr_o = VWMACCSU_VV;  x_issue_resp_o.accept = 1'b1; end
                                6'b010000: begin // VWXUNARY0   // Todo: register read?
                                    unique case (instr_i[19:15]) // vs1
                                        5'b00000: begin 
                                            vec_instr_o = VMV_XS;
                                            x_issue_resp_o.accept = (vm) ? 1'b1 : 1'b0;
                                            x_issue_resp_o.writeback = 1'b1; end 
                                        5'b10000: begin vec_instr_o = VCPOP_M;  x_issue_resp_o.accept = 1'b1; x_issue_resp_o.writeback = 1'b1; end // Old vpopc.m
                                        5'b10001: begin vec_instr_o = VFIRST_M; x_issue_resp_o.accept = 1'b1; x_issue_resp_o.writeback = 1'b1; end 
                                        default:  ;
                                    endcase
                                end
            
                                6'b010010: begin // VXUNARY0    // Todo: register read? unify operation?
                                    unique case (instr_i[19:15]) // vs1
                                        5'b00010: begin vec_instr_o = VZEXT_VF8;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00011: begin vec_instr_o = VSEXT_VF8;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00100: begin vec_instr_o = VZEXT_VF4;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00101: begin vec_instr_o = VSEXT_VF4;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00110: begin vec_instr_o = VZEXT_VF2;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00111: begin vec_instr_o = VSEXT_VF2;  x_issue_resp_o.accept = 1'b1; end 
                                        default:  ;
                                    endcase
                                end
            
                                6'b010100: begin // VMUNARY0     // Todo: register read?
                                    unique case (instr_i[19:15]) // vs1
                                        5'b00001: begin vec_instr_o = VMSBF_M;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00010: begin vec_instr_o = VMSOF_M;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b00011: begin vec_instr_o = VMSIF_M;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b10000: begin vec_instr_o = VIOTA_M;  x_issue_resp_o.accept = 1'b1; end 
                                        5'b10001: begin vec_instr_o = VID_V;    x_issue_resp_o.accept = 1'b1; end 
                                        default:  ;
                                    endcase
                                end
                            default:   ;
                            endcase
                        end
                
                        // Mask/multiply vector-scalar (rs1)
                        FMT_OPMVX_CSRRSI: begin
                            x_issue_resp_o.register_read = {1'b0, 1'b1};
                            unique case (funct6)
                                6'b001000: begin vec_instr_o = VAADDU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b001001: begin vec_instr_o = VAADD_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b001010: begin vec_instr_o = VASUBU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b001011: begin vec_instr_o = VASUB_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b001110: begin vec_instr_o = VSLIDE1UP_VX;   x_issue_resp_o.accept = 1'b1; end
                                6'b001111: begin vec_instr_o = VSLIDE1DOWN_VX; x_issue_resp_o.accept = 1'b1; end
                                6'b100000: begin vec_instr_o = VDIVU_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b100001: begin vec_instr_o = VDIV_VX;        x_issue_resp_o.accept = 1'b1; end
                                6'b100010: begin vec_instr_o = VREMU_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b100011: begin vec_instr_o = VREM_VX;        x_issue_resp_o.accept = 1'b1; end
                                6'b100100: begin vec_instr_o = VMULHU_VX;      x_issue_resp_o.accept = 1'b1; end               
                                6'b100101: begin vec_instr_o = VMUL_VX;        x_issue_resp_o.accept = 1'b1; end
                                6'b100110: begin vec_instr_o = VMULHSU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b100111: begin vec_instr_o = VMULH_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b101001: begin vec_instr_o = VMADD_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b101011: begin vec_instr_o = VNMSUB_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b101101: begin vec_instr_o = VMACC_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b101111: begin vec_instr_o = VNMSAC_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b110000: begin vec_instr_o = VWADDU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b110001: begin vec_instr_o = VWADD_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b110010: begin vec_instr_o = VWSUBU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b110011: begin vec_instr_o = VWSUB_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b110100: begin vec_instr_o = VWADDU_WX;      x_issue_resp_o.accept = 1'b1; end
                                6'b110101: begin vec_instr_o = VWADD_WX;       x_issue_resp_o.accept = 1'b1; end
                                6'b110110: begin vec_instr_o = VWSUBU_WX;      x_issue_resp_o.accept = 1'b1; end
                                6'b110111: begin vec_instr_o = VWSUB_WX;       x_issue_resp_o.accept = 1'b1; end
                                6'b111000: begin vec_instr_o = VWMULU_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b111010: begin vec_instr_o = VWMULSU_VX;     x_issue_resp_o.accept = 1'b1; end          
                                6'b111011: begin vec_instr_o = VWMUL_VX;       x_issue_resp_o.accept = 1'b1; end
                                6'b111100: begin vec_instr_o = VWMACCU_VX;     x_issue_resp_o.accept = 1'b1; end
                                6'b111101: begin vec_instr_o = VWMACC_VX;      x_issue_resp_o.accept = 1'b1; end
                                6'b111110: begin vec_instr_o = VWMACCUS_VX;    x_issue_resp_o.accept = 1'b1; end
                                6'b111111: begin vec_instr_o = VWMACCSU_VX;    x_issue_resp_o.accept = 1'b1; end
                                6'b010000: begin // VRXUNARY0
                                    unique case (instr_i[24:20]) // vs2
                                        5'b00000: begin vec_instr_o = VMV_SX; x_issue_resp_o.accept = (vm) ? 1'b1 : 1'b0; end 
                                        default:  ;
                                    endcase
                                    end
                                default:   ;
                            endcase
                        end
                
                        // Vector configuration: vsetvli / vsetivli / vsetvl
                        FMT_OPCFG_CSRRCI: begin
                            unique casez (instr_i[31:25])
                                7'b0??????: begin vec_instr_o = VSETVLI;  x_issue_resp_o.accept = 1'b1;
                                            if(!(instr_i[19:15] == '0) && !(instr_i[11:7] == '0))begin
                                                x_issue_resp_o.writeback = 1'b1;
                                            end 
                                            x_issue_resp_o.register_read = {1'b0, 1'b1}; end 
                                7'b11?????: begin vec_instr_o = VSETIVLI; x_issue_resp_o.accept = 1'b1; x_issue_resp_o.writeback = 1'b1; end                                
                                7'b1000000: begin vec_instr_o = VSETVL;   x_issue_resp_o.accept = 1'b1;
                                            if(!(instr_i[19:15] == '0) && !(instr_i[11:7] == '0))begin
                                                x_issue_resp_o.writeback = 1'b1;
                                            end 
                                            x_issue_resp_o.register_read = {1'b1, 1'b1}; end 
                                default: ;
                            endcase
                        end
                        default: ;
                    endcase
                end
        
                /////////////////////////////////////////////////////////
                // LOAD-FP encoding space, repurposed for vector loads //
                ////////////////////////////////////////////////////////
            
                OPCODE_LOAD: begin
                    if (!mew) begin

                        x_issue_resp_o.writeback = 1'b1;

                        unique case (mop)
                            2'b00: begin    // Unit-stride
                                x_issue_resp_o.register_read = {1'b0, 1'b1};
                                unique case (umop)
                                    5'b00000: begin // Normal unit-stride 
                                        unique case (width)     //Todo: make general vle. Then extract fields
                                            3'b000:  begin vec_instr_o = VLE8_V;  x_issue_resp_o.accept = 1'b1; end
                                            3'b101:  begin vec_instr_o = VLE16_V; x_issue_resp_o.accept = 1'b1; end
                                            3'b110:  begin vec_instr_o = VLE32_V; x_issue_resp_o.accept = 1'b1; end
                                            default: ;
                                        endcase
                                    end
                                    5'b01011: begin 
                                        if (vm) begin
                                            vec_instr_o = VLM_V;
                                            x_issue_resp_o.accept = 1'b1;                                                        //Unit-stride, mask-load EEW=8 
                                        end
                                    end
                                    5'b01000: begin // whole-register load
                                        if (vm) begin
                                            unique case (nf)    //Todo: make general vlXreX. Then extract fields
                                                3'b000: begin 
                                                    unique case (width)
                                                        3'b000:  begin vec_instr_o = VL1RE8_V;  x_issue_resp_o.accept = 1'b1; end
                                                        3'b101:  begin vec_instr_o = VL1RE16_V; x_issue_resp_o.accept = 1'b1; end
                                                        3'b110:  begin vec_instr_o = VL1RE32_V; x_issue_resp_o.accept = 1'b1; end
                                                        default: ;
                                                    endcase
                                                end 
                                                3'b001: begin
                                                    unique case (width)
                                                        3'b000:  begin vec_instr_o = VL2RE8_V;  x_issue_resp_o.accept = 1'b1; end
                                                        3'b101:  begin vec_instr_o = VL2RE16_V; x_issue_resp_o.accept = 1'b1; end
                                                        3'b110:  begin vec_instr_o = VL2RE32_V; x_issue_resp_o.accept = 1'b1; end
                                                        default: ;
                                                    endcase
                                                end
                                                3'b011: begin
                                                    unique case (width)
                                                        3'b000:  begin vec_instr_o = VL4RE8_V;  x_issue_resp_o.accept = 1'b1; end
                                                        3'b101:  begin vec_instr_o = VL4RE16_V; x_issue_resp_o.accept = 1'b1; end
                                                        3'b110:  begin vec_instr_o = VL4RE32_V; x_issue_resp_o.accept = 1'b1; end
                                                        default: ;
                                                    endcase
                                                end        
                                                3'b111: begin
                                                    unique case (width)
                                                        3'b000:  begin vec_instr_o = VL8RE8_V;  x_issue_resp_o.accept = 1'b1; end
                                                        3'b101:  begin vec_instr_o = VL8RE16_V; x_issue_resp_o.accept = 1'b1; end
                                                        3'b110:  begin vec_instr_o = VL8RE32_V; x_issue_resp_o.accept = 1'b1; end
                                                        default: ;
                                                    endcase
                                                end                           
                                                default: ;
                                            endcase
                                        end                                          
                                    end
                                    5'b10000: begin  // unit-stride fault-only-first
                                        unique case (width) //Todo: make general vleXff. Then extract fields
                                            3'b000:  begin vec_instr_o = VLE8FF_V;  x_issue_resp_o.accept = 1'b1; end
                                            3'b101:  begin vec_instr_o = VLE16FF_V; x_issue_resp_o.accept = 1'b1; end
                                            3'b110:  begin vec_instr_o = VLE32FF_V; x_issue_resp_o.accept = 1'b1; end
                                            default: ;
                                        endcase
                                    end  
                                    default: ;
                                endcase
                            end
            
                            // indexed-unordered
                            2'b01: begin
                                x_issue_resp_o.register_read = {1'b0, 1'b1};
                                unique case (width)             //Todo: make general vluxei. Then extract fields
                                    3'b000:  begin vec_instr_o = VLUXEI8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VLUXEI16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VLUXEI32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
                
                            // strided
                            2'b10: begin
                                x_issue_resp_o.register_read = {1'b1, 1'b1};
                                unique case (width)               //Todo: make general vlse. Then extract fields
                                    3'b000:  begin vec_instr_o = VLSE8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VLSE16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VLSE32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
                
                            // indexed-ordered
                            2'b11: begin
                                x_issue_resp_o.register_read = {1'b0, 1'b1};
                                unique case (width) //Todo: make general vloxei. Then extract fields
                                    3'b000:  begin vec_instr_o = VLOXEI8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VLOXEI16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VLOXEI32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
            
                            default: ;
                        endcase
                    end
                    
                end
        
                ///////////////////////////////////////////////////////////
                // STORE-FP encoding space, repurposed for vector stores //
                ///////////////////////////////////////////////////////////
                // Todo: nf?
                OPCODE_STORE: begin
                    if (!mew) begin

                        x_issue_resp_o.writeback = 1'b1;

                        unique case (mop)
                            2'b00: begin // unit-stride
                                x_issue_resp_o.register_read = {1'b0, 1'b1};
                                unique case (umop)
                                    5'b00000: begin 
                                        unique case (width) //Todo: make general vse. Then extract fields
                                            3'b000:  begin vec_instr_o = VSE8_V;  x_issue_resp_o.accept = 1'b1; end
                                            3'b101:  begin vec_instr_o = VSE16_V; x_issue_resp_o.accept = 1'b1; end
                                            3'b110:  begin vec_instr_o = VSE32_V; x_issue_resp_o.accept = 1'b1; end
                                            default: ;
                                        endcase
                                    end
                                    5'b01011: begin 
                                        if (vm) begin
                                            vec_instr_o = VSM_V;
                                            x_issue_resp_o.accept = 1'b1;
                                        end
                                    end
                                    5'b01000: begin // Todo: mew needs = 0?, 
                                        if (vm) begin
                                            unique case (nf)    //Todo: make general vsXr. Then extract fields
                                                3'b000: begin   vec_instr_o = VS1R_V; x_issue_resp_o.accept = 1'b1; end   
                                                3'b001: begin   vec_instr_o = VS2R_V; x_issue_resp_o.accept = 1'b1; end  
                                                3'b011: begin   vec_instr_o = VS4R_V; x_issue_resp_o.accept = 1'b1; end          
                                                3'b111: begin   vec_instr_o = VS8R_V; x_issue_resp_o.accept = 1'b1; end                             
                                                default: ;
                                            endcase
                                        end
                                    end
                                    default:  ;
                                endcase
                            end
            
                            2'b01: begin // indexed-unordered
                                x_issue_resp_o.register_read = {1'b0, 1'b1}; 
                                unique case (width)             //Todo: make general vsuxei. Then extract fields
                                    3'b000:  begin vec_instr_o = VSUXEI8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VSUXEI16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VSUXEI32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
            
                            2'b10: begin // strided
                                x_issue_resp_o.register_read = {1'b1, 1'b1}; 
                                unique case (width)             //Todo: make general vsseX. Then extract fields
                                    3'b000:  begin vec_instr_o = VSSE8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VSSE16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VSSE32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
            
                            2'b11: begin // indexed-ordered
                                x_issue_resp_o.register_read = {1'b0, 1'b1};
                                unique case (width)             //Todo: make general vsoxeiX. Then extract fields
                                    3'b000:  begin vec_instr_o = VSOXEI8_V;  x_issue_resp_o.accept = 1'b1; end
                                    3'b101:  begin vec_instr_o = VSOXEI16_V; x_issue_resp_o.accept = 1'b1; end
                                    3'b110:  begin vec_instr_o = VSOXEI32_V; x_issue_resp_o.accept = 1'b1; end
                                    default: ;
                                endcase
                            end
            
                            default: ;
                        endcase 
                    end
                end

                //////////////////////////////////
                // SYSTEM call for CSRs lecture //
                //////////////////////////////////
                
                OPCODE_SYSTEM: begin
                    unique case (fmt)
                        FMT_OPMVV_CSRRS: begin vec_instr_o = CSRRS; x_issue_resp_o.accept = 1'b1; x_issue_resp_o.writeback = 1'b1; end 
                        default:;
                    endcase
                end
            
                default: ; 
            endcase

            // Check address alignment
            if (x_issue_resp_o.accept) begin
                unique case (vec_instr_o)
                    // OPCODE_OP_V
                    ///////////////
                    // FMT_OPIVV //
                    ///////////////
                    VADD_VV, VSUB_VV,
                    VMINU_VV, VMIN_VV, VMAXU_VV, VMAX_VV,
                    VAND_VV, VOR_VV, VXOR_VV,
                    VRGATHER_VV, VRGATHEREI16_VV,
                    VSADDU_VV, VSADD_VV, VSSUBU_VV, VSSUB_VV,
                    VSMUL_VV,
                    VSLL_VV, VSRL_VV, VSRA_VV, VSSRL_VV, VSSRA_VV,
                    VADC_VVM, VMADC_VV, VSBC_VVM, VMSBC_VV,
                    //VMADC_VVM, VMSBC_VVM,  // Carry/borrow 
                    VMERGE_VVM: begin
                            uses_vd  = 1'b1;
                            uses_vs1 = 1'b1;
                            uses_vs2 = 1'b1;

                            emul_vd  = vtype_i.vlmul;
                            emul_vs1 = vtype_i.vlmul;
                            emul_vs2 = vtype_i.vlmul;
                    end
                    VMV_VV: begin
                            uses_vd  = 1'b1;
                            uses_vs1 = 1'b1;

                            emul_vd  = vtype_i.vlmul;
                            emul_vs1 = vtype_i.vlmul;
                    end
                    // Narrowing
                    VNSRL_WV, VNSRA_WV, VNCLIPU_WV, VNCLIP_WV: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_div2(vtype_i.vlmul, illegal_emul_vd);   
                        emul_vs1 = vtype_i.vlmul;
                        emul_vs2 = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                    end

                    // FMT_OPIVV. Mask producing
                    VMSEQ_VV, VMSNE_VV, VMSLTU_VV, VMSLT_VV, VMSLEU_VV, VMSLE_VV: begin
                            uses_vs1 = 1'b1;
                            uses_vs2 = 1'b1;

                            emul_vs1 = vtype_i.vlmul;
                            emul_vs2 = vtype_i.vlmul;
                    end
                    // Widening reductions
                    VWREDSUMU_VS, VWREDSUM_VS: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                        emul_vs1 = LMUL_1;
                        emul_vs2 = vtype_i.vlmul;
                    end

                    ///////////////
                    // FMT_OPIVX //
                    ///////////////
                    VADD_VX, VSUB_VX,
                    VRSUB_VX,
                    VMINU_VX,VMIN_VX,VMAXU_VX,VMAX_VX,
                    VAND_VX, VOR_VX, VXOR_VX,
                    VRGATHER_VX,
                    VSLIDEUP_VX, VSLIDEDOWN_VX,
                    VADC_VXM, VMADC_VX, VSBC_VXM, VMSBC_VX,  // Carry/borrow  TODO: emul? 
                    //VMADC_VXM, VMSBC_VXM,
                    VMERGE_VXM,
                    VSADDU_VX, VSADD_VX, VSSUBU_VX, VSSUB_VX,
                    VSMUL_VX,
                    VSLL_VX, VSRL_VX, VSRA_VX, VSSRL_VX, VSSRA_VX: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = vtype_i.vlmul;
                        emul_vs2 = vtype_i.vlmul;
                    end
                    VMV_VX: begin
                        uses_vd  = 1'b1;
                        emul_vd  = vtype_i.vlmul;
                    end

                    // Narrowing
                    VNSRL_WX, VNSRA_WX: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_div2(vtype_i.vlmul, illegal_emul_vd);    
                        emul_vs2 = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                    end
                    // VNCLIPU_WX
                    // VNCLIP_WX

                    // FMT_OPIVX. Mask producing
                    VMSEQ_VX, VMSNE_VX, VMSLTU_VX, VMSLT_VX, VMSLEU_VX, VMSLE_VX, VMSGTU_VX, VMSGT_VX: begin
                        uses_vs2 = 1'b1;
                        emul_vs2 = vtype_i.vlmul;
                    end

                    /////////////////////
                    // FMT_OPIVI_CSRRC //
                    /////////////////////
                    VADD_VI, VRSUB_VI,
                    VAND_VI, VOR_VI, VXOR_VI,
                    VRGATHER_VI, VSLIDEUP_VI, VSLIDEDOWN_VI,
                    VADC_VIM, VMADC_VI,      // Carry/borrow  
                    // VMADC_VIM 
                    VMERGE_VIM, 
                    VSADDU_VI, VSADD_VI,
                    VSLL_VI, VSRL_VI, VSRA_VI, VSSRL_VI, VSSRA_VI: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = vtype_i.vlmul;
                        emul_vs2 = vtype_i.vlmul;
                    end 
                    VMV_VI: begin
                        uses_vd  = 1'b1;
                        emul_vd  = vtype_i.vlmul;
                    end
                    // vmv<nr>r.v: vd/vs2 aligned to nr (simm5[2:0] = nr-1), independent of LMUL
                    VMVNRR_V: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        unique case (instr_i[17:15])
                            3'b001:  emul_vd = LMUL_2;
                            3'b011:  emul_vd = LMUL_4;
                            3'b111:  emul_vd = LMUL_8;
                            default: emul_vd = LMUL_1;
                        endcase
                        emul_vs2 = emul_vd;
                    end
                    // Narrowing
                    VNSRL_WI, VNSRA_WI, VNCLIPU_WI, VNCLIP_WI: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b0;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_div2(vtype_i.vlmul, illegal_emul_vd);  
                        emul_vs2 = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                    end
                    // FMT_OPIVI_CSRRC. Mask producing
                    VMSEQ_VI, VMSNE_VI, VMSLEU_VI, VMSLE_VI, VMSGTU_VI, VMSGT_VI: begin
                        uses_vs2 = 1'b1;
                        emul_vs2 = vtype_i.vlmul;
                    end
                    
                    /////////////////////
                    // FMT_OPMVV_CSRRS //
                    /////////////////////
                    //Reductions
                    VREDSUM_VS, VREDAND_VS, VREDOR_VS, VREDXOR_VS,
                    VREDMINU_VS, VREDMIN_VS, VREDMAXU_VS, VREDMAX_VS: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd   = LMUL_1;
                        emul_vs1  = LMUL_1;
                        emul_vs2  = vtype_i.vlmul;
                    end
                    VAADDU_VV, VAADD_VV, VASUBU_VV, VASUB_VV,
                    VDIVU_VV, VDIV_VV,
                    VREMU_VV, VREM_VV,
                    VMULHU_VV, VMUL_VV, VMULHSU_VV, VMULH_VV,
                    VMACC_VV: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd   = vtype_i.vlmul;
                        emul_vs1  = vtype_i.vlmul;
                        emul_vs2  = vtype_i.vlmul;
                    end
                    VCOMPRESS_VM: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd   = vtype_i.vlmul;
                        emul_vs2  = vtype_i.vlmul;
                    end
                    // VMANDNOT_MM,VMAND_MM,VMOR_MM,VMXOR_MM,VMORNOT_MM,VMNAND_MM,VMNOR_MM,VMXNOR_MM 
                    // VMADD_VV
                    // VNMSUB_VV
                    // VNMSAC_VV

                    // Widening arithmetic
                    VWADDU_VV, VWADD_VV, VWSUBU_VV, VWSUB_VV,
                    VWMULU_VV, VWMULSU_VV, VWMUL_VV,
                    //Widening multiply-acc
                    VWMACCU_VV, VWMACC_VV, VWMACCSU_VV: begin   
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd   = lmul_x2(vtype_i.vlmul, illegal_emul_vd);
                        emul_vs1  = vtype_i.vlmul;
                        emul_vs2  = vtype_i.vlmul;
                    end

                    // Widening add/sub
                    VWADDU_WV, VWADD_WV, VWSUBU_WV, VWSUB_WV: begin
                        uses_vd  = 1'b1;
                        uses_vs1 = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_x2(vtype_i.vlmul, illegal_emul_vd);
                        emul_vs1 = vtype_i.vlmul;
                        emul_vs2 = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                    end
                    // Unary operations
                    // VCPOP_M  // No need of reg check
                    // VFIRST_M // No need of reg check
                    VID_V: begin
                        uses_vd  = 1'b1;
                        emul_vd   = vtype_i.vlmul;    
                    end
                    VMV_XS,
                    VMSBF_M, VMSOF_M, VMSIF_M: begin
                        uses_vs2 = 1'b1;
                        emul_vs2 = vtype_i.vlmul;
                    end
                    VIOTA_M: begin
                        uses_vd  = 1'b1;
                        emul_vd  = vtype_i.vlmul; 
                    end 
                    // VZEXT_VF8
                    // VSEXT_VF8
                    // VZEXT_VF4
                    // VSEXT_VF4
                    // VZEXT_VF2
                    // VSEXT_VF2
                        // These are special fixed-ratio operations. Their source and destination EMULs are not both simply vtype_i.vlmul.
                        // The ratio is:
                        // vf2: source EMUL = destination EMUL / 2
                        // vf4: source EMUL = destination EMUL / 4
                        // vf8: source EMUL = destination EMUL / 8
                        // vf2: source EMUL = destination EMUL / 2vf4: source EMUL = destination EMUL / 4vf8: source EMUL = destination EMUL / 8
                        // The exact legal starting LMUL/EMUL combinations should be checked against the RVV widening/narrowing rules before implementing these cases.

                    //////////////////////
                    // FMT_OPMVX_CSRRSI //
                    //////////////////////
                    VAADDU_VX, VAADD_VX, VASUBU_VX, VASUB_VX,
                    VDIVU_VX, VDIV_VX,
                    VREMU_VX, VREM_VX,
                    VMULHU_VX, VMUL_VX, VMULHSU_VX, VMULH_VX,
                    VSLIDE1UP_VX, VSLIDE1DOWN_VX: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = vtype_i.vlmul;
                        emul_vs2 = vtype_i.vlmul;
                    end

                    // VMADD_VX,
                    // VNMSUB_VX,
                    // VMACC_VX,
                    // VNMSAC_VX,

                    // Widening arithmetic
                    VWADDU_VX, VWADD_VX, VWSUBU_VX, VWSUB_VX,
                    VWMULU_VX, VWMULSU_VX, VWMUL_VX,
                    // Widening multiply-acc
                    VWMACCU_VX, VWMACC_VX, VWMACCUS_VX, VWMACCSU_VX: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_x2(vtype_i.vlmul, illegal_emul_vd);
                        emul_vs2 = vtype_i.vlmul;
                    end
                    // Widening add/sub
                    VWADDU_WX, VWADD_WX, VWSUBU_WX, VWSUB_WX: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;

                        emul_vd  = lmul_x2(vtype_i.vlmul, illegal_emul_vd);
                        emul_vs2 = lmul_x2(vtype_i.vlmul, illegal_emul_vs2);
                    end
                    VMV_SX: begin
                        uses_vd  = 1'b1;
                        emul_vd = vtype_i.vlmul;
                    end 

                    // FMT_OPCFG_CSRRCI no check needed

                    /////////////////
                    // OPCODE_LOAD //
                    /////////////////
                    VLE8_V, VLE16_V, VLE32_V,
                    // VLM_V No alignment need
                    VLE8FF_V, VLE16FF_V, VLE32FF_V,
                    VLSE8_V, VLSE16_V, VLSE32_V: begin
                        uses_vd  = 1'b1;
                        emul_vd = get_emul(instr_i[14:12], vtype_i.vsew, vtype_i.vlmul, illegal_emul_vd);
                    end
                    VL1RE8_V, VL1RE16_V, VL1RE32_V: begin
                        uses_vd  = 1'b1;
                        emul_vd = LMUL_1;
                    end 
                    VL2RE8_V, VL2RE16_V, VL2RE32_V: begin
                        uses_vd  = 1'b1;
                        emul_vd = LMUL_2;
                    end
                    VL4RE8_V, VL4RE16_V, VL4RE32_V: begin
                        uses_vd  = 1'b1;
                        emul_vd = LMUL_4;
                    end
                    VL8RE8_V, VL8RE16_V, VL8RE32_V: begin
                        uses_vd  = 1'b1;
                        emul_vd = LMUL_8;
                    end
                    // Indexed
                    VLUXEI8_V, VLUXEI16_V, VLUXEI32_V,
                    VLOXEI8_V, VLOXEI16_V, VLOXEI32_V: begin
                        uses_vd  = 1'b1;
                        uses_vs2 = 1'b1;
                        emul_vd = get_emul(instr_i[14:12],vtype_i.vsew,vtype_i.vlmul,illegal_emul_vd);
                        emul_vs2 = vtype_i.vlmul;
                    end

                    //////////////////
                    // OPCODE_STORE //
                    //////////////////
                    VSE8_V, VSE16_V, VSE32_V,
                    VSSE8_V, VSSE16_V, VSSE32_V: begin 
                        uses_vs3 = 1'b1;
                        emul_vs3 = get_emul(instr_i[14:12],vtype_i.vsew,vtype_i.vlmul,illegal_emul_vs3);
                    end
                    // VSM_V no alignment check needed
                    VS1R_V: begin
                        uses_vs3 = 1'b1;
                        emul_vs3 = LMUL_1;
                    end
                    VS2R_V: begin
                        uses_vs3 = 1'b1;
                        emul_vs3 = LMUL_2;
                    end
                    VS4R_V: begin
                        uses_vs3 = 1'b1;
                        emul_vs3 = LMUL_4;
                    end
                    VS8R_V: begin
                        uses_vs3 = 1'b1;
                        emul_vs3 = LMUL_8;
                    end
                    VSUXEI8_V, VSUXEI16_V, VSUXEI32_V,
                    VSOXEI8_V, VSOXEI16_V, VSOXEI32_V: begin
                        uses_vs3 = 1'b1;
                        uses_vs2 = 1'b1;
                        emul_vs3 = vtype_i.vlmul;   // TODO: EMUL = LMUL for EEW = SEW
                        emul_vs2 = vtype_i.vlmul;
                    end

                    // OPCODE_SYSTEM no check needed
                    default: ; 
                endcase
            end

            illegal_align =
                (uses_vd  && is_misaligned(vd,  emul_vd))  ||
                (uses_vs1 && is_misaligned(vs1, emul_vs1)) ||
                (uses_vs2 && is_misaligned(vs2, emul_vs2)) ||
                (uses_vs3 && is_misaligned(vs3, emul_vs3)) ||
                illegal_emul_vd  ||
                illegal_emul_vs1 ||
                illegal_emul_vs2 || 
                illegal_emul_vs3;

            if (illegal_align) begin
                x_issue_resp_o.accept = 1'b0;
                x_issue_resp_o.writeback = 1'b0;
                x_issue_resp_o.register_read = '0;
                vec_instr_o           = INSTR_NONE;
            end
        end
        


    end: vproc_decoder
    
endmodule: vpu_xif_decoder