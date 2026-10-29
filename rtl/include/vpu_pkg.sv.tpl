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
    
    // Number of bits in a vector register (in each of 32 registers). Min 32. [DESIGN]
    localparam int unsigned VPU_VLEN = @VPU_VLEN@;             
    
    // Number of Integer Processing Units [DESIGN]
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
        // TODO: LMUL_F8
        LMUL_F4 = 3'b110,
        LMUL_F2 = 3'b111,
        LMUL_1  = 3'b000,
        LMUL_2  = 3'b001,
        LMUL_4  = 3'b010,
        LMUL_8  = 3'b011
    } lmul_e;

    // Source formats
    typedef enum logic [6:0] {   
        OPCODE_NONE   = 7'h0,
        OPCODE_LOAD   = 7'h7,             
        OPCODE_STORE  = 7'h27,            
        OPCODE_OP_V   = 7'h57,
        OPCODE_SYSTEM = 7'h73                   
    } major_opcode_e;
    
    //Operand type for OP-V instructions and operand-format 
    typedef enum logic [2:0] {
        FMT_OPIVV        = 3'b000, 
        FMT_OPFVV_CSRRW  = 3'b001,  // N/A
        FMT_OPMVV_CSRRS  = 3'b010,
        FMT_OPIVI_CSRRC  = 3'b011,
        FMT_OPIVX        = 3'b100,
        FMT_OPFVF_CSRRWI = 3'b101, // N/A
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
        logic          is_permutation;
        logic          is_reduction;
        logic          is_widening;
        logic          is_narrowing;
        sew_e          eew;
        lmul_e         emul;
        logic          vd_wide;         // vd EEW = 2*SEW, EMUL = 2 * LMUL
        logic          vs2_wide;        // vs2 EEW = 2*SEW, EMUL = 2 * LMUL 
        sew_e          eew_vd, eew_vs2, eew_vs1;
        lmul_e         emul_vd, emul_vs2, emul_vs1;
        logic [1:0]    sh_vd;           // log2(eew / eew_op): operand advances one row every 2^sh frags
        logic [1:0]    sh_vs1;
        logic [1:0]    sh_vs2;
        logic          vs1_sext;        // sign- (1) or zero-extend (0) a narrow source
        logic          vs2_sext;
        // logic          ew_illegal;      // illegal EEW/EMUL or register group overlap
        logic          uses_vs1;
        logic          uses_vs2;
        logic          uses_vd_src;
        logic          uses_rs1_scalar;
        logic          uses_rs2_scalar;
        logic          uses_imm;                         
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
    localparam int unsigned ROW_W         = (FRAGS_PER_REG > 1) ? $clog2(FRAGS_PER_REG) : 1;
    localparam int unsigned SEL_W         = 2;   // sub-row slice select (EEW ratio up to 4)

    typedef struct packed { 
        logic [FRAG_CNT_W-1:0]   next_frag;         // global set counter
        logic                    is_last;   
        // logic [FRAG_CNT_W-1:0]   frag_idx;
        vl_t                     elem_base;         // global index of first element processed this step
        vl_t                     elements;          // elements processed this step
        logic [4:0]              dispatch_vd;  
        logic [4:0]              dispatch_vs1; 
        logic [4:0]              dispatch_vs2;
        logic [ROW_W-1:0]        row_vd;            // fragment row inside each register
        logic [ROW_W-1:0]        row_vs1;
        logic [ROW_W-1:0]        row_vs2;
        logic [XLEN-1:0]         dispatch_raddr1; 
        logic [FRAG_CNT_W-1:0]   vd_frag;           // global fragment index inside the vd group
        logic                    vd_frag_done;      // this write completes vd_frag (consumers may read it)
        logic                    vd_we;      
        logic [SEL_W-1:0]        sel_vd;            // slice of the row used this step (narrow operands)
        logic [SEL_W-1:0]        sel_vs1;
        logic [SEL_W-1:0]        sel_vs2;        
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

    function automatic int get_eew_bits(input sew_e SEW);
        case (SEW)
            SEW_8:  return 8;
            SEW_16: return 16;
            SEW_32: return 32;
            default: return 32;
        endcase
    endfunction

    function automatic int get_width_bits(input logic [2:0] width);
        unique case (width)
            3'b000: return 8;
            3'b101: return 16;
            3'b110: return 32;
            default: return 0;
        endcase
    endfunction

    // Element width of the vd element space: EEW for loads/stores, SEW otherwise
    function automatic sew_e elem_eew(input vpu_decoded_t d);
        if (d.is_load || d.is_store) begin
            unique case (d.width)
                3'b000:  return SEW_8;
                3'b101:  return SEW_16;
                3'b110:  return SEW_32; 
                default: return SEW_32;
            endcase
        end
        // TODO: widen/narrow
        return d.vtype.vsew;
    endfunction

    function automatic vl_t calc_epf(input sew_e vsew);
        vl_t epf;
        case (vsew)
            SEW_8:   epf = vl_t'(DW /  8);  
            SEW_16:  epf = vl_t'(DW / 16);  
            default: epf = vl_t'(DW / 32);
        endcase
        return epf;
    endfunction
    
    // EMUL = (EEW / SEW) * LMUL
    function automatic lmul_e get_emul(
        input logic [2:0] width,
        input sew_e       sew,
        input lmul_e      lmul,
        output logic      illegal
    );
        int sew_bits, width_bits;
        int lmul_units;
        int emul_units;

        illegal  = 1'b0;
        width_bits = get_width_bits(width);
        sew_bits = get_eew_bits(sew);

        unique case (lmul)
            LMUL_F4: lmul_units = 1;
            LMUL_F2: lmul_units = 2;
            LMUL_1:  lmul_units = 4;
            LMUL_2:  lmul_units = 8;
            LMUL_4:  lmul_units = 16;
            LMUL_8:  lmul_units = 32;
            default: begin
                illegal = 1'b1;
                return LMUL_1;
            end
        endcase

        if ((width_bits <= 0) || (sew_bits <= 0)) begin
            illegal = 1'b1;
            return LMUL_1;
        end

        // LMUL is represented in units of 1/4.
        emul_units = (lmul_units * width_bits);

        // A non-integral result is below LMUL_F4 or otherwise unsupported.
        if ((emul_units % sew_bits) != 0) begin
            illegal = 1'b1;
            return LMUL_F4;
        end

        emul_units = emul_units / sew_bits;

        unique case (emul_units)
            1:  return LMUL_F4;
            2:  return LMUL_F2;
            4:  return LMUL_1;
            8:  return LMUL_2;
            16: return LMUL_4;
            32: return LMUL_8;
            default: begin
                // EMUL is smaller than 1/4 or greater than 8.
                illegal = 1'b1;

                // Return a legal value even though illegal is asserted.
                if (emul_units > 32)
                    return LMUL_8;
                else
                    return LMUL_F4;
            end
        endcase
    endfunction

    // 2*SEW
    function automatic sew_e dbl_sew(input sew_e sew, output logic illegal);
        illegal = 1'b0;
        unique case (sew)
            SEW_8:   return SEW_16;
            SEW_16:  return SEW_32;
            default: begin
                illegal = 1'b1;
                return SEW_32;
            end
        endcase
    endfunction

    // 2*LMUL
    function automatic lmul_e dbl_lmul(input lmul_e l, output logic illegal);
        illegal = 1'b0;
        unique case (l)
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

    // log2(eew / eew_op), with eew >= eew_op
    function automatic logic [1:0] eew_shift(input sew_e eew, input sew_e eew_op);
        return 2'(eew - eew_op);
    endfunction

    // Registers in a group (fractional EMUL occupies one register)
    function automatic int unsigned lmul_regs(input lmul_e lmul);
        unique case (lmul)
            LMUL_2:  return 2;
            LMUL_4:  return 4;
            LMUL_8:  return 8;
            default: return 1;
        endcase
    endfunction

    // RVV 5.2: vd may overlap a source of different EEW only in the highest-numbered part of vd
    // (vd wider, source EMUL >= 1) or in the lowest-numbered part of the source (vd narrower) 
    function automatic logic ew_overlap_illegal(input logic [4:0] vd, input sew_e eew_des, input lmul_e emul_des,
                                                input logic [4:0] vs, input sew_e eew_sour, input lmul_e emul_sour);
        int unsigned n_dest, n_sour;
        n_dest = lmul_regs(emul_des);
        n_sour = lmul_regs(emul_sour);
        if (eew_des == eew_sour)                     return 1'b0;
        if ((vs + n_sour <= vd) || (vd + n_dest <= vs)) return 1'b0;
        if (eew_des > eew_sour)
            return !((emul_sour inside {LMUL_1, LMUL_2, LMUL_4, LMUL_8}) && (vs == vd + n_dest - n_sour));
        return (vd != vs);
    endfunction

    // Sign/zero-extend each element of data_s from eew to 2*eew (sh = 1).
    function automatic dw_t ext_op(input dw_t data_s, input sew_e eew, input logic [1:0] sh, input logic sext);
        dw_t data_d;
        data_d = data_s;
        if (sh != '0) begin
            data_d = '0;
            unique case (eew)
                SEW_8:   for (int e = 0; e < DW/16; e++) 
                            data_d[e*16 +: 16] = {{8{sext & data_s[e*8+7]}},    data_s[e*8  +: 8]};
                SEW_16:  for (int e = 0; e < DW/32; e++) 
                            data_d[e*32 +: 32] = {{16{sext & data_s[e*16+15]}}, data_s[e*16 +: 16]};
                default: ;
            endcase
        end
        return data_d;
    endfunction

    // Narrowing: keep the low eew_vd bits of each 2*eew_vd element, packed into the low half
    function automatic dw_t pack_narrow(input dw_t data_s, input sew_e eew_vd);
        dw_t data_d;
        data_d = '0;
        unique case (eew_vd)
            SEW_8:   for (int e = 0; e < DW/16; e++)
                        data_d[e*8  +: 8]  = data_s[e*16 +: 8];
            SEW_16:  for (int e = 0; e < DW/32; e++) 
                        data_d[e*16 +: 16] = data_s[e*32 +: 16];
            default: data_d = data_s;
        endcase
        return data_d;
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
