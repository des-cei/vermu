// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Matheus Cavalcante, ETH Zurich
//
// The SIMD lane calculates SIMD operations depending on
// element width.

module VAU  import vpu_pkg::*; import vector_ops_pkg::*; #(
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
	input vsew_e  sew_i,
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
        if (operation_i inside {VMADD, VNMSUB}) begin
           mult_op1 = op_s1_i;
           mult_op2 = op_d_i;
        end
    end: mult_operands

    always_comb begin: multiply
        is_mult = operation_valid_i && operation_i inside {VMACC, VNMSAC, VMADD, VMUL, VMULH, VMULHU, VMULHSU};
        
        mult_result = '0;
        if (is_mult)
            mult_result = $signed({mult_op1[Width-1] & is_signed_i & ~(operation_i == VMULHSU), mult_op1}) * $signed({mult_op2[Width-1] & is_signed_i, mult_op2});
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
                VMACC,
                VNMSAC: begin
                    arith_op1 = mult_result[Width-1:0];                    
                    arith_op2 = op_d_i;
                end
                VMADD: begin
                    arith_op1 = mult_result[Width-1:0];
                    arith_op2 = op_s2_i;
                end
                VRSUB: begin
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
        is_shift = operation_valid_i && operation_i inside {VSLL, VSRL,VSRA};
        if(is_shift) begin
            if (Width == 32) begin   
                unique case (sew_i)
                    vpu_pkg::SEW_32: begin
                        shift_amount = op_s1_i[4:0];
                        if (operation_i == VSRA) shift_operand = $signed(op_s2_i);
                        else shift_operand = $unsigned(op_s2_i);
                    end
                    vpu_pkg::SEW_16: begin
                        shift_amount = op_s1_i[3:0];
                        if (operation_i == VSRA) shift_operand = $signed(op_s2_i[15:0]);
                        else shift_operand                     = $unsigned(op_s2_i[Width-1:0]);
                    end
                    default: begin
                        shift_amount = op_s1_i[2:0];
                        if (operation_i == VSRA) shift_operand = $signed(op_s2_i[15:0]);
                        else shift_operand = $unsigned(op_s2_i[Width-1:0]);
                    end
                endcase
            end else if (Width == 16) begin 
                unique case (sew_i)
                    vpu_pkg::SEW_16: begin
                        shift_amount = op_s1_i[3:0];
                        if (operation_i == VSRA) shift_operand = $signed(op_s2_i);
                        else shift_operand = $unsigned(op_s2_i);
                    end
                    default: begin
                        shift_amount = op_s1_i[2:0];
                        if (operation_i == VSRA) shift_operand = $signed(op_s2_i[7:0]);
                        else shift_operand = $unsigned(op_s2_i[7:0]);
                    end
                endcase
            end else begin
                if (op_s1_i > 'd8) shift_amount = 'd8;  
                else shift_amount = op_s1_i[2:0];
                if (operation_i == VSRA) shift_operand = $signed(op_s2_i);
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
        if(operation_i inside {VMSGTU, VMSGT, VMSGEU, VMSGE}) begin
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
                VMSEQ        : comp_result = ~|subtractor_result;	
                VMSNE        : comp_result = |subtractor_result; 
                VMSLTU, VMSLT, VMSGTU, VMSGT: comp_result = is_signed_i ? ($signed(comp_op_2) < $signed(comp_op_1)) : (comp_op_2 < comp_op_1); 
                VMSLEU, VMSLE, VMSGEU, VMSGE: comp_result = {'0, is_signed_i ? ($signed(comp_op_2) <= $signed(comp_op_1)) : (comp_op_2 <= comp_op_1)};
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
                VADD, VMACC, VMADD, VREDSUM      : simd_result = adder_result[Width-1:0];
                VSUB, VRSUB, VNMSAC              : simd_result = subtractor_result[Width-1:0];
                VMIN, VMINU                      : simd_result = $signed({op_s1_i[Width-1] & is_signed_i, op_s1_i}) <= $signed({op_s2_i[Width-1] & is_signed_i, op_s2_i}) ? op_s1_i : op_s2_i;
                VMAX, VMAXU                      : simd_result = $signed({op_s1_i[Width-1] & is_signed_i, op_s1_i}) > $signed({op_s2_i[Width-1] & is_signed_i, op_s2_i}) ? op_s1_i : op_s2_i;
                VAND                             : simd_result = op_s1_i & op_s2_i;
                VOR                              : simd_result = op_s1_i | op_s2_i;
                VXOR                             : simd_result = op_s1_i ^ op_s2_i;
                VSLL                             : simd_result = shift_operand << shift_amount;
                VSRL                             : simd_result = shift_operand >> shift_amount;
                VSRA                             : simd_result = $signed(shift_operand) >>> shift_amount;   
                VMUL                             : simd_result = mult_result[Width-1:0];
                VMULH, VMULHU, VMULHSU           : begin
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
                VMSEQ, VMSNE,
                VMSLTU, VMSLT, VMSLEU, VMSLE, 
                VMSGTU, VMSGT, VMSGEU, VMSGE    : simd_result = comp_result[Width-1:0];		              
                VMADC                           : simd_result = Width'(adder_result[Width]);				
                default: simd_result = '0;
            endcase 
        end
    end 
    
    assign result_o = simd_result;
    
endmodule : VAU 