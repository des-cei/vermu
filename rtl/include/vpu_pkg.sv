// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// [STATIC] --> design-time
// [FIXED]  --> defined by specification
// [DYNAMIC]--> by user
//
// TODO: template for generic use cases.

package vpu_pkg;

    import rvv_instr_pkg::*;
    // import vector_ops_pkg::*;

    ////////////////
    // Parameters //
    ////////////////
               
    localparam int unsigned XLEN = 32;  //[FIXED]
    // typedef logic [XLEN-1:0] xlen_t;    
    
    // // Maximum size of a single vector element in bits (ELEN ≥ 8)[FIXED]
    // localparam int unsigned ELEN = 32;       

    // typedef logic [31:0] elen_t;    
    
    // // Number of bits in a vector register (in each of 32 registers). Min 32. [STATIC]
    // localparam int unsigned VLEN = 128;	             
    
    // typedef logic [VLEN-1:0] vlen_t;                    

    // localparam int unsigned VLENB = VLEN / 8; 
                   
    // // Selected element width [DYNAMIC]
    // localparam int unsigned SEW = 32; 	

    // // Number of vector registers (RV32I) [FIXED]
    // localparam int unsigned NRVREG = 32;

    // typedef logic [$clog2(NRVREG)-1:0] vreg_t;
    // typedef logic[$clog2(NRVREG)-1:0] addr_t;
	
    // // Maximum vector length in elements 
    // localparam int unsigned MAXVL  = VLEN / 8; 

    // typedef logic [$clog2(MAXVL+1)-1:0] vl_t;      

    // Core-V Extension Interface param
    localparam int unsigned NrRgprPorts = 2;

    //////////////////
    //  Definitions //
    //////////////////

    // SEW: selected element width.(8,16,32)
    typedef enum logic [2:0] {
        SEW_8  = 3'b000,
        SEW_16 = 3'b001,
        SEW_32 = 3'b010
    } sew_e;

    typedef enum logic [2:0] {
        LMUL_F4 = 3'b110,
        LMUL_F2 = 3'b111,
        LMUL_1  = 3'b000,
        LMUL_2  = 3'b001,
        LMUL_4  = 3'b010,
        LMUL_8  = 3'b011
    } lmul_e;

    // Source formats
    typedef enum logic [6:0] {   
        OPCODE_LOAD  = 7'h7,             
        OPCODE_STORE = 7'h27,            
        OPCODE_OP_V  = 7'h57             
        //system   = 7'b1110011     
    } major_opcode_e;
    
    //Operand type for OP-V instructions and operand-format 
    typedef enum logic [2:0] {
        FMT_OPIVV        = 3'b000, 
        FMT_OPFVV_CSRRW  = 3'b001,     //--N/A
        FMT_OPMVV_CSRRS  = 3'b010,     
        FMT_OPIVI_CSRRC  = 3'b011,     //imm[4:0]
        FMT_OPIVX        = 3'b100,     //GPR x, rs1
        FMT_OPFVF_CSRRWI = 3'b101,     //--N/A
        FMT_OPMVX_CSRRSI = 3'b110,     //GPR x, rs1
        FMT_OPCFG_CSRRCI = 3'b111      //GPR x, rs1 & rs2/imm. 311p. Format under OP-V opcode? vsetvli, vsetvl
    } vec_funct3_e;
    
    typedef struct packed {
        vec_instr_e                         instr_enum;
        logic [31:0]                        instr;
        logic [NrRgprPorts-1:0][XLEN-1:0]   registers;
        logic                               writeback;
    } buff_dec_t;

    typedef struct packed {
        vec_instr_e    instr_enum;
        // logic          valid;
        // logic          illegal;

        major_opcode_e major_opcode;
        vec_funct3_e   fmt;       // OP-V funct3 field; meaningful when opcode==OPCODE_OP_V
        logic [5:0]    funct6;

        // register fields 
        logic [4:0]    vd;           // also rd for scalar dest (vsetvl*)
        logic [4:0]    vs1;          // also rs1 for *VX/*VF and rs1 for vset*
        logic [4:0]    vs2;          // also rs2 for vsetvl
        logic [4:0]    vs3;          // store-data register (same bit position as vd)
        logic [4:0]    imm5;         // OPIVI immediate (sign-extend at execute if needed)
        logic [XLEN-1:0] rs1_data;
        logic [XLEN-1:0] rs2_data;
        // logic [10:0]   zimm11;    // vsetvli immediate
        // logic [9:0]    zimm10;    // vsetivli immediate
        // logic [4:0]    avl_uimm;  // vsetivli AVL (5-bit unsigned immediate)
        logic          vm;        // vector mask-enable bit

        // memory-only fields (meaningful when opcode is LOAD_FP/STORE_FP)
        // logic [2:0]    width;     // EEW encoding for loads/stores
        // logic [2:0]    nf;        // number of fields (segments)
        // logic          mew;
        // logic [1:0]    mop;       // addressing mode: 00 unit-stride, 10 strided,
        //                           //                   01 indexed-unordered, 11 indexed-ordered
        // logic [4:0]    umop;      // lumop / sumop

        // category flags -- consumers branch on these, never on raw opcode bits
        logic          is_arith;
        logic          is_load;
        logic          is_store;
        // logic          is_config;
        // logic          is_mask_logic;
        // logic          is_reduction;
        // logic          is_widening;
        logic             is_narrowing;
        // logic          is_signed;

        // operand-presence flags -- tell the register-read stage what to fetch
        // logic          uses_vs1;
        // logic          uses_vs2;
        // logic          uses_vd_src;     // vd/vs3 also read (macc-style, store data)
        // logic          uses_rs1_scalar;
        // logic          uses_rs2_scalar;
        // logic          uses_imm;
    } vec_decoded_t;




endpackage