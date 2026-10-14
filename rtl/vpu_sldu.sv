// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_sldu 
    import vpu_pkg::*; 
    import rvv_instr_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,
    input  dw_t  op_s1_i,
    input  dw_t  op_s2_i,
    output dw_t  result_o,
    if_xif_exe.exe_unit if_exe_wrapper
);
    logic                  req_valid, is_last, result_valid;
    logic [FRAG_CNT_W-1:0] frag_idx;
    vl_t                   iter_vl;
    vec_instr_e            instr;
    sew_e                  sew;
    vl_t                   csr_vl;

    assign req_valid = if_exe_wrapper.wrapper_exe_instr_valid;
    assign is_last   = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.is_last; 
    assign frag_idx  = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.frag_idx; 
    assign iter_vl   = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.elements; 
    assign instr     = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.instr_enum;
    assign sew       = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vtype.vsew;
    assign csr_vl    = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vl;

    dw_t         op_s1;
    logic [31:0] scalar_val, result_data;

    always_comb begin : op1_assignation
        op_s1 = '0;
        scalar_val = '0;
        unique case (if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.fmt)
            FMT_OPMVV_CSRRS: begin
                scalar_val = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.rs1_data; // vmv.x.s
                op_s1 = op_s1_i;                                                            // vmv.v.v
            end
            FMT_OPIVI_CSRRC,                                                                // vmv.v.i
            FMT_OPIVX,                                                                      // vmv.v.x
            FMT_OPMVX_CSRRSI: begin
                if (if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.fmt == FMT_OPIVI_CSRRC)
                    scalar_val = $signed(if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.imm5);
                else
                    scalar_val = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.rs1_data; 
                
                unique case (sew)
                    SEW_8:  for (int i = 0; i < iter_vl; i++) op_s1[i*8 +: 8] = scalar_val[7:0];
                    SEW_16: for (int i = 0; i < iter_vl; i++) op_s1[i*16 +: 16] = scalar_val[15:0];
                    default: for (int i = 0; i < iter_vl; i++) op_s1[i*32 +: 32] = scalar_val[31:0];
                endcase

            end

            // FMT_OPIVV
            // FMT_OPMVV_CSRRS
            // FMT_OPCFG_CSRRCI
            default: op_s1 = op_s1_i;  // vmv.s.x ? 
        endcase
    end

    int sew_bits;
    int bit_index; 
    int lane_idx; 
    
    always_comb begin
        sew_bits = get_sew_bits(sew);
        bit_index = '0;

        result_data  = '0;
        result_o     = '0;
        result_valid = '0;
        if (req_valid) begin
            unique case (instr)
                VMV_XS: begin
                    if (frag_idx == 0) begin
                        unique case (sew)
                            SEW_8: begin
                                result_data = {{24{op_s2_i[7]}}, op_s2_i[7:0]};
                            end
                            SEW_16: begin
                                result_data = {{16{op_s2_i[15]}}, op_s2_i[15:0]};
                            end
                            SEW_32: begin
                                result_data = {op_s2_i[31:0]};
                            end
                            default:;
                        endcase
                        result_valid = 1'b1;
                    end
                end
                VMV_SX: begin
                    if (frag_idx == 0) begin
                        if (csr_vl != 0) begin
                            unique case (sew)
                                SEW_8: begin
                                    result_o[7:0] = scalar_val[7:0];
                                end
                                SEW_16: begin
                                    result_o[15:0] = scalar_val[15:0];
                                end
                                SEW_32: begin
                                    result_o[31:0] = scalar_val[31:0];
                                end
                                default:;
                            endcase
                        end
                        result_valid = 1'b1;
                    end
                end
                VMV_VV,
                VMV_VX,
                VMV_VI: begin
                    for (int elem = 0; elem < iter_vl; elem++) begin
                        bit_index   = elem * sew_bits;  
                        lane_idx    = bit_index / 32;   
                        unique case (sew)
                            SEW_8:  result_o[bit_index +:  8] = op_s1[bit_index +:  8];
                            SEW_16: result_o[bit_index +: 16] = op_s1[bit_index +: 16];
                            SEW_32: result_o[bit_index +: 32] = op_s1[bit_index +: 32];
                            default: ; 
                        endcase
                    end
                    result_valid = 1'b1;
                end 
                VMVNRR_V:begin
                    result_o = op_s2_i;
                    result_valid = 1'b1;
                end
                default: ;
            endcase 
        end
    end

    // Output to XIF wrapper
    assign if_exe_wrapper.exe_wrapper_recv_instr_ready                             = 1'b1;               // TODO: Ready for new instruction
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_valid_exec_o   = result_valid; // Instruction finished
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_data_exec_o    = result_data;        // TODO ?  
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.req      = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.req;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.resp     = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.resp;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.register = '0;                 // TODO ?

    assign if_exe_wrapper.exe_wrapper_result.instr_decoded = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded;
    assign if_exe_wrapper.exe_wrapper_result.instr_fragment= if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment;
endmodule