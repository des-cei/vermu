// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module simd_controller 
    import vpu_pkg::*; 
    import vector_ops_pkg::*;
(
    input  logic  clk_i,
    input  logic  rst_ni,
    input  op_e   operation_i,
    input  logic  operation_valid_i, 
    input  vlen_t op_s1_i,
    input  vlen_t op_s2_i,
    input  vlen_t op_d_i,
    input  logic  is_signed_i,
    input  logic  carry_i,
    input  vl_t   vl_i,            
	input  vsew_e sew_i,
    output vlen_t result_o,
    output logic  result_valid_o
);

    red_acc_t red_acc;

    localparam int NUM_LANES = VLEN / 32;

    logic [NUM_LANES-1:0][31:0] lane_op_s1;
    logic [NUM_LANES-1:0][31:0] lane_op_s2;
    logic [NUM_LANES-1:0][31:0] lane_d;
    logic [NUM_LANES-1:0][31:0] lane_result;
    logic [NUM_LANES-1:0]       lane_result_valid;

    //SIMD Block generation
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_lanes
            VAU_lanes i_VAU_lane (
                .clk_i            (clk_i),
                .rst_ni           (rst_ni),
                .operation_i      (operation_i),
                .operation_valid_i(operation_valid_i),
                .op_s1_i          (lane_op_s1[i]), 
                .op_s2_i          (lane_op_s2[i]),
                .op_d_i           (lane_d[i]),
                .is_signed_i      (is_signed_i),
                .carry_i          (carry_i),
                .sew_i            (sew_i),
                .result_o         (lane_result[i]),
                .result_valid_o   (lane_result_valid[i])
            );       
        end
    endgenerate


    int lane_limit;
    int sew_bits;
    int bit_index; 
    int lane_idx; 
    int lane_offset; 
    logic lanes_result_valid; 

    always_comb begin
        lane_limit = get_lane_limit(sew_i, vl_i); 
        sew_bits = get_sew_bits(sew_i);
    
        lane_op_s1  = '0;
        lane_op_s2  = '0;
        lane_d      = '0;
        bit_index   = '0;
        lane_idx    = '0;
        lane_offset = '0;

        for (int elem = 0; elem < vl_i; elem++) begin
            bit_index   = elem * sew_bits;  
            lane_idx    = bit_index / 32;   
            lane_offset = bit_index % 32;   
    
            if (lane_idx < NUM_LANES) begin
                case (sew_i)
                    SEW_8: begin
                        lane_op_s1[lane_idx][lane_offset +: 8] = op_s1_i[bit_index +: 8];
                        lane_op_s2[lane_idx][lane_offset +: 8] = op_s2_i[bit_index +: 8];
                        lane_d    [lane_idx][lane_offset +: 8] = op_d_i[bit_index +: 8]; 
                        if(operation_i == VREDSUM) begin
                            lane_op_s1[lane_idx][lane_offset +: 8] = 0;
                            lane_op_s2[lane_idx][lane_offset +: 8] = op_s2_i[bit_index +: 8];
                        end
                    end
                    SEW_16: begin
                        lane_op_s1[lane_idx][lane_offset +: 16] = op_s1_i[bit_index +: 16];
                        lane_op_s2[lane_idx][lane_offset +: 16] = op_s2_i[bit_index +: 16];
                        lane_d    [lane_idx][lane_offset +: 16] = op_d_i[bit_index +: 16];
                        if(operation_i == VREDSUM) begin
                            lane_op_s1[lane_idx][lane_offset +: 16] = 0;
                            lane_op_s2[lane_idx][lane_offset +: 16] = op_s2_i[bit_index +: 16];
                        end
                    end
                    SEW_32: begin
                        lane_op_s1[lane_idx][lane_offset +: 32] = op_s1_i[bit_index +: 32];
                        lane_op_s2[lane_idx][lane_offset +: 32] = op_s2_i[bit_index +: 32];
                        lane_d    [lane_idx][lane_offset +: 32] = op_d_i[bit_index +: 32];
                        if(operation_i == VREDSUM) begin
                            lane_op_s1[lane_idx][lane_offset +: 32] = 0;
                            lane_op_s2[lane_idx][lane_offset +: 32] = op_s2_i[bit_index +: 32];
                        end

                    end
                endcase
            end
        end 

    end
        
    always_comb begin
        lanes_result_valid = 1'b1;
        for (int i = 0; i < NUM_LANES; i++) begin
            lanes_result_valid &= lane_result_valid[i];
        end
    end
    
    assign result_valid_o = lanes_result_valid;
    
  // Assemble final result
    always_comb begin
        red_acc = '0;
        result_o = '0;

        //Masked results
        unique case (operation_i)
            VMSEQ,
            VMSNE,
            VMSLTU,
            VMSLT: begin
                unique case (sew_i)
                    SEW_8: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            result_o[i*4 +: 4] = lane_result[i][3:0];
                        end
                    end
                    SEW_16: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            result_o[i*2 +: 2] = lane_result[i][1:0]; 
                        end
                    end
                    default: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            result_o[i +: 1] = lane_result[i][0];
                        end
                    end
                endcase
            end
            VREDSUM:
                unique case (sew_i)
                    SEW_8: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            for (int e = 0; e < 4; e++) begin
                                red_acc.e8 = red_acc.e8 + lane_result[i][e*8 +: 8];
                            end
                        end
                        result_o[0 +: 8] = op_s1_i[0 +: 8] + red_acc.e8;
                    end
                    SEW_16: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            for (int e = 0; e < 2; e++) begin
                                red_acc.e16 += lane_result[i][e*16 +: 16];
                            end
                        end

                        result_o[0 +: 16] = op_s1_i[0 +: 16]  + red_acc.e16[0 +: 16]; 
                    end 
                    default: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            red_acc.e32 += lane_result[i]; 
                        end

                        result_o[0 +: 32] = op_s1_i[0 +: 32] + red_acc.e32;

                    end
                endcase
            default: begin
                for (int i = 0; i < NUM_LANES; i++) begin
                    result_o[i*32 +: 32] = lane_result[i];  
                end
            end
        endcase
    end


endmodule 

