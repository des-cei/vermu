// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)


package rvv_instr_pkg; 

    typedef enum logic [8:0] {   

        INSTR_NONE = '0,

        //  Integer arithmetic: OPIVV / OPIVX / OPIVI 
        VADD_VV,   VADD_VX,  VADD_VI,
        VSUB_VV,   VSUB_VX,
        VRSUB_VX,  VRSUB_VI,
        VAND_VV,   VAND_VX,   VAND_VI,
        VOR_VV,    VOR_VX,    VOR_VI,
        VXOR_VV,   VXOR_VX,   VXOR_VI,
        VSLL_VV,   VSLL_VX,   VSLL_VI,
        VSRL_VV,   VSRL_VX,   VSRL_VI,
        VSRA_VV,   VSRA_VX,   VSRA_VI,
        VMINU_VV,  VMINU_VX,
        VMIN_VV,   VMIN_VX,
        VMAXU_VV,  VMAXU_VX,
        VMAX_VV,   VMAX_VX,

        // Narrowing shifts
        VNSRL_WV,  VNSRL_WX,  VNSRL_WI,
        VNSRA_WV,  VNSRA_WX,  VNSRA_WI,

        // Scaling shift
        VSSRL_VV,  VSSRL_VX,  VSSRL_VI,
        VSSRA_VV,  VSSRA_VX,  VSSRA_VI,

        // Narrowing clip
        VNCLIPU_WV,  VNCLIPU_WX,  VNCLIPU_WI,
        VNCLIP_WV,   VNCLIP_WX,   VNCLIP_WI,

        // Saturating
        VSADDU_VV,  VSADDU_VX,  VSADDU_VI,
        VSADD_VV,   VSADD_VX,   VSADD_VI,
        VSSUBU_VV,  VSSUBU_VX,
        VSSUB_VV,   VSSUB_VX,

        // Carry/borrow (add-with-carry / subtract-with-borrow)
        VADC_VVM,   VADC_VXM,   VADC_VIM,
        VMADC_VVM,  VMADC_VXM,  VMADC_VIM,
        VMADC_VV,   VMADC_VX,   VMADC_VI,    // no mask variant
        VSBC_VVM,   VSBC_VXM,
        VMSBC_VVM,  VMSBC_VXM,
        VMSBC_VV,   VMSBC_VX,                // no mask variant


        //  Integer multiply / divide / macc: OPMVV / OPMVX 
        VMUL_VV,     VMUL_VX,
        VMULH_VV,    VMULH_VX,
        VMULHU_VV,   VMULHU_VX,
        VMULHSU_VV,  VMULHSU_VX,
        VMACC_VV,    VMACC_VX,
        VNMSAC_VV,   VNMSAC_VX,
        VMADD_VV,    VMADD_VX,
        VNMSUB_VV,  VNMSUB_VX, 

        // Signed fractional multiply
        VSMUL_VV,  VSMUL_VX,

        // Div / rem 
        VDIVU_VV,  VDIVU_VX,
        VDIV_VV,   VDIV_VX,
        VREMU_VV,  VREMU_VX,
        VREM_VV,   VREM_VX,

        // Widening integer multiply
        VWMULU_VV,  VWMULU_VX,
        VWMUL_VV,   VWMUL_VX,
        VWMULSU_VV, VWMULSU_VX,

        // Widening integer multiply-add
        VWMACCU_VV,  VWMACCU_VX,
        VWMACC_VV,   VWMACC_VX,
        VWMACCSU_VV, VWMACCSU_VX,
        VWMACCUS_VX,                   // only VX form exists

        // Widening add/sub (vd/vs2 are 2*SEW)
        VWADDU_VV, VWADDU_VX, VWADDU_WV, VWADDU_WX,
        VWADD_VV,  VWADD_VX,  VWADD_WV,  VWADD_WX,
        VWSUBU_VV, VWSUBU_VX, VWSUBU_WV, VWSUBU_WX,
        VWSUB_VV,  VWSUB_VX,  VWSUB_WV,  VWSUB_WX,

        // Widening
        VWREDSUMU_VS,
        VWREDSUM_VS,

        // Averaging (OPMVV / OPMVX)
        VAADDU_VV,  VAADDU_VX,
        VAADD_VV,   VAADD_VX,
        VASUBU_VV,  VASUBU_VX,
        VASUB_VV,   VASUB_VX,

        //  Reductions: OPMVV 
        VMERGE_VVM,  VMERGE_VXM,  VMERGE_VIM,
        VMV_VV,      VMV_VX,      VMV_VI,     // TODO: All this instructions are actually valid

        VMVNRR_V,                             // TODO: review VMV1R_V, VMV2R_V, VMV4R_V, VMV8R_V, 
        VREDSUM_VS,
        VREDAND_VS,
        VREDOR_VS,
        VREDXOR_VS,
        VREDMINU_VS,
        VREDMIN_VS,
        VREDMAXU_VS,
        VREDMAX_VS,

        // Mask-register logical ops: OPMVV 
        VMSEQ_VV,   VMSEQ_VX,   VMSEQ_VI,
        VMSNE_VV,   VMSNE_VX,   VMSNE_VI,
        VMSLTU_VV,  VMSLTU_VX,
        VMSLT_VV,   VMSLT_VX,
        VMSLEU_VV,  VMSLEU_VX,  VMSLEU_VI,
        VMSLE_VV,   VMSLE_VX,   VMSLE_VI,
        VMSGTU_VX,  VMSGTU_VI,
        VMSGT_VX,   VMSGT_VI,


        // Mask logical — missing from enum entirely
        VMANDNOT_MM,
        VMAND_MM,
        VMOR_MM,
        VMXOR_MM,
        VMORNOT_MM,
        VMNAND_MM,
        VMNOR_MM,
        VMXNOR_MM,


        // Gather / slide
        VRGATHER_VV,    VRGATHER_VX,    VRGATHER_VI,
        VRGATHEREI16_VV,
        VSLIDEUP_VX,    VSLIDEUP_VI,
        VSLIDEDOWN_VX,  VSLIDEDOWN_VI,
        VSLIDE1UP_VX,
        VSLIDE1DOWN_VX,

        // vcompress
        VCOMPRESS_VM,

        // VWXUNARY0 group (funct6=010000, OPMVV) — scalar from vector / mask ops
        VMV_XS,       
        VCPOP_M,
        VFIRST_M,
        VID_V,

        // VMUNARY0 group (funct6=010100, OPMVV)
        VMSBF_M,
        VMSOF_M,
        VMSIF_M,
        VIOTA_M,

        // VRXUNARY0 group (funct6=010000, OPMVX) — scalar to vector
        VMV_SX,

        // VXUNARY0 group (funct6=010010, OPMVX) — zero/sign extend
        VZEXT_VF2,  VSEXT_VF2,    
        VZEXT_VF4,  VSEXT_VF4,    
        VZEXT_VF8,  VSEXT_VF8,    

        //  Vector configuration: OPCFG 
        VSETVLI,  VSETIVLI,  VSETVL,

        //  Unit-stride loads/stores 
        VLE8_V,  VLE16_V,   VLE32_V,     
        VLM_V,
        VSE8_V,  VSE16_V,   VSE32_V,
        VSM_V,

        //  Strided loads/stores 
        VLSE8_V, VLSE16_V, VLSE32_V,
        VSSE8_V, VSSE16_V, VSSE32_V,

        // Indexed-unordered loads/stores
        VLUXEI8_V, VLUXEI16_V, VLUXEI32_V,
        VSUXEI8_V, VSUXEI16_V, VSUXEI32_V,

        // Indexed-ordered loads/stores
        VLOXEI8_V, VLOXEI16_V, VLOXEI32_V, 
        VSOXEI8_V, VSOXEI16_V, VSOXEI32_V,

        // Unit-stride fault-only-first
        VLE8FF_V, VLE16FF_V, VLE32FF_V,

        //  Whole-register loads/stores 
        VL1RE8_V, VL1RE16_V, VL1RE32_V,
        VL2RE8_V, VL2RE16_V, VL2RE32_V,
        VL4RE8_V, VL4RE16_V, VL4RE32_V,
        VL8RE8_V, VL8RE16_V, VL8RE32_V, 
        VS1R_V, VS2R_V, VS4R_V, VS8R_V,

        //System Instructions
        CSRRS
    } vec_instr_e;


    // Operation performed, independent of operand format.
    // TODO: adjust listed operations to ones needing ALU only. And not repeated
    typedef enum logic [6:0] {
        OP_NONE,
        //Arithmetic and (bitwise) logic instructions
        OP_VADD, OP_VSUB, OP_VRSUB,
        OP_VAND, OP_VOR, OP_VXOR,	 
        OP_VWADDU, OP_VWADD, OP_VWSUBU, OP_VWSUB,
    	OP_VADC, OP_VSBC,

        // Integer add-with-carry and subtract-with-borrow carry-out instructions
        OP_VMADC, OP_VMSBC, 
        OP_VMMV, 

        //Shifts instructions
        OP_VSLL, OP_VSRL, OP_VSRA,
        OP_VNSRL, OP_VNSRA,
        
        //Mul/Mul-add instruction
        OP_VMUL, OP_VMULH, OP_VMULHU, OP_VMULHSU, 
        OP_VMACC, OP_VNMSAC, OP_VMADD, OP_VNMSUB,

        // Narrowing clip
        OP_VNCLIPU, OP_VNCLIP,
  
        //Vector Widening Integer Multiply Instructions
        OP_VWMUL, OP_VWMULU, OP_VWMULSU,	  
        
        //Vector Widening Integer Multiply-Add Instructions
        OP_VWMACCU, OP_VWMACC, OP_VWMACCSU, OP_VWMACCUS,
        
        // Averaging
        OP_VAADDU, OP_VAADD, 
        OP_VASUBU, OP_VASUB,

        //Div instruction
        OP_VDIVU, OP_VDIV, OP_VREMU, OP_VREM,	
        
        //Min/max instruction
        OP_VMINU, OP_VMIN, OP_VMAXU, OP_VMAX,
        
        //Integer comparison  instructions
        OP_VMSEQ, OP_VMSNE, OP_VMSLTU, OP_VMSLT, OP_VMSLEU, OP_VMSLE, OP_VMSGTU, OP_VMSGT, 
        VMSGEU, VMSGE,    //TODO: fix pseudoinstruction
        
        //Zero- sign- extend  --> Not necessary, EEW always > SEW   //TODO: necessary?
        VZEXT, VSEXT,  
        
        //Merge and move  instruction      
        OP_VMV, OP_VMERGE, 	

        // Mask operations
        OP_VMANDNOT, OP_VMAND, OP_VMOR, OP_VMXOR, OP_VMORNOT, OP_VMNAND, OP_VMNOR, OP_VMXNOR,

        // Saturating 
        OP_VSADDU, OP_VSADD,
        OP_VSSUBU, OP_VSSUB,
        OP_VSSRL, OP_VSSRA,
        OP_SMUL,

        // Slide instructions
        OP_VRGATHER,
        OP_VRGATHEREI16,
        OP_VSLIDEUP, OP_VSLIDEDOWN,
        OP_VSLIDE1UP,  OP_VSLIDE1DOWN,
        OP_VCOMPRESS,

        // VCSR
        OP_VCSR,

        //Reduction  //TODO: sure to implement?
        OP_VREDSUM, OP_VREDAND, OP_VREDOR, OP_VREDXOR,
        OP_VREDMINU, OP_VREDMIN, OP_VREDMAXU, OP_VREDMAX,
        OP_VWREDSUM,

        // Load instructions
        OP_VLE, OP_VLSE, OP_VLXE, OP_VLM, OP_LRE, OP_VLEFF,
        // Store instructions
        OP_VSE, OP_VSSE, OP_VSXE, OP_VSM, OP_VSR,

        // Config instruction
        OP_VCFG,

        // mask population / iota / element-index / first-set //TODO: remove?
        OP_VCPOP,
        OP_VFIRST,
        OP_VMSBF,
        OP_VMSIF,
        OP_VMSOF,
        OP_VIOTA,
        OP_VID,

        OP_ZEXT,
        OP_SEXT

    } op_e; 

    function automatic op_e instr_to_op(vec_instr_e instr);
        unique case (instr)
            // add/sub/widen/carry 
            VADD_VV, VADD_VX, VADD_VI:                          instr_to_op = OP_VADD;
            VSUB_VV, VSUB_VX:                                   instr_to_op = OP_VSUB;
            VRSUB_VX, VRSUB_VI:                                 instr_to_op = OP_VRSUB;
            VWADDU_VV, VWADDU_VX, VWADDU_WV, VWADDU_WX:         instr_to_op = OP_VWADDU;
            VWADD_VV,  VWADD_VX,  VWADD_WV,  VWADD_WX:          instr_to_op = OP_VWADD;
            VWSUBU_VV, VWSUBU_VX, VWSUBU_WV, VWSUBU_WX:         instr_to_op = OP_VWSUBU;
            VWSUB_VV,  VWSUB_VX,  VWSUB_WV,  VWSUB_WX:          instr_to_op = OP_VWSUB;
            VADC_VVM, VADC_VXM, VADC_VIM:                       instr_to_op = OP_VADC;
            VMADC_VVM, VMADC_VXM, VMADC_VIM,
            VMADC_VV,  VMADC_VX,  VMADC_VI:                     instr_to_op = OP_VMADC;
            VSBC_VVM, VSBC_VXM:                                 instr_to_op = OP_VSBC;
            VMSBC_VVM, VMSBC_VXM, VMSBC_VV, VMSBC_VX:           instr_to_op = OP_VMSBC;
            
            // logical / shift 
            VAND_VV, VAND_VX, VAND_VI:                          instr_to_op = OP_VAND;
            VOR_VV,  VOR_VX,  VOR_VI:                           instr_to_op = OP_VOR;
            VXOR_VV, VXOR_VX, VXOR_VI:                          instr_to_op = OP_VXOR;
            VSLL_VV, VSLL_VX, VSLL_VI:                          instr_to_op = OP_VSLL;
            VSRL_VV, VSRL_VX, VSRL_VI:                          instr_to_op = OP_VSRL;
            VSRA_VV, VSRA_VX, VSRA_VI:                          instr_to_op = OP_VSRA;
            VNSRL_WV, VNSRL_WX, VNSRL_WI:                       instr_to_op = OP_VNSRL;
            VNSRA_WV, VNSRA_WX, VNSRA_WI:                       instr_to_op = OP_VNSRA;
        
            // compares 
            VMSEQ_VV,  VMSEQ_VX,  VMSEQ_VI:                     instr_to_op = OP_VMSEQ;
            VMSNE_VV,  VMSNE_VX,  VMSNE_VI:                     instr_to_op = OP_VMSNE;
            VMSLTU_VV, VMSLTU_VX:                               instr_to_op = OP_VMSLTU;
            VMSLT_VV,  VMSLT_VX:                                instr_to_op = OP_VMSLT;
            VMSLEU_VV, VMSLEU_VX, VMSLEU_VI:                    instr_to_op = OP_VMSLEU;
            VMSLE_VV,  VMSLE_VX,  VMSLE_VI:                     instr_to_op = OP_VMSLE;
            VMSGTU_VX, VMSGTU_VI:                               instr_to_op = OP_VMSGTU;
            VMSGT_VX,  VMSGT_VI:                                instr_to_op = OP_VMSGT;

            // min/max 
            VMINU_VV, VMINU_VX:                                 instr_to_op = OP_VMINU;
            VMIN_VV,  VMIN_VX:                                  instr_to_op = OP_VMIN;
            VMAXU_VV, VMAXU_VX:                                 instr_to_op = OP_VMAXU;
            VMAX_VV,  VMAX_VX:                                  instr_to_op = OP_VMAX;
        
            // merge / move
            VMERGE_VVM, VMERGE_VXM, VMERGE_VIM:                 instr_to_op = OP_VMV;   //TODO: rethink architecture
            VMV_VV, VMV_VX, VMV_VI:                             instr_to_op = OP_VMV;   //TODO: rethink architecture   
            VMV_XS:                                             instr_to_op = OP_VMV;   //TODO: rethink architecture
            VMV_SX:                                             instr_to_op = OP_VMV;   //TODO: rethink architecture
            VMVNRR_V:                                           instr_to_op = OP_VMV;

            // saturating / averaging / scaling-shift / clip 
            VSADDU_VV, VSADDU_VX, VSADDU_VI:                    instr_to_op = OP_VSADDU;
            VSADD_VV,  VSADD_VX,  VSADD_VI:                     instr_to_op = OP_VSADD;
            VSSUBU_VV, VSSUBU_VX:                               instr_to_op = OP_VSSUBU;
            VSSUB_VV,  VSSUB_VX:                                instr_to_op = OP_VSSUB;
            VSMUL_VV,  VSMUL_VX:                                instr_to_op = OP_SMUL;
            VAADDU_VV, VAADDU_VX:                               instr_to_op = OP_VAADDU;
            VAADD_VV,  VAADD_VX:                                instr_to_op = OP_VAADD;
            VASUBU_VV, VASUBU_VX:                               instr_to_op = OP_VASUBU;
            VASUB_VV,  VASUB_VX:                                instr_to_op = OP_VASUB;
            VSSRL_VV, VSSRL_VX, VSSRL_VI:                       instr_to_op = OP_VSSRL;
            VSSRA_VV, VSSRA_VX, VSSRA_VI:                       instr_to_op = OP_VSSRA;
            VNCLIPU_WV, VNCLIPU_WX, VNCLIPU_WI:                 instr_to_op = OP_VNCLIPU;
            VNCLIP_WV,  VNCLIP_WX,  VNCLIP_WI:                  instr_to_op = OP_VNCLIP;
                                                                                          
            // permutation 
            VRGATHER_VV, VRGATHER_VX, VRGATHER_VI:              instr_to_op = OP_VRGATHER;
            VRGATHEREI16_VV:                                    instr_to_op = OP_VRGATHEREI16;
            VSLIDEUP_VX,   VSLIDEUP_VI:                         instr_to_op = OP_VSLIDEUP;
            VSLIDEDOWN_VX, VSLIDEDOWN_VI:                       instr_to_op = OP_VSLIDEDOWN;
            VSLIDE1UP_VX:                                       instr_to_op = OP_VSLIDE1UP;
            VSLIDE1DOWN_VX:                                     instr_to_op = OP_VSLIDE1DOWN;
            VCOMPRESS_VM:                                       instr_to_op = OP_VCOMPRESS;
                                                                                          
            // integer multiply / divide / macc
            VMUL_VV,    VMUL_VX:                                instr_to_op = OP_VMUL;
            VMULH_VV,   VMULH_VX:                               instr_to_op = OP_VMULH;
            VMULHU_VV,  VMULHU_VX:                              instr_to_op = OP_VMULHU;
            VMULHSU_VV, VMULHSU_VX:                             instr_to_op = OP_VMULHSU;
            VDIVU_VV,  VDIVU_VX:                                instr_to_op = OP_VDIVU;
            VDIV_VV,   VDIV_VX:                                 instr_to_op = OP_VDIV;
            VREMU_VV,  VREMU_VX:                                instr_to_op = OP_VREMU;
            VREM_VV,   VREM_VX:                                 instr_to_op = OP_VREM;
            VMACC_VV,  VMACC_VX:                                instr_to_op = OP_VMACC;
            VNMSAC_VV, VNMSAC_VX:                               instr_to_op = OP_VNMSAC;
            VMADD_VV,  VMADD_VX:                                instr_to_op = OP_VMADD;
            VNMSUB_VV, VNMSUB_VX:                               instr_to_op = OP_VNMSUB;
                                                                                          
            // widening multiply / macc 
            VWMULU_VV, VWMULU_VX:                               instr_to_op = OP_VWMULU;
            VWMUL_VV,  VWMUL_VX:                                instr_to_op = OP_VWMUL;
            VWMULSU_VV, VWMULSU_VX:                             instr_to_op = OP_VWMULSU;
            VWMACCU_VV, VWMACCU_VX:                             instr_to_op = OP_VWMACCU;
            VWMACC_VV,  VWMACC_VX:                              instr_to_op = OP_VWMACC;
            VWMACCSU_VV, VWMACCSU_VX:                           instr_to_op = OP_VWMACCSU;
            VWMACCUS_VX:                                        instr_to_op = OP_VWMACCUS;
                                                                                          
            // reductions 
            VREDSUM_VS:                                         instr_to_op = OP_VREDSUM;
            VREDAND_VS:                                         instr_to_op = OP_VREDAND;
            VREDOR_VS:                                          instr_to_op = OP_VREDOR;
            VREDXOR_VS:                                         instr_to_op = OP_VREDXOR;
            VREDMINU_VS:                                        instr_to_op = OP_VREDMINU;
            VREDMIN_VS:                                         instr_to_op = OP_VREDMIN;
            VREDMAXU_VS:                                        instr_to_op = OP_VREDMAXU;
            VREDMAX_VS:                                         instr_to_op = OP_VREDMAX;
            VWREDSUMU_VS:                                       instr_to_op = OP_VWREDSUM;
            VWREDSUM_VS:                                        instr_to_op = OP_VWREDSUM;
                                                                                          
            // mask-register logical 
            VMAND_MM:                                           instr_to_op = OP_VMAND;
            VMNAND_MM:                                          instr_to_op = OP_VMNAND;
            VMANDNOT_MM:                                        instr_to_op = OP_VMANDNOT;
            VMOR_MM:                                            instr_to_op = OP_VMOR;
            VMNOR_MM:                                           instr_to_op = OP_VMNOR;
            VMORNOT_MM:                                         instr_to_op = OP_VMORNOT;
            VMXOR_MM:                                           instr_to_op = OP_VMXOR;
            VMXNOR_MM:                                          instr_to_op = OP_VMXNOR;
                                            
            // mask population / iota / element-index / first-se
            VCPOP_M:                                            instr_to_op = OP_VCPOP;
            VFIRST_M:                                           instr_to_op = OP_VFIRST;
            VMSBF_M:                                            instr_to_op = OP_VMSBF;
            VMSIF_M:                                            instr_to_op = OP_VMSIF;
            VMSOF_M:                                            instr_to_op = OP_VMSOF;
            VIOTA_M:                                            instr_to_op = OP_VIOTA;
            VID_V:                                              instr_to_op = OP_VID;

            VZEXT_VF2, VZEXT_VF4, VZEXT_VF8:                    instr_to_op = OP_ZEXT;
            VSEXT_VF2, VSEXT_VF4, VSEXT_VF8:                    instr_to_op = OP_SEXT;
                                                                                          
            // configuration 
            VSETVLI, VSETIVLI, VSETVL:                          instr_to_op = OP_VCFG;
                                                                                  
            // loads                                            //TODO: necessary specific?
            VLE8_V, VLE16_V, VLE32_V:                           instr_to_op = OP_VLE;
            VLSE8_V, VLSE16_V, VLSE32_V:                        instr_to_op = OP_VLSE; 
            VLUXEI8_V, VLUXEI16_V, VLUXEI32_V,                 
            VLOXEI8_V, VLOXEI16_V, VLOXEI32_V:                  instr_to_op = OP_VLXE; 
            VLM_V:                                              instr_to_op = OP_VLM;
            VL1RE8_V, VL1RE16_V, VL1RE32_V,
            VL2RE8_V, VL2RE16_V, VL2RE32_V,
            VL4RE8_V, VL4RE16_V, VL4RE32_V,
            VL8RE8_V, VL8RE16_V, VL8RE32_V:                     instr_to_op = OP_LRE;
            VLE8FF_V, VLE16FF_V, VLE32FF_V:                     instr_to_op = OP_VLEFF;
                                                                                          
            // stores 
            VSE8_V, VSE16_V, VSE32_V:                           instr_to_op = OP_VSE; 
            VSSE8_V, VSSE16_V, VSSE32_V:                        instr_to_op = OP_VSSE;
            VSUXEI8_V, VSUXEI16_V, VSUXEI32_V,
            VSOXEI8_V, VSOXEI16_V, VSOXEI32_V:                  instr_to_op = OP_VSXE;
            VSM_V:                                              instr_to_op = OP_VSM;
            VS1R_V, VS2R_V, VS4R_V, VS8R_V:                     instr_to_op = OP_VSR;                                                                                        

            default:                                            instr_to_op = OP_NONE; 
        endcase

    endfunction

endpackage 
    