// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// Todo: 
//  - signed/operation assignation
//  - vop, vnop, vwop 


`include "utils_macros.svh"

module vpu_decoder 
import vpu_pkg::*;
import rvv_instr_pkg::*;
#(
    parameter int unsigned       NrRgprPorts                 = 2,
    parameter type               hartid_t                    = logic,
    parameter type               id_t                        = logic,
    // parameter type               x_issue_req_t               = logic,
    // parameter type               x_issue_resp_t              = logic,
    // parameter type               x_register_t                = logic,
    parameter type               registers_t                 = logic [NrRgprPorts-1:0][XLEN-1:0]
)(
    input  logic                clk_i,
    input  logic                buffer_req_valid_i,     
    input  buff_dec_t           buffer_req_i,
    input  hartid_t             hartid_i,
    input  id_t                 id_i,
    output logic                dec_resp_valid_o,
    output hartid_t             hartid_o,
    output id_t                 id_o,
    output vec_decoded_t        dec_req_o
);

  always_comb begin : decoder

    dec_req_o = '0; 
  
    if (buffer_req_valid_i) begin
        
        dec_req_o.instr_enum = buffer_req_i.instr_enum;

        dec_req_o.major_opcode  = major_opcode_e'(buffer_req_i.instr[6:0]);
        dec_req_o.fmt           = vec_funct3_e'(buffer_req_i.instr[14:12]);
        dec_req_o.vm            = buffer_req_i.instr[25];
        

        unique case (buffer_req_i.instr_enum)

            //////////
            // OP-V //
            //////////

            // -------------------------------------------------------
            // Integer arithmetic: add / sub / widening add-sub / carry
            // -------------------------------------------------------

            VADD_VV, VADD_VX, VADD_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VADD;
            end
            VSUB_VV, VSUB_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSUB;
            end
            VRSUB_VX, VRSUB_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VRSUB;
            end

            VWADDU_VV, VWADDU_VX, VWADDU_WV, VWADDU_WX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWADDU;
            end
            VWADD_VV, VWADD_VX, VWADD_WV, VWADD_WX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWADD;
            end
            VWSUBU_VV, VWSUBU_VX, VWSUBU_WV, VWSUBU_WX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWSUBU;
            end
            VWSUB_VV, VWSUB_VX, VWSUB_WV, VWSUB_WX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWSUB;
            end

            VADC_VVM, VADC_VXM, VADC_VIM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VADC;
            end
            VMADC_VVM, VMADC_VXM, VMADC_VIM,
            VMADC_VV,  VMADC_VX,  VMADC_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMADC;
            end
            VSBC_VVM, VSBC_VXM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSBC;
            end
            VMSBC_VVM, VMSBC_VXM, VMSBC_VV, VMSBC_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSBC;
            end

            // -------------------------------------------------------
            // Bitwise logical / shifts
            // -------------------------------------------------------
            VAND_VV, VAND_VX, VAND_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VAND;
            end
            VOR_VV, VOR_VX, VOR_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VOR;
            end
            VXOR_VV, VXOR_VX, VXOR_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VXOR;
            end
            VSLL_VV, VSLL_VX, VSLL_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSLL;
            end
            VSRL_VV, VSRL_VX, VSRL_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSRL;
            end
            VSRA_VV, VSRA_VX, VSRA_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSRA;
            end

            // Narrowing shifts
            VNSRL_WV, VNSRL_WX, VNSRL_WI: begin
                dec_req_o.is_arith      = 1'b1;
                dec_req_o.is_narrowing  = 1'b1;
                dec_req_o.operation     = OP_VNSRL;
            end
            VNSRA_WV, VNSRA_WX, VNSRA_WI: begin
                dec_req_o.is_arith      = 1'b1;
                dec_req_o.is_narrowing  = 1'b1;
                dec_req_o.operation     = OP_VNSRA;
            end          
            // -------------------------------------------------------
            // Integer compare / min-max
            // -------------------------------------------------------
            VMSEQ_VV, VMSEQ_VX, VMSEQ_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSEQ;
            end
            VMSNE_VV, VMSNE_VX, VMSNE_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSNE;
            end
            VMSLTU_VV, VMSLTU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSLTU;
            end
            VMSLT_VV, VMSLT_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSLT;
            end
            VMSLEU_VV, VMSLEU_VX, VMSLEU_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSLEU;
            end
            VMSLE_VV, VMSLE_VX, VMSLE_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSLE;
            end
            VMSGTU_VX, VMSGTU_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSGTU;
            end
            VMSGT_VX, VMSGT_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMSGT;
            end

            VMINU_VV, VMINU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMINU;
            end
            VMIN_VV, VMIN_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMIN;
            end
            VMAXU_VV, VMAXU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMAXU;
            end
            VMAX_VV, VMAX_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMAX;
            end

            // -------------------------------------------------------
            // Merge / move  // TODO: rethink architecture (VMERGE vs VMV)
            // -------------------------------------------------------
            VMERGE_VVM, VMERGE_VXM, VMERGE_VIM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMERGE;
            end
            VMV_VV, VMV_VX, VMV_VI: begin  
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMV;
            end
            VMV_XS: begin
                dec_req_o.operation = OP_VMV;
            end
            VMV_SX: begin
                dec_req_o.operation = OP_VMV;
            end
            VMVNRR_V: begin  
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMV;
            end

            // -------------------------------------------------------
            // Saturating / averaging / scaling-shift / narrowing-clip
            // -------------------------------------------------------
            VSADDU_VV, VSADDU_VX, VSADDU_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSADDU;
            end
            VSADD_VV, VSADD_VX, VSADD_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSADD;
            end
            VSSUBU_VV, VSSUBU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSSUBU;
            end
            VSSUB_VV, VSSUB_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSSUB;
            end
            VSMUL_VV, VSMUL_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_SMUL;
            end
            VAADDU_VV, VAADDU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VAADDU;
            end
            VAADD_VV, VAADD_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VAADD;
            end
            VASUBU_VV, VASUBU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VASUBU;
            end
            VASUB_VV, VASUB_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VASUB;
            end
            VSSRL_VV, VSSRL_VX, VSSRL_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSSRL;
            end
            VSSRA_VV, VSSRA_VX, VSSRA_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSSRA;
            end
            VNCLIPU_WV, VNCLIPU_WX, VNCLIPU_WI: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_narrowing = 1'b1;
                dec_req_o.operation    = OP_VNCLIPU;
            end
            VNCLIP_WV, VNCLIP_WX, VNCLIP_WI: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_narrowing = 1'b1;
                dec_req_o.operation    = OP_VNCLIP;
            end

            // -------------------------------------------------------
            // Gather / slide / compress
            // -------------------------------------------------------
            VRGATHER_VV, VRGATHER_VX, VRGATHER_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VRGATHER;
            end
            VRGATHEREI16_VV: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VRGATHEREI16;
            end
            VSLIDEUP_VX, VSLIDEUP_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSLIDEUP;
            end
            VSLIDEDOWN_VX, VSLIDEDOWN_VI: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSLIDEDOWN;
            end
            VSLIDE1UP_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSLIDE1UP;
            end
            VSLIDE1DOWN_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VSLIDE1DOWN;
            end
            VCOMPRESS_VM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VCOMPRESS;
            end

            // -------------------------------------------------------
            // Integer multiply / divide / macc
            // -------------------------------------------------------
            VMUL_VV, VMUL_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMUL;
            end
            VMULH_VV, VMULH_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMULH;
            end
            VMULHU_VV, VMULHU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMULHU;
            end
            VMULHSU_VV, VMULHSU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMULHSU;
            end
            VDIVU_VV, VDIVU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VDIVU;
            end
            VDIV_VV, VDIV_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VDIV;
            end
            VREMU_VV, VREMU_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VREMU;
            end
            VREM_VV, VREM_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VREM;
            end
            VMACC_VV, VMACC_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMACC;
            end
            VNMSAC_VV, VNMSAC_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VNMSAC;
            end
            VMADD_VV, VMADD_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMADD;
            end
            VNMSUB_VV, VNMSUB_VX: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VNMSUB;
            end

            // Widening multiply / macc
            VWMULU_VV, VWMULU_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMULU;
            end
            VWMUL_VV, VWMUL_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMUL;
            end
            VWMULSU_VV, VWMULSU_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMULSU;
            end
            VWMACCU_VV, VWMACCU_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMACCU;
            end
            VWMACC_VV, VWMACC_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMACC;
            end
            VWMACCSU_VV, VWMACCSU_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMACCSU;
            end
            VWMACCUS_VX: begin
                dec_req_o.is_arith    = 1'b1;
                dec_req_o.is_widening = 1'b1;
                dec_req_o.operation   = OP_VWMACCUS;
            end

            // -------------------------------------------------------
            // Reductions
            // -------------------------------------------------------
            VREDSUM_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDSUM;
            end
            VREDAND_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDAND;
            end
            VREDOR_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDOR;
            end
            VREDXOR_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDXOR;
            end
            VREDMINU_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDMINU;
            end
            VREDMIN_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDMIN;
            end
            VREDMAXU_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDMAXU;
            end
            VREDMAX_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VREDMAX;
            end
            VWREDSUMU_VS,
            VWREDSUM_VS: begin
                dec_req_o.is_arith     = 1'b1;
                dec_req_o.is_widening  = 1'b1;
                dec_req_o.is_reduction = 1'b1;
                dec_req_o.operation    = OP_VWREDSUM;
            end

            // -------------------------------------------------------
            // Mask-register logical
            // -------------------------------------------------------
            VMAND_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMAND;
            end
            VMNAND_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMNAND;
            end
            VMANDNOT_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMANDNOT;
            end
            VMOR_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMOR;
            end
            VMNOR_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMNOR;
            end
            VMORNOT_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMORNOT;
            end
            VMXOR_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMXOR;
            end
            VMXNOR_MM: begin
                dec_req_o.is_arith  = 1'b1;
                dec_req_o.operation = OP_VMXNOR;
            end

            // -------------------------------------------------------
            // Mask population / iota / element-index / first-set
            // -------------------------------------------------------
            VCPOP_M: begin
                dec_req_o.operation = OP_VCPOP;
            end
            VFIRST_M: begin
                dec_req_o.operation = OP_VFIRST;
            end
            VMSBF_M: begin
                // dec_req_o.uses_vs2  = 1'b1;
                // dec_req_o.uses_vs1  = 1'b1;
                dec_req_o.operation = OP_VMSBF;
            end
            VMSIF_M: begin
                // dec_req_o.uses_vs2  = 1'b1;
                // dec_req_o.uses_vs1  = 1'b1;
                dec_req_o.operation = OP_VMSIF;
            end
            VMSOF_M: begin
                // dec_req_o.uses_vs2  = 1'b1;
                // dec_req_o.uses_vs1  = 1'b1;
                dec_req_o.operation = OP_VMSOF;
            end
            VIOTA_M: begin
                // dec_req_o.uses_vs2  = 1'b1;
                // dec_req_o.uses_vs1  = 1'b1;
                dec_req_o.operation = OP_VIOTA;
            end
            VID_V: begin
                // dec_req_o.uses_vs2  = 1'b1;
                // dec_req_o.uses_vs1  = 1'b1;
                dec_req_o.operation = OP_VID;
            end

            // Zero / sign extend
            VZEXT_VF2, VZEXT_VF4, VZEXT_VF8: begin
                dec_req_o.operation = OP_ZEXT;
            end
            VSEXT_VF2, VSEXT_VF4, VSEXT_VF8: begin
                dec_req_o.operation = OP_SEXT;
            end

            // -------------------------------------------------------
            // Configuration  (CSR instructions handled separately)
            // -------------------------------------------------------
            VSETVLI, VSETIVLI, VSETVL: begin
                dec_req_o.operation = OP_VCFG;
            end

            /////////////
            // LOAD-FP //
            /////////////

            // Unit-stride
            VLE8_V, VLE16_V, VLE32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_VLE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            VLM_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_VLM;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            // Unit-stride fault-only-first
            VLE8FF_V, VLE16FF_V, VLE32FF_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_VLEFF;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            // Strided
            VLSE8_V, VLSE16_V, VLSE32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_VLSE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs2_data = buffer_req_i.registers[1];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            // Indexed (unordered + ordered share same op)
            VLUXEI8_V, VLUXEI16_V, VLUXEI32_V,
            VLOXEI8_V, VLOXEI16_V, VLOXEI32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_VLXE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.vs2      = buffer_req_i.instr[24:20];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end
            // Whole-register loads
            VL1RE8_V,  VL1RE16_V,  VL1RE32_V,
            VL2RE8_V,  VL2RE16_V,  VL2RE32_V,
            VL4RE8_V,  VL4RE16_V,  VL4RE32_V,
            VL8RE8_V,  VL8RE16_V,  VL8RE32_V: begin
                dec_req_o.is_load  = 1'b1;
                dec_req_o.operation = OP_LRE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vd       = buffer_req_i.instr[11:7];
            end

            //////////////
            // STORE-FP //
            //////////////

            // Unit-stride
            VSE8_V, VSE16_V, VSE32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.operation = OP_VSE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vs3      = buffer_req_i.instr[11:7];
            end
            // Strided
            VSSE8_V, VSSE16_V, VSSE32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.operation = OP_VSSE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs2_data = buffer_req_i.registers[1];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vs3      = buffer_req_i.instr[11:7];
            end
            // Indexed (unordered + ordered share same op)
            VSUXEI8_V, VSUXEI16_V, VSUXEI32_V,
            VSOXEI8_V, VSOXEI16_V, VSOXEI32_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.operation = OP_VSXE;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.vs2      = buffer_req_i.instr[24:20];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vs3      = buffer_req_i.instr[11:7];
            end
            // Whole-register stores
            VS1R_V, VS2R_V, VS4R_V, VS8R_V: begin
                dec_req_o.is_store = 1'b1;
                dec_req_o.operation = OP_VSR;
                // dec_req_o.nf       = buffer_req_i.instr[31:29];
                // dec_req_o.mew      = buffer_req_i.instr[28];
                // dec_req_o.mop      = buffer_req_i.instr[27:26];
                // dec_req_o.umop     = buffer_req_i.instr[24:20];
                // dec_req_o.width    = buffer_req_i.instr[14:12];
                // dec_req_o.rs1_data = buffer_req_i.registers[0];
                // dec_req_o.vs3      = buffer_req_i.instr[11:7];
            end

            default: ;           
        endcase
        
        if (dec_req_o.major_opcode == OPCODE_OP_V) begin     // is_arith
            unique case (dec_req_o.fmt)
            FMT_OPIVV, FMT_OPMVV_CSRRS: begin
                dec_req_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_req_o.vs2           = buffer_req_i.instr[24:20];          
                dec_req_o.vs1           = buffer_req_i.instr[19:15];                   
                dec_req_o.vd            = buffer_req_i.instr[11:7];
                dec_req_o.uses_vs1 = 1'b1;
                dec_req_o.uses_vs2 = 1'b1;
            end
            FMT_OPIVX, FMT_OPMVX_CSRRSI: begin
                dec_req_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_req_o.vs2           = buffer_req_i.instr[24:20];          
                dec_req_o.rs1_data      = buffer_req_i.registers[0];                   
                dec_req_o.vd            = buffer_req_i.instr[11:7];

                dec_req_o.uses_rs1_scalar = 1'b1;
                dec_req_o.uses_vs2        = 1'b1;
            end
            FMT_OPIVI_CSRRC: begin
                dec_req_o.funct6        = buffer_req_i.instr[31:26];                   
                dec_req_o.vs2           = buffer_req_i.instr[24:20];          
                dec_req_o.imm5          = buffer_req_i.instr[19:15];                   
                dec_req_o.vd            = buffer_req_i.instr[11:7];

                dec_req_o.uses_imm = 1'b1;
                dec_req_o.uses_vs2 = 1'b1;
            end
            FMT_OPCFG_CSRRCI: begin
                dec_req_o.uses_rs1_scalar = (dec_req_o.instr_enum == VSETVLI) || (dec_req_o.instr_enum == VSETVL);
                dec_req_o.uses_rs2_scalar = (dec_req_o.instr_enum == VSETVL);
            end
            default: ;
            endcase

            // multiply-accumulate style ops also read vd as a source operand
            dec_req_o.uses_vd_src |= dec_req_o.instr_enum inside {
            VMACC_VV, VMACC_VX, VNMSAC_VV, VNMSAC_VX,
            VWMACCU_VV, VWMACCU_VX, VWMACC_VV, VWMACC_VX
            };
        end
        else if (dec_req_o.major_opcode == OPCODE_STORE) begin                                      //is_store

            dec_req_o.nf              = buffer_req_i.instr[31:29];
            dec_req_o.mew             = buffer_req_i.instr[28];
            dec_req_o.mop             = buffer_req_i.instr[27:26];
            dec_req_o.umop            = buffer_req_i.instr[24:20]; 
            dec_req_o.width           = buffer_req_i.instr[14:12];
            dec_req_o.uses_rs1_scalar = 1'b1;                                                        // base address
            dec_req_o.rs1_data        = (dec_req_o.uses_rs1_scalar) ? buffer_req_i.registers[1] : 0;
            dec_req_o.uses_rs2_scalar = (dec_req_o.mop == 2'b10) ? 1'b1 : 1'b0;                      // stride
            dec_req_o.rs2_data        = (dec_req_o.uses_rs2_scalar) ? buffer_req_i.registers[0] : 0; 
            dec_req_o.vs3             = buffer_req_i.instr[11:7];
            
            dec_req_o.uses_vd_src     = 1'b1;                                                        // vs3 = store data, same field as vd
            dec_req_o.uses_vs2        = (dec_req_o.mop == 2'b01) || (dec_req_o.mop == 2'b11);        // index 
            
        end
        else if (dec_req_o.major_opcode == OPCODE_LOAD) begin                                        //is_load

            dec_req_o.nf              = buffer_req_i.instr[31:29];
            dec_req_o.mew             = buffer_req_i.instr[28];
            dec_req_o.mop             = buffer_req_i.instr[27:26];
            dec_req_o.umop            = buffer_req_i.instr[24:20]; 
            dec_req_o.width           = buffer_req_i.instr[14:12];
            dec_req_o.uses_rs1_scalar = (dec_req_o.umop !=  5'b0100) ? 1'b1 : 1'b0;                       // base address
            dec_req_o.rs1_data        = (dec_req_o.uses_rs1_scalar) ? buffer_req_i.registers[0] : 0; 
            dec_req_o.uses_rs2_scalar = (dec_req_o.mop == 2'b10) ? 1'b1 : 1'b0;                      // stride
            dec_req_o.rs2_data        = (dec_req_o.uses_rs2_scalar) ? buffer_req_i.registers[1] : 0;
            dec_req_o.uses_vs2        = (dec_req_o.mop == 2'b01) || (dec_req_o.mop == 2'b11);        // index  
            dec_req_o.vs3             = buffer_req_i.instr[11:7];
        end
    end
    
    dec_req_o.writeback = buffer_req_i.writeback;

  end : decoder

  assign dec_resp_valid_o = buffer_req_valid_i;
  assign hartid_o = hartid_i;
  assign id_o = id_i;

`ifndef SYNTHESIS
assert property (@(posedge clk_i) buffer_req_valid_i |->
    (dec_req_o.operation != OP_NONE || buffer_req_i.instr_enum == INSTR_NONE))
    else $error("Unrecognized instr_enum: %0d", buffer_req_i.instr_enum);
`endif
    
endmodule: vpu_decoder

