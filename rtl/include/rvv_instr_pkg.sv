// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)


package rvv_instr_pkg; 

    typedef enum logic [6:0] {   
        ILLEGAL,
        NOP,
        VLE8,
        VLE16,
        VLE32,
        VLSE8,
        VLSE16,
        VLSE32,
        VL1RE32_V,
        VSE8,
        VSE16,
        VSE32,
        VS1R_V,  
        VSETVLI,
        VSETIVLI,
        VSETVL,
        CSRRS,
        VADD_VV,
        VADD_VI,
        VADD_VX,
        VSUB_VV,
        VSUB_VX,
        VRSUB_VX,
        VRSUB_VI,
        VAND_VV,
        VAND_VI,
        VAND_VX,
        VOR_VV,
        VOR_VI,
        VOR_VX,
        VXOR_VV,
        VXOR_VI,
        VXOR_VX,
        VSLL_VV,
        VSLL_VX,
        VSLL_VI,
        VSRL_VV,
        VSRL_VX,
        VSRL_VI,
        VSRA_VV,
        VSRA_VX,
        VSRA_VI,
        VMINU_VV,
        VMINU_VX,
        VMIN_VV,
        VMIN_VX,
        VMAXU_VV,
        VMAXU_VX,
        VMAX_VV,
        VMAX_VX,
        VMSEQ_VV,
        VMSEQ_VX,
        VMSEQ_VI,
        VMSNE_VV,
        VMSNE_VX,
        VMSNE_VI,
        VMSLTU_VV,
        VMSLTU_VX,
        VMSLT_VV,
        VMSLT_VX,
        VMUL_VV,
        VMUL_VX,
        VMULH_VV,
        VMULH_VX,
        VMULHU_VV,
        VMULHU_VX,
        VMULHSU_VV,
        VMULHSU_VX,
        VMACC_VV,
        VMACC_VX,
        VNMSAC_VV,
        VNMSAC_VX,
        VMADD_VV,
        VMADD_VX,
        VMERGE_VVM,
        VMERGE_VXM,
        VMERGE_VIM,
        VMV_VV,
        VMV_VX,
        VMV_VI,
        VMV_XS,
        VMV_SX,
        VMV1R_V,
        VMV2R_V,
        VMV4R_V,
        VMV8R_V,
        VREDSUM_VS,
        VID_V
    } opcode_t;

    typedef struct packed {
        logic accept;
        logic writeback;  // TODO depends on dualwrite
        logic [2:0] register_read;  // TODO Nr read ports
    } issue_resp_t;

    typedef struct packed {
        logic [31:0] instr;
        logic [31:0] mask;
        issue_resp_t resp;
        opcode_t     opcode;
    } copro_issue_resp_t;

    parameter int unsigned NbInstr = 87;     
    parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
        '{
            // Custom Nop
            instr: 32'b00000_00_00000_00000_0_00_00000_1111011,  // custom3 opcode
            mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b0, 1'b0}},
            opcode : NOP
        },
        '{
            // vle8.v vd, (rs1)
            instr: 32'b000_0_00_0_00000_00000_000_00000_0000111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLE8
        },
        '{
            // vle16.v vd, (rs1)
            instr: 32'b000_0_00_0_00000_00000_101_00000_0000111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLE16
        },
        '{
            // vle32.v vd, (rs1)
            instr: 32'b000_0_00_0_00000_00000_110_00000_0000111, // template for 32-bit element load
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, // mask relevant fields
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLE32
        },
        '{
            // vlse8.v vd, (rs1), rs2, vm
            instr: 32'b000_0_10_0_00000_00000_000_00000_0000111,
            mask:  32'b111_1_11_0_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLSE8
        },
        '{
            // vlse16.v vd, (rs1), rs2, vm
            instr: 32'b000_0_10_0_00000_00000_101_00000_0000111,
            mask:  32'b111_1_11_0_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLSE16
        },        
        '{
            // vlse32.v vd, (rs1), rs2, vm
            instr: 32'b000_0_10_0_00000_00000_110_00000_0000111,
            mask:  32'b111_1_11_0_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VLSE32
        },
        '{
            // vl1re32.v	v31,(sp)
            instr: 32'b000_0_00_0_01000_00000_110_00000_0000111,
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VL1RE32_V
        },
        '{
            // vse8.v vs3, (rs1), vm 
            instr: 32'b000_0_00_0_00000_00000_000_00000_0100111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSE8
        },  
        '{
            // vse16.v vs3, (rs1), vm 
            instr: 32'b000_0_00_0_00000_00000_101_00000_0100111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSE16
        },  
        '{
            // vse32.v vs3, (rs1)
            instr: 32'b000_0_00_0_00000_00000_110_00000_0100111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSE32
        },          
        '{
            // vs1r.v v3, (a1)
            instr: 32'b000_0_00_0_01000_00000_000_00000_0100111,  
            mask:  32'b111_1_11_0_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VS1R_V
        },
        '{
            // vsetvli rd, rs1, vtypei
            instr: 32'b0_00000000000_00000_111_00000_1010111, 
            mask:  32'b1_00000000000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSETVLI
        },
        '{
            // vsetvli rd, rs1, vtypei
            instr: 32'b11_0000000000_00000_111_00000_1010111,  
            mask:  32'b11_0000000000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSETIVLI
        },
        '{
            // vsetvli rd, rs1, vtypei
            instr: 32'b1_000000_00000_00000_111_00000_1010111, 
            mask:  32'b1_111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSETVL
        },
        '{
            // csrrs
            instr: 32'b000000000000_00000_010_00000_1110011, 
            mask:  32'b000000000000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1,1'b1}},
            opcode : CSRRS
        },
        '{
            //vadd.vv vd, vs2, vs1, vm # Vector-vector
            instr: 32'b0000000_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VADD_VV
        },
        '{
            //vadd.vv vd, vs2, vs1, vm # Vector-immediate
            instr: 32'b0000000_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VADD_VI
        },
        '{
            //vadd.vv vd, vs2, vs1, vm # Vector-scalar
            instr: 32'b0000000_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VADD_VX
        },
        '{
            //vsub.vv vd, vs2, vs1, vm # Vector-vector
            instr: 32'b0000100_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSUB_VV
        },
        '{
            //vsub.vx vd, vs2, vs1, vm
            instr: 32'b0000100_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSUB_VX
        },
        '{
            //vrsub.vx vd, vs2, vs1, vm 
            instr: 32'b0000110_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VRSUB_VX
        },
        '{
            //vrsub.vx vd, vs2, vs1, vm 
            instr: 32'b0000110_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VRSUB_VI
        },
        '{
            //vand.vv vd, vs2, vs1, vm 
            instr: 32'b0010010_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VAND_VV
        },
        '{
            //vand.vi vd, vs2, vs1, vm 
            instr: 32'b0010010_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VAND_VI
        },
        '{
            //vand.vx vd, vs2, vs1, vm 
            instr: 32'b0010010_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VAND_VX
        },
        '{
            //vor.vv vd, vs2, vs1, vm 
            instr: 32'b0010100_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VOR_VV
        },
        '{
            //vor.vi vd, vs2, vs1, vm 
            instr: 32'b0010100_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VOR_VI
        },
        '{
            //vor.vx vd, vs2, vs1, vm 
            instr: 32'b0010100_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VOR_VX
        },
        '{
            //vxor.vv vd, vs2, vs1, vm 
            instr: 32'b0010110_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VXOR_VV
        },
        '{
            //vxor.vi vd, vs2, vs1, vm 
            instr: 32'b0010110_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VXOR_VI
        },
        '{
            //vxor.vx vd, vs2, vs1, vm 
            instr: 32'b0010110_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VXOR_VX
        },
        '{
            //vsll.vv vd, vs2, vs1, vm
            instr: 32'b1001010_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSLL_VV
        },
        '{
            //sll.vx vd, vs2, rs1, vm
            instr: 32'b1001010_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSLL_VX
        },
        '{
            //vsll.vi vd, vs2, uimm, vm 
            instr: 32'b1001010_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSLL_VI
        },
        '{
            //vsrl.vv vd, vs2, vs1, vm
            instr: 32'b1010000_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRL_VV
        },
        '{
            //vsrl.vx vd, vs2, rs1, vm
            instr: 32'b1010000_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRL_VX
        },
        '{
            //vsrl.vi vd, vs2, uimm, vm
            instr: 32'b1010000_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRL_VI
        },
        '{
            //vsra.vv vd, vs2, vs1, vm
            instr: 32'b1010010_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRA_VV
        },
        '{
            //vsra.vx vd, vs2, rs1, vm
            instr: 32'b1010010_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRA_VX
        },
        '{
            //vsra.vi vd, vs2, uimm, vm
            instr: 32'b1010010_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VSRA_VI
        },
        '{
            //vminu.vv vd, vs2, vs1, vm
            instr: 32'b0001000_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMINU_VV
        },
        '{
            //vminu.vx vd, vs2, rs1, vm
            instr: 32'b0001000_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMINU_VX
        },
        '{
            //vmin.vv vd, vs2, vs1, vm
            instr: 32'b0001010_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMIN_VV
        },
        '{
            //vmin.vx vd, vs2, rs1, vm
            instr: 32'b0001010_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMIN_VX
        },
        '{
            //vmaxu.vv vd, vs2, vs1, vm
            instr: 32'b0001100_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMAXU_VV
        },
        '{
            //vmaxu.vx vd, vs2, rs1, vm
            instr: 32'b0001100_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMAXU_VX
        },
        '{
            //vmax.vv vd, vs2, vs1, vm
            instr: 32'b0001110_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMAX_VV
        },
        '{
            //vmax.vx vd, vs2, rs1, vm
            instr: 32'b0001110_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMAX_VX
        },
        '{
            //vmseq.vv vd, vs2, vs1, vm 
            instr: 32'b0110000_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSEQ_VV
        },
        '{
            //vmseq.vx vd, vs2, rs1, vm 
            instr: 32'b0110000_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSEQ_VX
        },
        '{
            //vmseq.vi vd, vs2, imm, vm
            instr: 32'b0110000_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSEQ_VI
        },
        '{
            //vmsne.vv vd, vs2, vs1, vm 
            instr: 32'b0110010_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSNE_VV
        },
        '{
            //vmsne.vx vd, vs2, rs1, vm 
            instr: 32'b0110010_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSNE_VX
        },
        '{
            //vmsne.vi vd, vs2, imm, vm
            instr: 32'b0110010_00000_00000_011_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSNE_VI
        },
        '{
            //vmsltu.vv vd, vs2, vs1, vm
            instr: 32'b0110100_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSLTU_VV
        },
        '{
            //vmsltu.vx vd, vs2, vs1, vm
            instr: 32'b0110100_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSLTU_VX
        },
        '{
            //vmslt.vv vd, vs2, vs1, vm
            instr: 32'b0110110_00000_00000_000_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSLT_VV
        },
        '{
            //vmslt.vx vd, vs2, vs1, vm
            instr: 32'b0110110_00000_00000_100_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMSLT_VX
        },
        '{
            //vmul.vv vd, vs2, vs1, vm
            instr: 32'b1001010_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMUL_VV
        },
        '{
            //vmul.vx vd, vs2, rs1, vm
            instr: 32'b1001010_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMUL_VX
        },
        '{
            //vmulh.vv vd, vs2, vs1, vm 
            instr: 32'b1001110_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULH_VV
        },
        '{
            //vmulh.vx vd, vs2, rs1, vm 
            instr: 32'b1001110_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULH_VX
        },
        '{
            //vmulhu.vv vd, vs2, vs1, vm
            instr: 32'b1001000_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULHU_VV
        },
        '{
            //vmulhu.vx vd, vs2, rs1, vm
            instr: 32'b1001000_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULHU_VX
        },
        '{
            //vmulhsu.vv vd, vs2, vs1, vm 
            instr: 32'b1001100_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULHSU_VV
        },
        '{
            //vmulhsu.vx vd, vs2, rs1, vm 
            instr: 32'b1001100_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMULHSU_VX
        },
        '{
            //vmacc.vv vd, vs1, vs2, vm 
            instr: 32'b1011010_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMACC_VV
        },
        '{
            //vmacc.vx vd, rs1, vs2, vm 
            instr: 32'b1011010_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMACC_VX
        },
        '{
            //vnmsac.vv vd, vs1, vs2, vm 
            instr: 32'b1011110_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VNMSAC_VV
        },
        '{
            //vnmsac.vx vd, rs1, vs2, vm 
            instr: 32'b1011110_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VNMSAC_VX
        },
        '{
            //vmadd.vv vd, vs1, vs2, vm 
            instr: 32'b1010010_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMADD_VV
        },
        '{
            //vmadd.vx vd, rs1, vs2, vm 
            instr: 32'b1010010_00000_00000_110_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMADD_VX
        },
        '{
            //vmerge.vvm vd, vs2, vs1, v0 
            instr: 32'b0101110_00000_00000_000_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMERGE_VVM
        },
        '{  
            //vmerge.vxm vd, vs2, rs1, v0
            instr: 32'b0101110_00000_00000_100_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMERGE_VXM
        },
        '{
            //vmerge.vim vd, vs2, imm, v0 
            instr: 32'b0101110_00000_00000_011_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMERGE_VIM
        },
        '{
            //vmv.v.v vd, vs1
            instr: 32'b0101111_00000_00000_000_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV_VV
        },
        '{  
            //vmv.v.x vd, rs1
            instr: 32'b0101111_00000_00000_100_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV_VX
        },
        '{
            //vmv.v.i vd
            instr: 32'b0101111_00000_00000_011_00000_1010111, 
            mask:  32'b1111111_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV_VI
        },
        '{  
            //vmv.x.s rd, vs2
            instr: 32'b0100001_00000_00000_010_00000_1010111, 
            mask:  32'b1111111_00000_11111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV_XS
        },
        '{  
            //vmv.s.x vd, rs1
            instr: 32'b0100001_00000_00000_110_00000_1010111, 
            mask:  32'b1111111_11111_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV_SX
        },
        '{
            //vmv<nr>r.v vd, vs2
            instr: 32'b1001111_00000_00000_011_00000_1010111, 
            mask:  32'b1111111_00000_00111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV1R_V
        },
        '{
            //vmv<nr>r.v vd, vs2
            instr: 32'b1001111_00000_00001_011_00000_1010111, 
            mask:  32'b1111111_00000_00111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV2R_V
        },
        '{
            //vmv<nr>r.v vd, vs2
            instr: 32'b1001111_00000_00011_011_00000_1010111, 
            mask:  32'b1111111_00000_00111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV4R_V
        },
        '{
            //vmv<nr>r.v vd, vs2
            instr: 32'b1001111_00000_00111_011_00000_1010111, 
            mask:  32'b1111111_00000_00111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VMV8R_V
        },
        '{
            //vredsum.vs vd, vs2, vs1, vm
            instr: 32'b0000000_00000_00000_010_00000_1010111, 
            mask:  32'b1111110_00000_00000_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VREDSUM_VS
        },
        '{
            //vid.v vd, vm 
            instr: 32'b0101000_00000_10001_010_00000_1010111, 
            mask:  32'b1111110_00000_11111_111_00000_1111111, 
            resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b1,1'b1}},
            opcode : VID_V
        }

    };

    typedef enum logic [11:0] { 
        CSR_VSTART = 12'h8,
        CSR_XSAT   = 12'h9,
        CSR_VXRM   = 12'hA, 
        CSR_VCSR   = 12'hF,
        CSR_VL     = 12'hC20,
        CSR_VTYPE  = 12'hC21,
        CSR_VLENB  = 12'hC22
    } csr_addr_e;

    typedef struct packed {
        logic read_CSR;
        logic write_CSR;  
    } csr_handle_t;

endpackage 
    