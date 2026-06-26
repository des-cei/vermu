// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

`include "utils_macros.svh"

module vpu_decoder 
import vpu_pkg::*;
import rvv_instr_pkg::*;
#(
    // parameter int unsigned       NrRgprPorts                 = 2,
    parameter type               hartid_t                    = logic,
    parameter type               id_t                        = logic,
    // parameter type               x_issue_req_t               = logic,
    // parameter type               x_issue_resp_t              = logic,
    // parameter type               x_register_t                = logic,
    parameter type               registers_t                 = logic [NrRgprPorts-1:0][XLEN-1:0],
)(
    input  logic                buffer_req_valid_i,     
    input  buff_dec_t           buffer_req_i,
    input  hartid_t             hartid_i,
    input  id_t                 id_t,
    output logic                dec_resp_valid_o,
    output hartid_t             hartid_o,
    output id_t                 id_o,
    output vec_decoded_t        dec_req_o
);

  always_comb begin : decoder
    if (buffer_req_valid_i) begin
        
        dec_req_o.instr_enum = buffer_req_i.instr_enum

        dec_instr_o.major_opcode  = major_opcode_e'(buffer_req_i.instr[6:0]);
        dec_instr_o.fmt           = vec_funct3_e'(buffer_req_i.instr[14:12]);
        dec_instr_o.vm            = buffer_req_i.instr[25];
        
        unique case (buff_dec_i.instr_enum)

            //////////
            // OP-V //
            //////////

            //OPIVV
            VADD_VV,
            VSUB_VV,
            VMINU_VV,
            VMIN_VV,
            VMAXU_VV,
            VMAX_VV,
            VAND_VV,
            VOR_VV,
            VXOR_VV,
            VRGATHER_VV,
            VRGATHEREI16_VV,
            VADC_VVM,
            VMADC_VV,
            VMADC_VVM,
            VSBC_VVM,
            VMSBC_VV,
            VMSBC_VVM,
            VMERGE_VVM,
            VMSEQ_VV,
            VMSNE_VV,
            VMSLTU_VV,
            VMSLT_VV,
            VMSLEU_VV,
            VMSLE_VV,
            VSADDU_VV,
            VSADD_VV,
            VSSUBU_VV,
            VSSUB_VV,
            VSLL_VV,
            VSMUL_VV,
            VSRL_VV,
            VSRA_VV,
            VSSRL_VV,
            VSSRA_VV: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end
            VNSRL_WV,
            VNSRA_WV: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
                dec_Re
            end
            VNCLIPU_WV,
            VNCLIP_WV,
            VWREDSUMU_VS,
            VWREDSUM_VS: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end

            //OPIVX
            VADD_VX,
            VSUB_VX,
            VRSUB_VX,
            VMINU_VX,
            VMIN_VX,
            VMAXU_VX,
            VMAX_VX,
            VAND_VX,
            VOR_VX,
            VXOR_VX,
            VRGATHER_VX,
            VSLIDEUP_VX,
            VSLIDEDOWN_VX,
            VADC_VXM,
            VMADC_VX,
            VMADC_VXM,
            VSBC_VXM,
            VMSBC_VX,
            VMSBC_VXM,
            VMERGE_VXM,
            VMSEQ_VX,
            VMSNE_VX,
            VMSLTU_VX,
            VMSLT_VX,
            VMSLEU_VX,
            VMSLE_VX,
            VMSGTU_VX,
            VMSGT_VX,
            VSADDU_VX,
            VSADD_VX,
            VSSUBU_VX,
            VSSUB_VX,
            VSLL_VX,
            VSMUL_VX,
            VSRL_VX,
            VSRA_VX,
            VSSRL_VX,
            VSSRA_VX: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.rs1_data      = buffer_req_i.rs[0];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end
            VNSRL_WX,
            VNSRA_WX,
            VNCLIPU_WX,
            VNCLIP_WX: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.rs1_data      = buffer_req_i.rs[0];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end

            // OPIVI
            VADD_VI,
            VRSUB_VI,
            VAND_VI,
            VOR_VI,
            VXOR_VI,
            VRGATHER_VI,
            VSLIDEUP_VI,
            VSLIDEDOWN_VI,
            VADC_VIM,
            VMADC_VI,
            VMADC_VIM,
            VMERGE_VIM,
            VMSEQ_VI,
            VMSNE_VI,
            VMSLEU_VI,
            VMSLE_VI,
            VMSGTU_VI,
            VMSGT_VI,
            VSADDU_VI,
            VSADD_VI,
            VSLL_VI,
            VSRL_VI,
            VSRA_VI,
            VSSRL_VI,
            VSSRA_VI,
            VMVNRR_V: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.imm5          = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end
            VNSRL_WI,
            VNSRA_WI,
            VNCLIPU_WI,
            VNCLIP_WI: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.imm5          = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];
            end

            // OPMVV
            VREDSUM_VS,
            VREDAND_VS,
            VREDOR_VS,
            VREDXOR_VS,
            VREDMINU_VS,
            VREDMIN_VS,
            VREDMAXU_VS,
            VREDMAX_VS,
            VAADDU_VV,
            VAADD_VV,
            VASUBU_VV,
            VASUB_VV,
            VCOMPRESS_VM,
            VMANDNOT_MM,
            VMAND_MM,
            VMOR_MM,
            VMXOR_MM,
            VMORNOT_MM,
            VMNAND_MM,
            VMNOR_MM,
            VMXNOR_MM,
            VDIVU_VV,
            VDIV_VV,
            VREMU_VV,
            VREM_VV,
            VMULHU_VV,
            VMUL_VV,
            VMULHSU_VV,
            VMULH_VV,
            VMADD_VV,
            VNMSUB_VV,
            VMACC_VV,
            VNMSAC_VV,: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end 
            VWADDU_VV,
            VWADD_VV,
            VWSUBU_VV,
            VWSUB_VV,
            VWADDU_WV,
            VWADD_WV,
            VWSUBU_WV,
            VWSUB_WV,
            VWMULU_VV,
            VWMULSU_VV,
            VWMUL_VV,
            VWMACCU_VV,
            VWMACC_VV,
            VWMACCSU_VV: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end
            VMV_XS,
            VCPOP_M,
            VFIRST_M,
            VZEXT_VF8,
            VSEXT_VF8,
            VZEXT_VF4,
            VSEXT_VF4,
            VZEXT_VF2,
            VSEXT_VF2: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end
            VMSBF_M,
            VMSOF_M,
            VMSIF_M,
            VIOTA_M,
            VID_V: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end

            // OPMVX
            VAADDU_VX,
            VAADD_VX,
            VASUBU_VX,
            VASUB_VX,
            VSLIDE1UP_V,X
            VSLIDE1DOWN_VX,
            VDIVU_VX,
            VDIV_VX,
            VREMU_VX,
            VREM_VX,
            VMULHU_VX,
            VMUL_VX,
            VMULHSU_VX,
            VMULH_VX,
            VMADD_VX,
            VNMSUB_VX,
            VMACC_VX,
            VNMSAC_VX: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.rs1_data      = buffer_req_i.rs[0];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end
            VWADDU_VX,
            VWADD_VX,
            VWSUBU_VX,
            VWSUB_VX,
            VWADDU_WX,
            VWADD_WX,
            VWSUBU_WX,
            VWSUB_WX,
            VWMULU_VX,
            VWMULSU_VX,
            VWMUL_VX,
            VWMACCU_VX,
            VWMACC_VX,
            VWMACCUS_VX,
            VWMACCSU_VX: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.rs1_data      = buffer_req_i.rs[0];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?                
            end
            VMV_SX: begin
                dec_req_o.is_arih         = 1'b1; 
                dec_instr_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_instr_o.vs2           = buffer_req_i.instr[24:20];          
                dec_instr_o.rs1_data      = buffer_req_i.rs[0];                   
                dec_req_o.vd              = buffer_req_i.instr[11:7];   //rd?
            end

            //CSR instructions not included

            /////////////
            // LOAD-FP //
            /////////////

            VLE8_V ,
            VLE16_V,
            VLE32_V,
            VLM_V,
            VL1RE8_V,
            VL1RE16_V,
            VL1RE32_V,
            VL2RE8_V,
            VL2RE16_V,
            VL2RE32_V,
            VL4RE8_V,
            VL4RE16_V,
            VL4RE32_V,
            VL8RE8_V,
            VL8RE16_V,
            VL8RE32_V,
            VLE8FF_V,
            VLE16FF_V,
            VLE32FF_V: begin 
                dec_req_o.is_load  = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.umop     = buffer_req_i.instr[24:20];  
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vd       = buffer_req_i.instr[11:7];
            end

            VLUXEI8_V,
            VLUXEI16_V,
            VLUXEI32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.vs2     = buffer_req_i.instr[24:20];
                dec_req_o.rs1_data = buffer_req_i.rs[0];
                dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            VLSE8_V,
            VLSE16_V,
            VLSE32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.rs2_data = buffer_req_i.instr.rs[1];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            VLOXEI8_V,
            VLOXEI16_V,
            VLOXEI32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.vs2      = buffer_req_i.instr[24:20];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vd       = buffer_req_i.instr[11:7];
            end

            //////////////
            // STORE-FP //
            //////////////

            VSE8_V,
            VSE16_V,
            VSE32_V,
            VS1R_V,
            VS2R_V,
            VS4R_V,
            VS8R_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.umop     = buffer_req_i.instr[24:20];  
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vs3       = buffer_req_i.instr[11:7];
            end
            VSUXEI8_V,
            VSUXEI16_V, 
            VSUXEI32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.vs2      = buffer_req_i.instr[24:20];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vs3       = buffer_req_i.instr[11:7];
            end
            VSSE8_V,
            VSSE16_V,
            VSSE32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.rs2_data = buffer_req_i.instr.rs[1];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vs3       = buffer_req_i.instr[11:7];
            end
            VSOXEI8_V,
            VSOXEI16_V,
            VSOXEI32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.nf       = buffer_req_i.instr[31:29];
                dec_req_o.mew      = buffer_req_i.instr[28];
                dec_req_o.mop      = buffer_req_i.instr[27:26];
                dec_req_o.width    = buffer_req_i.instr[14:12];
                dec_req_o.vs2      = buffer_req_i.instr[24:20];
                dec_req_o.rs1_data = buffer_req_i.instr.rs[0];
                dec_req_o.vs3       = buffer_req_i.instr[11:7];
            end
            default: ; 
        endcase

    end

  end : decoder

  assign dec_resp_valid_o = buffer_req_valid_i;
  assign hartid_i = hartid_o;
  assign id_i = id_o;
    
endmodule: vpu_decoder

