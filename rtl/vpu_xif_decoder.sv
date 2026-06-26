// Copyright 2024 CEIMM-UPM
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
//    That validity of instruction should condition xif_issue_resp.accept?
//  - Writeback: CSRs read instructions

module vpu_xif_decoder
import rvv_instr_pkg::*;
import vpu_pkg::*;
#(
    parameter type          readregflags_t   = logic
)(
    input  logic          issue_valid_i,
    input  logic [31:0]   instr_i,
    output logic          issue_ready_o,
    output logic          accept_o,         // Instruction recognized by VPU
    output logic          writeback_o,      
    output readregflags_t register_read_o, 
    output vec_instr_e    vec_instr_o
);
  
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

    always_comb begin: vproc_decoder
        major_opcode    = major_opcode_e'(instr_i[6:0]);
        fmt             = vec_funct3_e'(instr_i[14:12]);
        vm              = instr_i[25];
        funct6          = instr_i[31:26];
        nf              = instr_i[31:29];
        mew             = instr_i[28];
        mop             = instr_i[27:26];
        width           = instr_i[14:12];
        umop            = instr_i[24:20];
          
        vec_instr_o     = INSTR_NONE;
        accept_o        = 1'b0;
        writeback_o     = 1'b0;
        register_read_o = '0;
         
        unique case (major_opcode)
         
            //////////////////////////////////////////////////////////
            // OP-V : arithmetic / config / mask-logic / reductions //
            //////////////////////////////////////////////////////////
            OPCODE_OP_V: begin
                unique case (fmt)
    
                // Integer vector-vector
                FMT_OPIVV: begin
                    unique case (funct6)
                        6'b000000: begin vec_instr_o = VADD_VV;         accept_o = 1'b1; end    
                        6'b000010: begin vec_instr_o = VSUB_VV;         accept_o = 1'b1; end
                        6'b000100: begin vec_instr_o = VMINU_VV;        accept_o = 1'b1; end
                        6'b000101: begin vec_instr_o = VMIN_VV;         accept_o = 1'b1; end
                        6'b000110: begin vec_instr_o = VMAXU_VV;        accept_o = 1'b1; end
                        6'b000111: begin vec_instr_o = VMAX_VV;         accept_o = 1'b1; end
                        6'b001001: begin vec_instr_o = VAND_VV;         accept_o = 1'b1; end
                        6'b001010: begin vec_instr_o = VOR_VV;          accept_o = 1'b1; end
                        6'b001011: begin vec_instr_o = VXOR_VV;         accept_o = 1'b1; end
                        6'b001100: begin vec_instr_o = VRGATHER_VV;     accept_o = 1'b1; end
                        6'b001110: begin vec_instr_o = VRGATHEREI16_VV; accept_o = 1'b1; end 
                        6'b010000: begin vec_instr_o = VADC_VVM;        accept_o = (!vm) ? 1'b1 : 1'b0; end 
                        6'b010001: begin 
                            vec_instr_o = (vm) ? VMADC_VV : VMADC_VVM;                                          // vmadc.vvm / vmadc.vv (vm bit selects variant)
                            accept_o = 1'b1; 
                        end
                        6'b010010: begin vec_instr_o = VSBC_VVM;        accept_o = (!vm) ? 1'b1 : 1'b0;; end 
                        6'b010011: begin 
                            vec_instr_o = (vm) ? VMSBC_VV : VMSBC_VVM;
                            accept_o = 1'b1;
                        end
                        6'b010111: begin vec_instr_o = VMERGE_VVM;      accept_o = (!vm) ? 1'b1 : 1'b0; end      // vmerge.vvm (vm=0) / vmv.vv (vm=1, vs2=v0) // TODO: vmv? vmerge (0), vmv (1)
                        6'b011000: begin vec_instr_o = VMSEQ_VV;        accept_o = 1'b1; end
                        6'b011001: begin vec_instr_o = VMSNE_VV;        accept_o = 1'b1; end
                        6'b011010: begin vec_instr_o = VMSLTU_VV;       accept_o = 1'b1; end
                        6'b011011: begin vec_instr_o = VMSLT_VV;        accept_o = 1'b1; end
                        6'b011100: begin vec_instr_o = VMSLEU_VV;       accept_o = 1'b1; end
                        6'b011101: begin vec_instr_o = VMSLE_VV;        accept_o = 1'b1; end
                        6'b100000: begin vec_instr_o = VSADDU_VV;       accept_o = 1'b1; end
                        6'b100001: begin vec_instr_o = VSADD_VV;        accept_o = 1'b1; end
                        6'b100010: begin vec_instr_o = VSSUBU_VV;       accept_o = 1'b1; end
                        6'b100011: begin vec_instr_o = VSSUB_VV;        accept_o = 1'b1; end
                        6'b100101: begin vec_instr_o = VSLL_VV;         accept_o = 1'b1; end
                        6'b100111: begin vec_instr_o = VSMUL_VV;        accept_o = 1'b1; end 
                        6'b101000: begin vec_instr_o = VSRL_VV;         accept_o = 1'b1; end
                        6'b101001: begin vec_instr_o = VSRA_VV;         accept_o = 1'b1; end
                        6'b101010: begin vec_instr_o = VSSRL_VV;        accept_o = 1'b1; end
                        6'b101011: begin vec_instr_o = VSSRA_VV;        accept_o = 1'b1; end
                        6'b101100: begin vec_instr_o = VNSRL_WV;        accept_o = 1'b1; end 
                        6'b101101: begin vec_instr_o = VNSRA_WV;        accept_o = 1'b1; end
                        6'b101110: begin vec_instr_o = VNCLIPU_WV;      accept_o = 1'b1; end
                        6'b101111: begin vec_instr_o = VNCLIP_WV;       accept_o = 1'b1; end
                        6'b110000: begin vec_instr_o = VWREDSUMU_VS;    accept_o = 1'b1; end 
                        6'b110001: begin vec_instr_o = VWREDSUM_VS;     accept_o = 1'b1; end
                        default:   ; 
                    endcase
                end
        
                // Integer vector-scalar (rs1)
                FMT_OPIVX: begin
                    register_read_o = {1'b0, 1'b1};
                    unique case (funct6)
                        6'b000000: begin vec_instr_o = VADD_VX;       accept_o = 1'b1; end
                        6'b000010: begin vec_instr_o = VSUB_VX;       accept_o = 1'b1; end
                        6'b000011: begin vec_instr_o = VRSUB_VX;      accept_o = 1'b1; end
                        6'b000100: begin vec_instr_o = VMINU_VX;      accept_o = 1'b1; end
                        6'b000101: begin vec_instr_o = VMIN_VX;       accept_o = 1'b1; end
                        6'b000110: begin vec_instr_o = VMAXU_VX;      accept_o = 1'b1; end
                        6'b000111: begin vec_instr_o = VMAX_VX;       accept_o = 1'b1; end
                        6'b001001: begin vec_instr_o = VAND_VX;       accept_o = 1'b1; end
                        6'b001010: begin vec_instr_o = VOR_VX;        accept_o = 1'b1; end
                        6'b001011: begin vec_instr_o = VXOR_VX;       accept_o = 1'b1; end
                        6'b001100: begin vec_instr_o = VRGATHER_VX;   accept_o = 1'b1; end
                        6'b001110: begin vec_instr_o = VSLIDEUP_VX;   accept_o = 1'b1; end
                        6'b001111: begin vec_instr_o = VSLIDEDOWN_VX; accept_o = 1'b1; end
                        6'b010000: begin vec_instr_o = VADC_VXM;      accept_o = (!vm) ? 1'b1 : 1'b0; end
                        6'b010001: begin 
                            vec_instr_o = (vm) ? VMADC_VX : VMADC_VXM;               // vm selects vmadc.vxm vs vmadc.vx
                            accept_o = 1'b1;
                        end 
                        6'b010010: begin vec_instr_o = VSBC_VXM;      accept_o = (!vm) ? 1'b1 : 1'b0; end
                        6'b010011: begin 
                            vec_instr_o = (vm) ? VMSBC_VX : VMSBC_VXM;
                            accept_o = 1'b1;
                        end
                        6'b010111: begin vec_instr_o = VMERGE_VXM;    accept_o = (!vm) ? 1'b1 : 1'b0; end // vm=0: vmerge, vm=1: //todo: vmv.vx?
                        6'b011000: begin vec_instr_o = VMSEQ_VX;      accept_o = 1'b1; end
                        6'b011001: begin vec_instr_o = VMSNE_VX;      accept_o = 1'b1; end
                        6'b011010: begin vec_instr_o = VMSLTU_VX;     accept_o = 1'b1; end
                        6'b011011: begin vec_instr_o = VMSLT_VX;      accept_o = 1'b1; end
                        6'b011100: begin vec_instr_o = VMSLEU_VX;     accept_o = 1'b1; end
                        6'b011101: begin vec_instr_o = VMSLE_VX;      accept_o = 1'b1; end
                        6'b011110: begin vec_instr_o = VMSGTU_VX;     accept_o = 1'b1; end
                        6'b011111: begin vec_instr_o = VMSGT_VX;      accept_o = 1'b1; end
                        6'b100000: begin vec_instr_o = VSADDU_VX;     accept_o = 1'b1; end
                        6'b100001: begin vec_instr_o = VSADD_VX;      accept_o = 1'b1; end
                        6'b100010: begin vec_instr_o = VSSUBU_VX;     accept_o = 1'b1; end
                        6'b100011: begin vec_instr_o = VSSUB_VX;      accept_o = 1'b1; end
                        6'b100101: begin vec_instr_o = VSLL_VX;       accept_o = 1'b1; end
                        6'b100111: begin vec_instr_o = VSMUL_VX;      accept_o = 1'b1; end
                        6'b101000: begin vec_instr_o = VSRL_VX;       accept_o = 1'b1; end
                        6'b101001: begin vec_instr_o = VSRA_VX;       accept_o = 1'b1; end
                        6'b101010: begin vec_instr_o = VSSRL_VX;      accept_o = 1'b1; end
                        6'b101011: begin vec_instr_o = VSSRA_VX;      accept_o = 1'b1; end
                        6'b101100: begin vec_instr_o = VNSRL_WX;      accept_o = 1'b1; end
                        6'b101101: begin vec_instr_o = VNSRA_WX;      accept_o = 1'b1; end
                        6'b101110: begin vec_instr_o = VNCLIPU_WX;    accept_o = 1'b1; end
                        6'b101111: begin vec_instr_o = VNCLIP_WX;     accept_o = 1'b1; end
                    default:   ;
                    endcase
                end
        
                // Integer vector-immediate
                FMT_OPIVI_CSRRC: begin
                    unique case (funct6)
                        6'b000000: begin vec_instr_o = VADD_VI;         accept_o = 1'b1; end
                        6'b000011: begin vec_instr_o = VRSUB_VI;        accept_o = 1'b1; end
                        6'b001001: begin vec_instr_o = VAND_VI;         accept_o = 1'b1; end
                        6'b001010: begin vec_instr_o = VOR_VI;          accept_o = 1'b1; end
                        6'b001011: begin vec_instr_o = VXOR_VI;         accept_o = 1'b1; end
                        6'b001100: begin vec_instr_o = VRGATHER_VI;     accept_o = 1'b1; end
                        6'b001110: begin vec_instr_o = VSLIDEUP_VI;     accept_o = 1'b1; end
                        6'b001111: begin vec_instr_o = VSLIDEDOWN_VI;   accept_o = 1'b1; end
                        6'b010000: begin vec_instr_o = VADC_VIM;        accept_o = (!vm) ? 1'b1 : 1'b0; end
                        6'b010001: begin
                            vec_instr_o = (vm) ? VMADC_VI : VMADC_VIM;  
                            accept_o = 1'b1;
                        end 
                        6'b010111: begin vec_instr_o = VMERGE_VIM;      accept_o = (!vm) ? 1'b1 : 1'b0; end // vm=0: vmerge, vm=1: // TODO: vmv.vi?
                        6'b011000: begin vec_instr_o = VMSEQ_VI;        accept_o = 1'b1; end
                        6'b011001: begin vec_instr_o = VMSNE_VI;        accept_o = 1'b1; end
                        6'b011100: begin vec_instr_o = VMSLEU_VI;       accept_o = 1'b1; end
                        6'b011101: begin vec_instr_o = VMSLE_VI;        accept_o = 1'b1; end
                        6'b011110: begin vec_instr_o = VMSGTU_VI;       accept_o = 1'b1; end
                        6'b011111: begin vec_instr_o = VMSGT_VI;        accept_o = 1'b1; end
                        6'b100000: begin vec_instr_o = VSADDU_VI;       accept_o = 1'b1; end
                        6'b100001: begin vec_instr_o = VSADD_VI;        accept_o = 1'b1; end
                        6'b100101: begin vec_instr_o = VSLL_VI;         accept_o = 1'b1; end
                        6'b101000: begin vec_instr_o = VSRL_VI;         accept_o = 1'b1; end
                        6'b101001: begin vec_instr_o = VSRA_VI;         accept_o = 1'b1; end
                        6'b101010: begin vec_instr_o = VSSRL_VI;        accept_o = 1'b1; end
                        6'b101011: begin vec_instr_o = VSSRA_VI;        accept_o = 1'b1; end
                        6'b101100: begin vec_instr_o = VNSRL_WI;        accept_o = 1'b1; end
                        6'b101101: begin vec_instr_o = VNSRA_WI;        accept_o = 1'b1; end
                        6'b101110: begin vec_instr_o = VNCLIPU_WI;      accept_o = 1'b1; end
                        6'b101111: begin vec_instr_o = VNCLIP_WI;       accept_o = 1'b1; end
                        // vmv<nr>r.v: funct6 = 100111, vm=1, vs2=v0, simm5 encodes nr-1 (0→1reg, 1→2reg, 3→4reg, 7→8reg)
                        // These share funct6=100111 with vsmul but vm=1 AND funct3=OPIVI distinguishes them unambiguously
                        // Zve32x only requires vmv1r; add vmv2r/vmv4r/vmv8r if your implementation supports them.
                        6'b100111: begin
                            vec_instr_o = VMVNRR_V;
                            case ({instr_i[17:15], vm})
                                4'b0001, 4'b0011, 4'b0111, 4'b1111: accept_o = 1'b1;
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
                        6'b000000: begin vec_instr_o = VREDSUM_VS;   accept_o = 1'b1; end
                        6'b000001: begin vec_instr_o = VREDAND_VS;   accept_o = 1'b1; end
                        6'b000010: begin vec_instr_o = VREDOR_VS;    accept_o = 1'b1; end
                        6'b000011: begin vec_instr_o = VREDXOR_VS;   accept_o = 1'b1; end
                        6'b000100: begin vec_instr_o = VREDMINU_VS;  accept_o = 1'b1; end
                        6'b000101: begin vec_instr_o = VREDMIN_VS;   accept_o = 1'b1; end
                        6'b000110: begin vec_instr_o = VREDMAXU_VS;  accept_o = 1'b1; end
                        6'b000111: begin vec_instr_o = VREDMAX_VS;   accept_o = 1'b1; end
                        6'b001000: begin vec_instr_o = VAADDU_VV;    accept_o = 1'b1; end
                        6'b001001: begin vec_instr_o = VAADD_VV;     accept_o = 1'b1; end
                        6'b001010: begin vec_instr_o = VASUBU_VV;    accept_o = 1'b1; end
                        6'b001011: begin vec_instr_o = VASUB_VV;     accept_o = 1'b1; end
                        6'b010111: begin vec_instr_o = VCOMPRESS_VM; accept_o = (vm) ? 1'b1 : 1'b0; end
                        6'b011000: begin vec_instr_o = VMANDNOT_MM;  accept_o = 1'b1; end      // Todo: change mneumonics? mask-register logical (vs1/vs2 are mask registers, vm field ignored)
                        6'b011001: begin vec_instr_o = VMAND_MM;     accept_o = 1'b1; end
                        6'b011010: begin vec_instr_o = VMOR_MM;      accept_o = 1'b1; end
                        6'b011011: begin vec_instr_o = VMXOR_MM;     accept_o = 1'b1; end
                        6'b011100: begin vec_instr_o = VMORNOT_MM;   accept_o = 1'b1; end
                        6'b011101: begin vec_instr_o = VMNAND_MM;    accept_o = 1'b1; end
                        6'b011110: begin vec_instr_o = VMNOR_MM;     accept_o = 1'b1; end
                        6'b011111: begin vec_instr_o = VMXNOR_MM;    accept_o = 1'b1; end
                        6'b100000: begin vec_instr_o = VDIVU_VV;     accept_o = 1'b1; end
                        6'b100001: begin vec_instr_o = VDIV_VV;      accept_o = 1'b1; end
                        6'b100010: begin vec_instr_o = VREMU_VV;     accept_o = 1'b1; end
                        6'b100011: begin vec_instr_o = VREM_VV;      accept_o = 1'b1; end 
                        6'b100100: begin vec_instr_o = VMULHU_VV;    accept_o = 1'b1; end
                        6'b100101: begin vec_instr_o = VMUL_VV;      accept_o = 1'b1; end
                        6'b100110: begin vec_instr_o = VMULHSU_VV;   accept_o = 1'b1; end
                        6'b100111: begin vec_instr_o = VMULH_VV;     accept_o = 1'b1; end
                        6'b101001: begin vec_instr_o = VMADD_VV;     accept_o = 1'b1; end 
                        6'b101011: begin vec_instr_o = VNMSUB_VV;    accept_o = 1'b1; end 
                        6'b101101: begin vec_instr_o = VMACC_VV;     accept_o = 1'b1; end
                        6'b101111: begin vec_instr_o = VNMSAC_VV;    accept_o = 1'b1; end
                        6'b110000: begin vec_instr_o = VWADDU_VV;    accept_o = 1'b1; end
                        6'b110001: begin vec_instr_o = VWADD_VV;     accept_o = 1'b1; end
                        6'b110010: begin vec_instr_o = VWSUBU_VV;    accept_o = 1'b1; end
                        6'b110011: begin vec_instr_o = VWSUB_VV;     accept_o = 1'b1; end
                        6'b110100: begin vec_instr_o = VWADDU_WV;    accept_o = 1'b1; end
                        6'b110101: begin vec_instr_o = VWADD_WV;     accept_o = 1'b1; end
                        6'b110110: begin vec_instr_o = VWSUBU_WV;    accept_o = 1'b1; end
                        6'b110111: begin vec_instr_o = VWSUB_WV;     accept_o = 1'b1; end
                        6'b111000: begin vec_instr_o = VWMULU_VV;    accept_o = 1'b1; end
                        6'b111010: begin vec_instr_o = VWMULSU_VV;   accept_o = 1'b1; end
                        6'b111011: begin vec_instr_o = VWMUL_VV;     accept_o = 1'b1; end
                        6'b111100: begin vec_instr_o = VWMACCU_VV;   accept_o = 1'b1; end
                        6'b111101: begin vec_instr_o = VWMACC_VV;    accept_o = 1'b1; end
                        6'b111111: begin vec_instr_o = VWMACCSU_VV;  accept_o = 1'b1; end
                        6'b010000: begin // VWXUNARY0   // Todo: register read?
                            unique case (instr_i[19:15]) // vs1
                                5'b00000: begin 
                                    vec_instr_o = VMV_XS;
                                    accept_o = (vm) ? 1'b1 : 1'b0;
                                    writeback_o = 1'b1; end 
                                5'b10000: begin vec_instr_o = VCPOP_M;  accept_o = 1'b1; writeback_o = 1'b1; end // Old vpopc.m
                                5'b10001: begin vec_instr_o = VFIRST_M; accept_o = 1'b1; writeback_o = 1'b1; end 
                                default:  ;
                            endcase
                        end
    
                        6'b010010: begin // VXUNARY0    // Todo: register read? unify operation?
                            unique case (instr_i[19:15]) // vs1
                                5'b00010: begin vec_instr_o = VZEXT_VF8;  accept_o = 1'b1; end 
                                5'b00011: begin vec_instr_o = VSEXT_VF8;  accept_o = 1'b1; end 
                                5'b00100: begin vec_instr_o = VZEXT_VF4;  accept_o = 1'b1; end 
                                5'b00101: begin vec_instr_o = VSEXT_VF4;  accept_o = 1'b1; end 
                                5'b00110: begin vec_instr_o = VZEXT_VF2;  accept_o = 1'b1; end 
                                5'b00111: begin vec_instr_o = VSEXT_VF2;  accept_o = 1'b1; end 
                                default:  ;
                            endcase
                        end
    
                        6'b010100: begin // VMUNARY0     // Todo: register read?
                            unique case (instr_i[19:15]) // vs1
                                5'b00001: begin vec_instr_o = VMSBF_M;  accept_o = 1'b1; end 
                                5'b00010: begin vec_instr_o = VMSOF_M;  accept_o = 1'b1; end 
                                5'b00011: begin vec_instr_o = VMSIF_M;  accept_o = 1'b1; end 
                                5'b10000: begin vec_instr_o = VIOTA_M;  accept_o = 1'b1; end 
                                5'b10001: begin vec_instr_o = VID_V;    accept_o = 1'b1; end 
                                default:  ;
                            endcase
                        end
                    default:   ;
                    endcase
                end
        
                // Mask/multiply vector-scalar (rs1)
                FMT_OPMVX_CSRRSI: begin
                    register_read_o = {1'b0, 1'b1};
                    unique case (funct6)
                        6'b001000: begin vec_instr_o = VAADDU_VX;      accept_o = 1'b1; end
                        6'b001001: begin vec_instr_o = VAADD_VX;       accept_o = 1'b1; end
                        6'b001010: begin vec_instr_o = VASUBU_VX;      accept_o = 1'b1; end
                        6'b001011: begin vec_instr_o = VASUB_VX;       accept_o = 1'b1; end
                        6'b001110: begin vec_instr_o = VSLIDE1UP_VX;   accept_o = 1'b1; end
                        6'b001111: begin vec_instr_o = VSLIDE1DOWN_VX; accept_o = 1'b1; end
                        6'b100000: begin vec_instr_o = VDIVU_VX;       accept_o = 1'b1; end
                        6'b100001: begin vec_instr_o = VDIV_VX;        accept_o = 1'b1; end
                        6'b100010: begin vec_instr_o = VREMU_VX;       accept_o = 1'b1; end
                        6'b100011: begin vec_instr_o = VREM_VX;        accept_o = 1'b1; end
                        6'b100100: begin vec_instr_o = VMULHU_VX;      accept_o = 1'b1; end               
                        6'b100101: begin vec_instr_o = VMUL_VX;        accept_o = 1'b1; end
                        6'b100110: begin vec_instr_o = VMULHSU_VX;     accept_o = 1'b1; end
                        6'b100111: begin vec_instr_o = VMULH_VX;       accept_o = 1'b1; end
                        6'b101001: begin vec_instr_o = VMADD_VX;       accept_o = 1'b1; end
                        6'b101011: begin vec_instr_o = VNMSUB_VX;      accept_o = 1'b1; end
                        6'b101101: begin vec_instr_o = VMACC_VX;       accept_o = 1'b1; end
                        6'b101111: begin vec_instr_o = VNMSAC_VX;      accept_o = 1'b1; end
                        6'b110000: begin vec_instr_o = VWADDU_VX;      accept_o = 1'b1; end
                        6'b110001: begin vec_instr_o = VWADD_VX;       accept_o = 1'b1; end
                        6'b110010: begin vec_instr_o = VWSUBU_VX;      accept_o = 1'b1; end
                        6'b110011: begin vec_instr_o = VWSUB_VX;       accept_o = 1'b1; end
                        6'b110100: begin vec_instr_o = VWADDU_WX;      accept_o = 1'b1; end
                        6'b110101: begin vec_instr_o = VWADD_WX;       accept_o = 1'b1; end
                        6'b110110: begin vec_instr_o = VWSUBU_WX;      accept_o = 1'b1; end
                        6'b110111: begin vec_instr_o = VWSUB_WX;       accept_o = 1'b1; end
                        6'b111000: begin vec_instr_o = VWMULU_VX;      accept_o = 1'b1; end
                        6'b111010: begin vec_instr_o = VWMULSU_VX;     accept_o = 1'b1; end          
                        6'b111011: begin vec_instr_o = VWMUL_VX;       accept_o = 1'b1; end
                        6'b111100: begin vec_instr_o = VWMACCU_VX;     accept_o = 1'b1; end
                        6'b111101: begin vec_instr_o = VWMACC_VX;      accept_o = 1'b1; end
                        6'b111110: begin vec_instr_o = VWMACCUS_VX;    accept_o = 1'b1; end
                        6'b111111: begin vec_instr_o = VWMACCSU_VX;    accept_o = 1'b1; end
                        6'b010000: begin // VRXUNARY0
                            unique case (instr_i[24:20]) // vs2
                                5'b00000: begin vec_instr_o = VMV_SX; accept_o = (vm) ? 1'b1 : 1'b0; end 
                                default:  ;
                            endcase
                            end
                        default:   ;
                    endcase
                end
        
                // Vector configuration: vsetvli / vsetivli / vsetvl
                FMT_OPCFG_CSRRCI: begin
                    unique casez (instr_i[31:25])
                        7'b0??????: begin vec_instr_o = VSETVLI;  accept_o = 1'b1; writeback_o = 1'b1; register_read_o = {1'b0, 1'b1}; end // TODO: vill
                        7'b11?????: begin vec_instr_o = VSETIVLI; accept_o = 1'b1; writeback_o = 1'b1; end                                // TODO: vill
                        7'b1000000: begin vec_instr_o = VSETVL;   accept_o = 1'b1; writeback_o = 1'b1; register_read_o = {1'b1, 1'b1}; end // TODO: vill
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
                    unique case (mop)
                        2'b00: begin    // Unit-stride
                            register_read_o = {1'b0, 1'b1};
                            unique case (umop)
                                5'b00000: begin // Normal unit-stride 
                                    unique case (width)     //Todo: make general vle. Then extract fields
                                        3'b000:  begin vec_instr_o = VLE8_V;  accept_o = 1'b1; end
                                        3'b101:  begin vec_instr_o = VLE16_V; accept_o = 1'b1; end
                                        3'b110:  begin vec_instr_o = VLE32_V; accept_o = 1'b1; end
                                        default: ;
                                    endcase
                                end
                                5'b01011: begin 
                                    if (vm) begin
                                        vec_instr_o = VLM_V;
                                        accept_o = 1'b1;                                                        //Unit-stride, mask-load EEW=8 
                                    end
                                end
                                5'b01000: begin // whole-register load
                                    if (vm) begin
                                        unique case (nf)    //Todo: make general vlXreX. Then extract fields
                                            3'b000: begin 
                                                unique case (width)
                                                    3'b000:  begin vec_instr_o = VL1RE8_V;  accept_o = 1'b1; end
                                                    3'b101:  begin vec_instr_o = VL1RE16_V; accept_o = 1'b1; end
                                                    3'b110:  begin vec_instr_o = VL1RE32_V; accept_o = 1'b1; end
                                                    default: ;
                                                endcase
                                            end 
                                            3'b001: begin
                                                unique case (width)
                                                    3'b000:  begin vec_instr_o = VL2RE8_V;  accept_o = 1'b1; end
                                                    3'b101:  begin vec_instr_o = VL2RE16_V; accept_o = 1'b1; end
                                                    3'b110:  begin vec_instr_o = VL2RE32_V; accept_o = 1'b1; end
                                                    default: ;
                                                endcase
                                            end
                                            3'b011: begin
                                                unique case (width)
                                                    3'b000:  begin vec_instr_o = VL4RE8_V;  accept_o = 1'b1; end
                                                    3'b101:  begin vec_instr_o = VL4RE16_V; accept_o = 1'b1; end
                                                    3'b110:  begin vec_instr_o = VL4RE32_V; accept_o = 1'b1; end
                                                    default: ;
                                                endcase
                                            end        
                                            3'b111: begin
                                                unique case (width)
                                                    3'b000:  begin vec_instr_o = VL8RE8_V;  accept_o = 1'b1; end
                                                    3'b101:  begin vec_instr_o = VL8RE16_V; accept_o = 1'b1; end
                                                    3'b110:  begin vec_instr_o = VL8RE32_V; accept_o = 1'b1; end
                                                    default: ;
                                                endcase
                                            end                           
                                            default: ;
                                        endcase
                                    end                                          
                                end
                                5'b10000: begin  // unit-stride fault-only-first
                                    unique case (width) //Todo: make general vleXff. Then extract fields
                                        3'b000:  begin vec_instr_o = VLE8FF_V;  accept_o = 1'b1; end
                                        3'b101:  begin vec_instr_o = VLE16FF_V; accept_o = 1'b1; end
                                        3'b110:  begin vec_instr_o = VLE32FF_V; accept_o = 1'b1; end
                                        default: ;
                                    endcase
                                end  
                                default: ;
                            endcase
                        end
        
                        // indexed-unordered
                        2'b01: begin
                            register_read_o = {1'b0, 1'b1};
                            unique case (width)             //Todo: make general vluxei. Then extract fields
                                3'b000:  begin vec_instr_o = VLUXEI8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VLUXEI16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VLUXEI32_V; accept_o = 1'b1; end
                                default: ;
                            endcase
                        end
            
                        // strided
                        2'b10: begin
                            register_read_o = {1'b1, 1'b1};
                            unique case (width)               //Todo: make general vlse. Then extract fields
                                3'b000:  begin vec_instr_o = VLSE8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VLSE16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VLSE32_V; accept_o = 1'b1; end
                                default: ;
                            endcase
                        end
            
                        // indexed-ordered
                        2'b11: begin
                            register_read_o = {1'b0, 1'b1};
                            unique case (width) //Todo: make general vloxei. Then extract fields
                                3'b000:  begin vec_instr_o = VLOXEI8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VLOXEI16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VLOXEI32_V; accept_o = 1'b1; end
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
                    unique case (mop)
                        2'b00: begin // unit-stride
                            register_read_o = {1'b0, 1'b1};
                            unique case (umop)
                                5'b00000: begin 
                                    unique case (width) //Todo: make general vse. Then extract fields
                                        3'b000:  begin vec_instr_o = VSE8_V;  accept_o = 1'b1; end
                                        3'b101:  begin vec_instr_o = VSE16_V; accept_o = 1'b1; end
                                        3'b110:  begin vec_instr_o = VSE32_V; accept_o = 1'b1; end
                                        default: ;
                                    endcase
                                end
                                5'b01011: begin 
                                    if (vm) begin
                                        vec_instr_o = VSM_V;
                                        accept_o = 1'b1;
                                    end
                                end
                                5'b01000: begin // Todo: mew needs = 0?, 
                                    if (vm) begin
                                        unique case (nf)    //Todo: make general vsXr. Then extract fields
                                            3'b000: begin   vec_instr_o = VS1R_V; accept_o = 1'b1; end   
                                            3'b001: begin   vec_instr_o = VS2R_V; accept_o = 1'b1; end  
                                            3'b011: begin   vec_instr_o = VS4R_V; accept_o = 1'b1; end          
                                            3'b111: begin   vec_instr_o = VS8R_V; accept_o = 1'b1; end                             
                                            default: ;
                                        endcase
                                    end
                                end
                                default:  ;
                            endcase
                        end
        
                        2'b01: begin // indexed-unordered
                            register_read_o = {1'b0, 1'b1}; 
                            unique case (width)             //Todo: make general vsuxei. Then extract fields
                                3'b000:  begin vec_instr_o = VSUXEI8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VSUXEI16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VSUXEI32_V; accept_o = 1'b1; end
                                default: ;
                            endcase
                        end
        
                        2'b10: begin // strided
                            register_read_o = {1'b1, 1'b1}; 
                            unique case (width)             //Todo: make general vsseX. Then extract fields
                                3'b000:  begin vec_instr_o = VSSE8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VSSE16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VSSE32_V; accept_o = 1'b1; end
                                default: ;
                            endcase
                        end
        
                        2'b11: begin // indexed-ordered
                            register_read_o = {1'b0, 1'b1};
                            unique case (width)             //Todo: make general vsoxeiX. Then extract fields
                                3'b000:  begin vec_instr_o = VSOXEI8_V;  accept_o = 1'b1; end
                                3'b101:  begin vec_instr_o = VSOXEI16_V; accept_o = 1'b1; end
                                3'b110:  begin vec_instr_o = VSOXEI32_V; accept_o = 1'b1; end
                                default: ;
                            endcase
                        end
        
                        default: ;
                    endcase 
                end
            end
          
            default: ; 
        endcase
    end: vproc_decoder
  
    assign issue_ready_o = issue_valid_i; // Todo: in case of VCF too?
  
endmodule: vpu_xif_decoder
  