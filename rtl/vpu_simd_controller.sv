// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module simd_controller 
    import vpu_pkg::*; 
    import rvv_instr_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,
    input  dw_t  op_s1_i,
    input  dw_t  op_s2_i,
    input  dw_t  op_d_i,
    input  logic is_signed_i, // TODO : ? 
    input  logic carry_i,     // TODO : ?  
    output dw_t result_o,
    if_xif_exe.exe_unit if_exe_wrapper
);

    op_e operation; 
    // vl_t   vl;
    vl_t   iter_vl;
    sew_e sew;

    assign operation = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.operation;
    // assign vl = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.element; 
    assign iter_vl = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.elements; 
    assign sew = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vtype.vsew;

    dw_t op_s1;
    logic [31:0] scalar_val;

    always_comb begin :op1_assignation
        op_s1 = '0;
        scalar_val = '0;
        unique case(if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.fmt)
            FMT_OPIVI_CSRRC: begin
                scalar_val = $signed(if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.imm5);
                unique case (sew)
                    SEW_8:  for (int i = 0; i < iter_vl; i++) op_s1[i*8 +: 8] = scalar_val[7:0];
                    SEW_16: for (int i = 0; i < iter_vl; i++) op_s1[i*16 +: 16] = scalar_val[15:0];
                    default: for (int i = 0; i < iter_vl; i++) op_s1[i*32 +: 32] = scalar_val[31:0];
                endcase
            end
            FMT_OPIVX,
            FMT_OPMVX_CSRRSI: begin
                scalar_val = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.rs1_data;
                unique case (sew)
                    SEW_8:  for (int i = 0; i < iter_vl; i++) op_s1[i*8 +: 8] = scalar_val[7:0];
                    SEW_16: for (int i = 0; i < iter_vl; i++) op_s1[i*16 +: 16] = scalar_val[15:0];
                    default: for (int i = 0; i < iter_vl; i++) op_s1[i*32 +: 32] = scalar_val[31:0];
                endcase
            end
            default: op_s1 = op_s1_i;
        endcase
    end

    red_acc_t red_acc;

    // localparam int NUM_LANES = VPU_VLEN / 32;
    localparam int NUM_LANES = VPU_N_IPU;

    logic [NUM_LANES-1:0][31:0] lane_op_s1;
    logic [NUM_LANES-1:0][31:0] lane_op_s2;
    logic [NUM_LANES-1:0][31:0] lane_d;
    logic [NUM_LANES-1:0][31:0] lane_result;
    logic [NUM_LANES-1:0]       lane_result_valid;


    //SIMD Block generation
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_lanes
            vpu_simd_block i_simd_block (
                .clk_i            (clk_i),
                .rst_ni           (rst_ni),
                .operation_i      (operation),
                .operation_valid_i(if_exe_wrapper.wrapper_exe_instr_valid),
                .op_s1_i          (lane_op_s1[i]), 
                .op_s2_i          (lane_op_s2[i]),
                .op_d_i           (lane_d[i]),
                .is_signed_i      (is_signed_i),
                .carry_i          (carry_i),
                .sew_i            (sew),
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
        lane_limit = get_lane_limit(sew, iter_vl); 
        sew_bits = get_sew_bits(sew);
    
        lane_op_s1  = '0;
        lane_op_s2  = '0;
        lane_d      = '0;
        bit_index   = '0;
        lane_idx    = '0;
        lane_offset = '0;

        for (int elem = 0; elem < iter_vl; elem++) begin
            bit_index   = elem * sew_bits;  
            lane_idx    = bit_index / 32;   
            lane_offset = bit_index % 32;   
    
            if (lane_idx < NUM_LANES) begin
                case (sew)
                    SEW_8: begin
                        lane_op_s1[lane_idx][lane_offset +: 8] = op_s1[bit_index +: 8];
                        lane_op_s2[lane_idx][lane_offset +: 8] = op_s2_i[bit_index +: 8];
                        lane_d    [lane_idx][lane_offset +: 8] = op_d_i[bit_index +: 8]; 
                        if(operation == OP_VREDSUM) begin
                            lane_op_s1[lane_idx][lane_offset +: 8] = 0;
                            lane_op_s2[lane_idx][lane_offset +: 8] = op_s2_i[bit_index +: 8];
                        end
                    end
                    SEW_16: begin
                        lane_op_s1[lane_idx][lane_offset +: 16] = op_s1[bit_index +: 16];
                        lane_op_s2[lane_idx][lane_offset +: 16] = op_s2_i[bit_index +: 16];
                        lane_d    [lane_idx][lane_offset +: 16] = op_d_i[bit_index +: 16];
                        if(operation == OP_VREDSUM) begin
                            lane_op_s1[lane_idx][lane_offset +: 16] = 0;
                            lane_op_s2[lane_idx][lane_offset +: 16] = op_s2_i[bit_index +: 16];
                        end
                    end
                    SEW_32: begin
                        lane_op_s1[lane_idx][lane_offset +: 32] = op_s1[bit_index +: 32];
                        lane_op_s2[lane_idx][lane_offset +: 32] = op_s2_i[bit_index +: 32];
                        lane_d    [lane_idx][lane_offset +: 32] = op_d_i[bit_index +: 32];
                        if(operation == OP_VREDSUM) begin
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
        
  // Assemble final result
    always_comb begin
        red_acc = '0;
        result_o = '0;

        //Masked results
        unique case (operation)
            OP_VMSEQ,
            OP_VMSNE,
            OP_VMSLTU,
            OP_VMSLT: begin
                unique case (sew)
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
            OP_VREDSUM:
                unique case (sew)
                    SEW_8: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            for (int e = 0; e < 4; e++) begin
                                red_acc.e8 = red_acc.e8 + lane_result[i][e*8 +: 8];
                            end
                        end
                        result_o[0 +: 8] = op_s1[0 +: 8] + red_acc.e8;
                    end
                    SEW_16: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            for (int e = 0; e < 2; e++) begin
                                red_acc.e16 += lane_result[i][e*16 +: 16];
                            end
                        end

                        result_o[0 +: 16] = op_s1[0 +: 16]  + red_acc.e16[0 +: 16]; 
                    end 
                    default: begin
                        for (int i = 0; i < NUM_LANES; i++) begin
                            red_acc.e32 += lane_result[i]; 
                        end

                        result_o[0 +: 32] = op_s1[0 +: 32] + red_acc.e32;

                    end
                // TODO: add other reduction operations
                endcase
            default: begin
                for (int i = 0; i < NUM_LANES; i++) begin
                    result_o[i*32 +: 32] = lane_result[i];  
                end
            end
        endcase
    end

    // Output to XIF wrapper
    assign if_exe_wrapper.exe_wrapper_recv_instr_ready                             = 1'b1; // TODO: Ready for new instruction
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_valid_exec_o   = lanes_result_valid;    //Instruction finished
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_data_exec_o    = '0; // TODO ?  
    // assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_data_exec_o    = result_o[31:0];
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.req      = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.req;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.resp     = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.resp;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.register = '0; // TODO?

    assign if_exe_wrapper.exe_wrapper_result.instr_decoded = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded;
    assign if_exe_wrapper.exe_wrapper_result.instr_fragment= if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment;

endmodule 

