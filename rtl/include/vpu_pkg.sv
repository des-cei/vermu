// [STATIC] --> design-time
// [FIXED]  --> defined by specification
// [DYNAMIC]--> by user

package vpu_pkg;

    import rvv_instr_pkg::*;
    import vector_ops_pkg::*;

    ////////////////
    // Parameters //
    ////////////////
               
    localparam int unsigned XLEN = 32;  //[FIXED]
    typedef logic [XLEN-1:0] xlen_t;    
    
    // Maximum size of a single vector element in bits (ELEN ≥ 8)[FIXED]
    localparam int unsigned ELEN   = 32;       

    typedef logic [31:0] elen_t;    
    
    // Number of bits in a vector register (in each of 32 registers). Min 32. [STATIC]
    localparam int unsigned VLEN   = 128;	             
    
    typedef logic [VLEN-1:0] vlen_t;                    

    localparam int unsigned VLENB  = VLEN / 8; 
                   
    // Selected element width [DYNAMIC]
    localparam int unsigned SEW = 32; 	

    // Number of vector registers (RV32I) [FIXED]
    localparam int unsigned NRVREG = 32;

    typedef logic [$clog2(NRVREG)-1:0] vreg_t;
    typedef logic[$clog2(NRVREG)-1:0] addr_t;
	
    // Maximum vector length in elements 
    localparam int unsigned MAXVL  = VLEN / 8; 

    typedef logic [$clog2(MAXVL+1)-1:0] vl_t;      

    //////////////////
    //  Definitions //
    //////////////////

    // SEW: selected element width.(8,16,32)
    typedef enum logic [2:0] {
        SEW_8  = 3'b000,
        SEW_16 = 3'b001,
        SEW_32 = 3'b010
    } vsew_e;

    typedef enum logic [2:0] {
        LMUL_F4 = 3'b110,
        LMUL_F2 = 3'b111,
        LMUL_1  = 3'b000,
        LMUL_2  = 3'b001,
        LMUL_4  = 3'b010,
        LMUL_8  = 3'b011
    } vlmul_e;

    typedef enum logic [6:0] {   
        load_fp  = 7'b0000111,    
        store_fp = 7'b0100111,    
        op_v     = 7'b1010111,    
        system   = 7'b1110011     
    } major_opcode_e;
    
    //Operand type and source locations
    typedef enum logic [3:0] {
        OPIVV        = 4'b0000, 
        OPFVV_CSRRW  = 4'b0001, //--N/A
        OPMVV_CSRRS  = 4'b0010, 
        OPIVI_CSRRC  = 4'b0011, //imm[4:0]
        OPIVX        = 4'b0100, //GPR x, rs1
        OPFVF_CSRRWI = 4'b0101, //--N/A
        OPMVX_CSRRSI = 4'b0110, //GPR x, rs1
        OPCFG_CSRRCI = 4'b0111, //GPR x, rs1 & rs2/imm. 311p. Format under OP-V opcode? vsetvli, vsetvl
        NOP_FUNCT3   = 4'b1000
    } encode_funct3_e;

    typedef enum logic [2:0] {
        W_8  = 3'b000,
        W_16 = 3'b101,
        W_32 = 3'b110
    } width_e;
    
    ////////////
    //  CSRs  //
    ////////////

    typedef logic [XLEN-1:0] vstart_t;
    
    // typedef enum logic [1:0] {
    //     RNU = 2'b00,
    //     RNE = 2'b01,
    //     RDN = 2'b10,
    //     ROD = 2'b11
    // } vxrm_e;

    // typedef struct packed {
    //     vxrm_e vxrm;
    //     logic  vxsat;
    // } vcsr_t;
    
    typedef struct packed {
        logic   vill;
        logic   vma;
        logic   vta;
        vsew_e  vsew;
        vlmul_e vlmul;
    } vtype_t;

    typedef struct packed {
        opcode_t        opcode;
        major_opcode_e  mopcode; 
        encode_funct3_e funct3;
        
        
        addr_t          vd;
        addr_t          vs1;
        addr_t          vs2;

        elen_t          rd;
        elen_t          rs1;
        elen_t          rs2;        

        logic           vm;
        logic [5:0]     funct6;

        //Load/Store
        width_e         width;
        addr_t          lumop;
        logic [1:0]     mop;
        logic           mew;
        logic [2:0]     nf;

        //CSRS config
        vtype_t csr_vtype;

        vlen_t rs_rdata1;
        logic  use_data1;
        logic  use_data2;
        logic  is_signed;
        logic  is_vmv_nr;
        logic  is_writeback;
    } vpu_req_t;


    typedef enum logic {
        S_IDLE, 
        S_BUSY
    } xif_fsm_e;

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

    /////////////////////
    // Functionalities //
    /////////////////////

    function automatic int get_sew_bits(input vsew_e SEW);
        case (SEW)
            SEW_8:  return 8;
            SEW_16: return 16;
            SEW_32: return 32;
            default: return 32;
        endcase
    endfunction

    function automatic int get_eew_bits(input width_e WIDTH);
        unique case (WIDTH)
            W_8:  return 8;
            W_16: return 16;
            W_32: return 32;
            default: return 32;
        endcase
    endfunction

    function automatic int get_lane_limit(input vsew_e SEW, input int unsigned vl);
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

    function automatic int int_lmul(input vlmul_e vlmul, input logic vtype_supported);
        unique case (vlmul) 
        LMUL_F4: int_lmul = 1;   // 1/4 LMUL
        LMUL_F2: int_lmul = 2;   // 1/2 LMUL
        LMUL_1:  int_lmul = 4;   // 1 LMUL
        default: begin 
            vtype_supported = 1'b0;
            int_lmul = 0;
        end
        endcase
    endfunction
    
    function automatic int get_nreg(input opcode_t op);
        unique case (op)
            VMV1R_V: get_nreg = 1;
            VMV2R_V: get_nreg = 2;
            VMV4R_V: get_nreg = 4;
            VMV8R_V: get_nreg = 8;
            default: get_nreg = 0;
        endcase
    endfunction



endpackage