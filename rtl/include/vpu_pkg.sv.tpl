// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// This file is rendered by Makefile. Do not compile it directly.

package vpu_pkg;

    import rvv_instr_pkg::*;
    import cvxif_types_pkg::x_issue_t;
    import cvxif_types_pkg::x_issue_fifo_res_t;

    ////////////////
    // Parameters //
    ////////////////
               
    localparam int unsigned XLEN = 32;  //[FIXED]
    // typedef logic [XLEN-1:0] xlen_t;    
    
    // Maximum size of a single vector element in bits (ELEN >= 8)[FIXED]
    localparam int unsigned ELEN = 32;       

    // typedef logic [31:0] elen_t;    
    
    // Number of bits in a vector register (in each of 32 registers). Min 32. [DYNAMIC]
    localparam int unsigned VPU_VLEN = @VPU_VLEN@;             
    
    // Number of Integer Processing Units [DYNAMIC]
    localparam int unsigned VPU_N_IPU = @VPU_N_IPU@;             

    // Datapath width
    typedef logic [VPU_N_IPU*ELEN-1:0] dw_t;

    // Maximum Register Grouping [FIXED]
    localparam int unsigned VPU_LMUL_MAX = 8;             
    
    typedef logic [VPU_VLEN-1:0] vlen_t;

    localparam int unsigned VLENB = VPU_VLEN / 8; 
    localparam int unsigned VLENB_W = $clog2(VPU_VLEN / 8 + 1); 
                  
    // Number of vector registers (RV32I) [FIXED]
    localparam int unsigned NRVREG = 32;

    // Maximum vector length in elements 
    localparam int unsigned MAXVL  = VPU_VLEN * 8 / 8;
    localparam int unsigned MAXVL_W   = $clog2(MAXVL + 1);

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
        FMT_OPFVV_CSRRW  = 3'b001,
        FMT_OPMVV_CSRRS  = 3'b010,
        FMT_OPIVI_CSRRC  = 3'b011,
        FMT_OPIVX        = 3'b100,
        FMT_OPFVF_CSRRWI = 3'b101,
        FMT_OPMVX_CSRRSI = 3'b110,
        FMT_OPCFG_CSRRCI = 3'b111
    } vec_funct3_e;

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
        logic          vill;
        logic          vma;
        logic          vta;
        sew_e          vsew;
        lmul_e         vlmul;
    } vtype_t;

    typedef struct packed {
        vec_instr_e    instr_enum;
        logic          writeback;
        major_opcode_e major_opcode;
        vec_funct3_e   fmt;
        logic [5:0]    funct6;
        op_e           operation;
        logic [4:0]    vd;
        logic [4:0]    vs1;
        logic [4:0]    vs2;
        logic [4:0]    vs3;
        logic [4:0]    imm5;
        logic [XLEN-1:0] rs1_data;
        logic [XLEN-1:0] rs2_data;
        logic          vm;
        logic [2:0]    nf;
        logic [2:0]    width;
        logic          mew;
        logic [1:0]    mop;
        logic [4:0]    umop;
        logic          is_arith;
        logic          is_load;
        logic          is_store;
        logic          is_reduction;
        logic          is_widening;
        logic          is_narrowing;
        logic          uses_vs1;
        logic          uses_vs2;
        logic          uses_vd_src;
        logic          uses_rs1_scalar;
        logic          uses_rs2_scalar;
        logic          uses_imm;
        lmul_e         emul;
        vtype_t        vtype;
        vl_t           vl;
        vl_t           vstart;
    } vpu_decoded_t;

    ////////////////
    // Dispatcher //
    ////////////////

    localparam int unsigned FU_VALU = 0;
    localparam int unsigned FU_VLSU = 1;
    localparam int unsigned FU_VSLD = 2;
    localparam int unsigned MAX_INFLIGHT  = 3;
 
    typedef enum logic [1:0] {
        STALL_NONE     = 2'b00,
        STALL_HAZARD   = 2'b01,
        STALL_STRUCT   = 2'b10,
        STALL_BOTH     = 2'b11
    } stall_reason_e;

    // Derived constants
    localparam int unsigned DW            = VPU_N_IPU * XLEN;
    localparam int unsigned FRAGS_PER_REG = VPU_VLEN / DW;
    localparam int unsigned FRAG_MAX      = FRAGS_PER_REG * VPU_LMUL_MAX;
    localparam int unsigned FRAG_CNT_W    = $clog2(FRAG_MAX) + 1;
    localparam int unsigned FRAG_MSK_W    = FRAG_MAX;
    localparam int unsigned REG_OFF_W     = $clog2(VPU_LMUL_MAX) + 1;

    typedef struct packed { 
        logic [FRAG_CNT_W-1:0]   frag_idx;
        logic                    is_last;   
        vl_t                     elements;
        logic [4:0]              dispatch_vd;  
        logic [4:0]              dispatch_vs1; 
        logic [4:0]              dispatch_vs2; 
    } dispatch_sideband_t;

    ///////////////////
    // XIF Interface //
    ///////////////////

    typedef struct packed {
        x_issue_t instr_issue;
        vec_instr_e vec_instr; 
    } vpu_issue_t;

    typedef struct packed {
        x_issue_t            instr_issue;
        vpu_decoded_t        instr_decoded;
        dispatch_sideband_t  instr_fragment;
    } vpu_compl_issue_t;

    typedef struct packed {
        x_issue_fifo_res_t   xif_fifo_result;
        vpu_decoded_t        instr_decoded;
        dispatch_sideband_t  instr_fragment;
    } vpu_issue_fifo_res_t;

    ////////////////
    // Arithmetic //
    ////////////////

    typedef struct packed {
        logic sew8;
        logic sew16;
        logic sew32;  
    } operation_valid_t;
    
    typedef struct packed {
        logic[7:0]  e8;
        logic[15:0] e16;
        logic[31:0] e32;  
    } red_acc_t;

    function automatic int get_sew_bits(input sew_e SEW);
        case (SEW)
            SEW_8:  return 8;
            SEW_16: return 16;
            SEW_32: return 32;
            default: return 32;
        endcase
    endfunction

    function automatic int get_lane_limit(input sew_e SEW, input int unsigned vl);
        case (SEW)
            SEW_8: begin
                if      (vl <= 4)  return 1;
                else if (vl <= 8)  return 2;
                else if (vl <= 12) return 3;
                else               return 4;
            end
            SEW_16: begin
                if      (vl <= 2)  return 1;
                else if (vl <= 4)  return 2;
                else if (vl <= 6)  return 3;
                else               return 4;
            end
            default: begin 
                if (vl <= 1)       return 1;
                else if (vl <= 2)  return 2;
                else if (vl <= 3)  return 3;
                else               return 4;
            end
        endcase
    endfunction   
    
endpackage
