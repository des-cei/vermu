// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Matheus Cavalcante, ETH Zurich
//
// The SIMD lane calculates SIMD operations depending on
// element width.

module vpu_vau  import vpu_pkg::*; import rvv_instr_pkg::*; #(
    parameter int unsigned Width = 8,                        
	parameter type         data_t = logic [Width-1:0]
) (
    input logic   clk_i,
    input logic   rst_ni,
    input op_e    operation_i,
    input logic   operation_valid_i, 
    input data_t  op_s1_i,
    input data_t  op_s2_i,
    input data_t  op_d_i,
    input logic   is_signed_i,  
    input logic   carry_i,
	input sew_e  sew_i,
    output data_t result_o,
    output logic  result_valid_o 	
); 
    int sew_bits;

    ////////////////
    // Multiplier //  op_2 * op_1
    ////////////////	

    logic               is_mult;
    logic [2*Width-1:0] mult_result;
	data_t              mult_op1;
	data_t              mult_op2;
	
    always_comb begin: mult_operands
        mult_op1 = op_s1_i;
        mult_op2 = op_s2_i;
        if (operation_i inside {OP_VMADD, OP_VNMSUB}) begin
           mult_op1 = op_s1_i;
           mult_op2 = op_d_i;
        end
    end: mult_operands

    always_comb begin: multiply
        is_mult = operation_valid_i && operation_i inside {OP_VMACC, OP_VNMSAC, OP_VMADD, OP_VMUL, OP_VMULH, OP_VMULHU, OP_VMULHSU};
        
        mult_result = '0;
        if (is_mult)
            mult_result = $signed({mult_op1[Width-1] & is_signed_i & ~(operation_i == OP_VMULHSU), mult_op1}) * $signed({mult_op2[Width-1] & is_signed_i, mult_op2});
    end: multiply

    ////////////////////////
    // Adder / Subtractor //    op_2 - op_1
    ////////////////////////
    
    logic  [Width:0] adder_result;
    logic  [Width:0] subtractor_result;
    data_t           simd_result;
    data_t           arith_op1;        
    data_t           arith_op2;        
    
    always_comb begin : arith_operands
        if(operation_valid_i) 
           unique case (operation_i)   
                OP_VMACC,
                OP_VNMSAC: begin
                    arith_op1 = mult_result[Width-1:0];                    
                    arith_op2 = op_d_i;
                end
                OP_VMADD: begin
                    arith_op1 = mult_result[Width-1:0];
                    arith_op2 = op_s2_i;
                end
                OP_VRSUB: begin
                    arith_op1 = op_s2_i;
                    arith_op2 = op_s1_i;
                end                
                default: begin   
                    arith_op1 = op_s1_i;	
                    arith_op2 = op_s2_i;	
               end
           endcase 
        else begin 
            arith_op1 = op_s1_i;
            arith_op2 = op_s2_i;
        end
    end        
    
    assign adder_result      = operation_valid_i ? $signed(arith_op2) + $signed(arith_op1) + carry_i : '0;
    assign subtractor_result = operation_valid_i ? $signed(arith_op2) - $signed(arith_op1) - carry_i : '0;

    
    /////////////
    // Shifter //
    /////////////  
    
    logic                     is_shift;
    logic [Width-1:0]         shift_operand; 
    logic [$clog2(Width)-1:0] shift_amount;  
	    
    always_comb begin : shifter
        is_shift = operation_valid_i && operation_i inside {OP_VSLL, OP_VSRL, OP_VSRA};
        if(is_shift) begin
            if (Width == 32) begin   
                unique case (sew_i)
                    vpu_pkg::SEW_32: begin
                        shift_amount = op_s1_i[4:0];
                        if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i);
                        else shift_operand = $unsigned(op_s2_i);
                    end
                    vpu_pkg::SEW_16: begin
                        shift_amount = op_s1_i[3:0];
                        if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i[15:0]);
                        else shift_operand                     = $unsigned(op_s2_i[Width-1:0]);
                    end
                    default: begin
                        shift_amount = op_s1_i[2:0];
                        if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i[15:0]);
                        else shift_operand = $unsigned(op_s2_i[Width-1:0]);
                    end
                endcase
            end else if (Width == 16) begin 
                unique case (sew_i)
                    vpu_pkg::SEW_16: begin
                        shift_amount = op_s1_i[3:0];
                        if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i);
                        else shift_operand = $unsigned(op_s2_i);
                    end
                    default: begin
                        shift_amount = op_s1_i[2:0];
                        if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i[7:0]);
                        else shift_operand = $unsigned(op_s2_i[7:0]);
                    end
                endcase
            end else begin
                if (op_s1_i > 'd8) shift_amount = 'd8;  
                else shift_amount = op_s1_i[2:0];
                if (operation_i == OP_VSRA) shift_operand = $signed(op_s2_i);
                else shift_operand = $unsigned(op_s2_i);
            end
        end
       
    end 

    /////////////
    // Compare //    op_2 < op_1
    /////////////	

    data_t comp_result; 
    data_t comp_op_1;
    data_t comp_op_2;
    
    always_comb begin: comp_operands
        if(operation_i inside {OP_VMSGTU, OP_VMSGT, OP_VMSGEU, OP_VMSGE}) begin
            comp_op_1 = op_s2_i;
            comp_op_2 = op_s1_i;
        end
        else begin
            comp_op_1 = op_s1_i;
            comp_op_2 = op_s2_i;
        end
    end: comp_operands

    always_comb begin: compare     
        if(operation_valid_i) 
            unique case (operation_i)
                OP_VMSEQ        : comp_result = ~|subtractor_result;	
                OP_VMSNE        : comp_result = |subtractor_result; 
                OP_VMSLTU, OP_VMSLT, OP_VMSGTU, OP_VMSGT: comp_result = is_signed_i ? ($signed(comp_op_2) < $signed(comp_op_1)) : (comp_op_2 < comp_op_1); 
                OP_VMSLEU, OP_VMSLE, OP_VMSGEU, OP_VMSGE: comp_result = {'0, is_signed_i ? ($signed(comp_op_2) <= $signed(comp_op_1)) : (comp_op_2 <= comp_op_1)};
                default: comp_result = '0;
            endcase
    end: compare

    ////////////
    // Result // 
    ////////////

    always_comb begin : simd
        simd_result    = '0;
        result_valid_o = 1'b0;
        sew_bits = get_sew_bits(sew_i);
        if (operation_valid_i) begin
            result_valid_o = 1'b1;  
            unique case (operation_i)
                OP_VADD, OP_VMACC, OP_VMADD, OP_VREDSUM   : simd_result = adder_result[Width-1:0];
                OP_VSUB, OP_VRSUB, OP_VNMSAC              : simd_result = subtractor_result[Width-1:0];
                OP_VMIN, OP_VMINU                         : simd_result = $signed({op_s1_i[Width-1] & is_signed_i, op_s1_i}) <= $signed({op_s2_i[Width-1] & is_signed_i, op_s2_i}) ? op_s1_i : op_s2_i;
                OP_VMAX, OP_VMAXU                         : simd_result = $signed({op_s1_i[Width-1] & is_signed_i, op_s1_i}) > $signed({op_s2_i[Width-1] & is_signed_i, op_s2_i}) ? op_s1_i : op_s2_i;
                OP_VAND                                   : simd_result = op_s1_i & op_s2_i;
                OP_VOR                                    : simd_result = op_s1_i | op_s2_i;
                OP_VXOR                                   : simd_result = op_s1_i ^ op_s2_i;
                OP_VSLL                                   : simd_result = shift_operand << shift_amount;
                OP_VSRL                                   : simd_result = shift_operand >> shift_amount;
                OP_VSRA                                   : simd_result = $signed(shift_operand) >>> shift_amount;   
                OP_VMUL                                   : simd_result = mult_result[Width-1:0];
                OP_VMULH, OP_VMULHU, OP_VMULHSU           : begin
                    simd_result = mult_result[2*Width-1:Width];
                    if (Width == 32) begin
                        unique case (sew_i)
                            SEW_8:   simd_result = mult_result[8 +: 8];
                            SEW_16:  simd_result = mult_result[31:16];
                            default: simd_result = mult_result[63:32]; 
                        endcase 
                    end else if (Width == 16) begin
                        unique case (sew_i)
                            SEW_8:    simd_result = mult_result[15:8];
                            default:  simd_result = mult_result[31:16];
                        endcase 
                        
                    end else if (Width == 8) begin
                        simd_result = mult_result[15:8];
                    end
                end
                OP_VMSEQ, OP_VMSNE,
                OP_VMSLTU, OP_VMSLT, OP_VMSLEU, OP_VMSLE, 
                OP_VMSGTU, OP_VMSGT, OP_VMSGEU, OP_VMSGE    : simd_result = comp_result[Width-1:0];		              
                OP_VMADC                                    : simd_result = Width'(adder_result[Width]);				
                default: simd_result = '0;
            endcase 
        end
    end 
    
    assign result_o = simd_result;
    
endmodule : vpu_vau 