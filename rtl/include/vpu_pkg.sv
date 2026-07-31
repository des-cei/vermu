// Copyright 2026 CEIMM-UPM
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
    import cvxif_types_pkg::x_issue_t;
    import cvxif_types_pkg::x_issue_fifo_res_t;

    ////////////////
    // Parameters //
    ////////////////
               
    localparam int unsigned XLEN = 32;  //[FIXED]
    // typedef logic [XLEN-1:0] xlen_t;    
    
    // Maximum size of a single vector element in bits (ELEN ≥ 8)[FIXED]
    localparam int unsigned ELEN = 32;       

    // typedef logic [31:0] elen_t;    
    
    // Number of bits in a vector register (in each of 32 registers). Min 32. [STATIC]
    localparam int unsigned VPU_VLEN = 256; //128;	             
    
    // Number of Integer  Processing Units [STATIC]
    localparam int unsigned VPU_N_IPU = 2;	             

    // Maximum Register Grouping [FIXED]
    localparam int unsigned VPU_LMUL_MAX = 8;	             
    
    // typedef logic [VPU_VLEN-1:0] vlen_t;                    

    // localparam int unsigned VLENB = VPU_VLEN / 8; 
                   
    // // Selected element width [DYNAMIC]
    // localparam int unsigned SEW = 32; 	

    // // Number of vector registers (RV32I) [FIXED]
    // localparam int unsigned NRVREG = 32;

    // typedef logic [$clog2(NRVREG)-1:0] vreg_t;
    // typedef logic[$clog2(NRVREG)-1:0] addr_t;
	
    // Maximum vector length in elements 
    localparam int unsigned MAXVL  = VPU_VLEN / 8; 

    typedef logic [$clog2(MAXVL+1)-1:0] vl_t;      

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
        OPCODE_LOAD   = 7'h7,             
        OPCODE_STORE  = 7'h27,            
        OPCODE_OP_V   = 7'h57,
        OPCODE_SYSTEM = 7'h73                   
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
        vec_instr_e    instr_enum;
        // logic          valid;
        // logic          illegal;
        logic           writeback;

        major_opcode_e major_opcode;
        vec_funct3_e   fmt;       // OP-V funct3 field; meaningful when opcode==OPCODE_OP_V
        logic [5:0]    funct6;
        op_e           operation;

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
        logic [2:0]    nf;        // number of fields (segments)
        logic [2:0]    width;     // EEW encoding for loads/stores
        logic          mew;
        logic [1:0]    mop;       
        logic [4:0]    umop;      // lumop / sumop

        // category flags -- consumers branch on these, never on raw opcode bits
        logic          is_arith;
        logic          is_load;
        logic          is_store;
        // logic          is_config;
        // logic          is_mask_logic;
        logic          is_reduction;
        logic          is_widening;
        logic          is_narrowing;
        // logic          is_signed;

        // operand-presence flags -- tell the register-read stage what to fetch
        logic          uses_vs1;
        logic          uses_vs2;
        logic          uses_vd_src;     // vd/vs3 also read (macc-style, store data)
        logic          uses_rs1_scalar;
        logic          uses_rs2_scalar;
        logic          uses_imm;

        // CSRs information
        sew_e          vsew;
        lmul_e         vlmul;
        vl_t           vl;
    } vpu_decoded_t;

    ////////////////
    // Dispatcher //
    ////////////////

    localparam int unsigned FU_VALU = 0;
    localparam int unsigned FU_VLSU = 1;
    localparam int unsigned FU_VSLD = 2;
    localparam int unsigned MAX_INFLIGHT  = 3;
 
    // Dispatch stall reason (for debug / coverage) TODO: remove
    typedef enum logic [1:0] {
        STALL_NONE     = 2'b00,  // no stall
        STALL_HAZARD   = 2'b01,  // data hazard (RAW / WAW)
        STALL_STRUCT   = 2'b10,  // structural: target FU slot occupied
        STALL_BOTH     = 2'b11   // both (hazard takes priority in reporting)
    } stall_reason_e;

    // Derived constants
    localparam int unsigned DW            = VPU_N_IPU * XLEN;             // [STATIC] datapath width (bits) 
    localparam int unsigned FRAGS_PER_REG = VPU_VLEN / DW;                // fragments to cover per register
    localparam int unsigned FRAG_MAX      = FRAGS_PER_REG * VPU_LMUL_MAX; // max fragments per instruction
    localparam int unsigned FRAG_CNT_W    = $clog2(FRAG_MAX) + 1;         // counter width
    localparam int unsigned FRAG_MSK_W    = FRAG_MAX;                     // mask width
    localparam int unsigned REG_OFF_W     = $clog2(VPU_LMUL_MAX) + 1;     // reg offset width


    typedef struct packed { 
        // Fragmentation data for chaining
        logic [FRAG_CNT_W-1:0]   frag_idx;  //[$clog2(FRAGS_PER_REG)-1:0] ?
        logic                    is_last;
        logic [4:0]              dispatch_vd;  
        logic [4:0]              dispatch_vs1; 
        logic [4:0]              dispatch_vs2; 
    } dispatch_sideband_t;

    ///////////////////
    // XIF Interface //
    ///////////////////

    // Complementary VPU fields for 'wrapper_exe_instr_issue'
    // Dispatched issue
    typedef struct packed {
        x_issue_t            instr_issue;      // instruction issued
        vpu_decoded_t        instr_decoded;    // issue decoded
        dispatch_sideband_t  instr_fragment;
    } vpu_issue_t;

    // Complementary VPU fields for 'exe_wrapper_result'
    typedef struct packed {
        x_issue_fifo_res_t   xif_fifo_result;
        vpu_decoded_t        instr_decoded;    // issue decoded
        dispatch_sideband_t  instr_fragment;
    } vpu_issue_fifo_res_t;


endpackage