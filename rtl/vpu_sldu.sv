// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// Future implementation should look for an optimized design that reuses 
// operations if possible instead of a analysing particular instructions.
// disp_decoded_i.is_permutation || disp_decoded_i.is_reduction ||
//  disp_decoded_i.is_widening || disp_decoded_i.is_narrowing

module vpu_sldu 
    import vpu_pkg::*; 
    import rvv_instr_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,
    input  dw_t  op_s1_i,
    input  dw_t  op_s2_i,
    input  dw_t  op_d_i,
    output dw_t  result_o,
    if_xif_exe.exe_unit if_exe_wrapper
);
    logic                  req_valid, is_last, result_valid;
    logic [FRAG_CNT_W-1:0] elem_base;
    logic [FRAG_CNT_W-1:0] next_frag;
    vl_t                   iter_vl;
    vec_instr_e            instr;
    logic                  vm;
    sew_e                  sew;
    vl_t                   csr_vl, vstart;
    logic                  is_reduction;

    assign req_valid    = if_exe_wrapper.wrapper_exe_instr_valid;
    assign is_last      = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.is_last; 
    assign elem_base    = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.elem_base; 
    assign next_frag    = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.next_frag; 
    assign iter_vl      = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment.elements; 
    assign instr        = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.instr_enum;
    assign vm           = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vm;
    assign is_reduction = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.is_reduction;
    assign sew          = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vtype.vsew;
    assign csr_vl       = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vl;
    assign vstart       = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded.vstart;

    dw_t         op_s1;
    logic [31:0] scalar_val, result_data;

    // Reduction accumulator
    logic [31:0] acc_q;
    logic        red_fire;

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
                    SEW_8:   for (int i = 0; i < $bits(dw_t)/8; i++) op_s1[i*8 +: 8] = scalar_val[7:0];
                    SEW_16:  for (int i = 0; i < $bits(dw_t)/16; i++) op_s1[i*16 +: 16] = scalar_val[15:0];
                    default: for (int i = 0; i < $bits(dw_t)/32; i++) op_s1[i*32 +: 32] = scalar_val[31:0];
                endcase
            end

            // FMT_OPIVV
            // FMT_OPMVV_CSRRS
            // FMT_OPCFG_CSRRCI
            default: op_s1 = op_s1_i;  // vmv.s.x ? 
        endcase
    end

    logic [31:0] acc;

    always_comb begin
        automatic int sew_bits;
        automatic int bit_index;

        sew_bits = get_eew_bits(sew);
        bit_index = '0;

        acc = '0;
        result_data  = '0;
        result_o     = '0;
        result_valid = '0;
        if (req_valid) begin
            unique case (instr)
                VMV_XS: begin
                    if (vm) begin
                        if (next_frag == 0) begin   // elem_base?
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
                        end
                        result_valid = 1'b1;
                    end
                end
                VMV_SX: begin
                    if (vm) begin
                        if (next_frag == 0) begin
                            if (csr_vl != 0 && !(vstart >= csr_vl)) begin
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
                        end
                        result_valid = 1'b1;
                    end 
                end
                VMV_VV,
                VMV_VX,
                VMV_VI: begin
                    for (int elem = 0; elem < iter_vl; elem++) begin
                        bit_index   = elem * sew_bits;  
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
                VREDSUM_VS: begin       
                    // # vd[0] = sum( vs1[0] , vs2[*] )
                    unique case (sew)
                        SEW_8: begin
                            acc[7:0] = (next_frag == 0) ? op_s1[7:0] : acc_q[7:0];
                            for (int e = 0; e < DW/8; e++)
                                if (e < iter_vl) acc[7:0] += op_s2_i[e*8 +: 8];
                        end
                        SEW_16: begin
                            acc[15:0] = (next_frag == 0) ? op_s1[15:0] : acc_q[15:0];
                            for (int e = 0; e < DW/16; e++)
                                if (e < iter_vl) acc[15:0] += op_s2_i[e*16 +: 16];
                        end
                        SEW_32: begin
                            acc = (next_frag == 0) ? op_s1[31:0] : acc_q[31:0];
                            for (int e = 0; e < DW/32; e++)
                                if (e < iter_vl) acc += op_s2_i[e*32 +: 32];
                        end
                        default: ;
                    endcase
                    result_o[31:0] = acc;   // only element 0 (SEW bits) is meaningful; rest is 0

                    result_valid   = 1'b1;
                end
                default: ;
            endcase 
        end
    end


    // Count a step only when the result is accepted, so a stalled step isn't added twice
    assign red_fire = req_valid && is_reduction && if_exe_wrapper.wrapper_exe_recv_result_ready;
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)       acc_q <= '0;
        else if (red_fire) acc_q <= acc;
    end

    dispatch_sideband_t res_frag;

    // Output to XIF wrapper
    assign if_exe_wrapper.exe_wrapper_recv_instr_ready                             = 1'b1;         // TODO: Ready for new instruction
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_valid_exec_o   = result_valid; // Instruction finished
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_data_exec_o    = result_data;  // vmv.s.x        
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.req      = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.req;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.resp     = if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.resp;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.register = '0;                 

    assign if_exe_wrapper.exe_wrapper_result.instr_decoded           = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded;

    assign if_exe_wrapper.exe_wrapper_result.instr_fragment = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment;

    // always_comb begin
    //     res_frag = if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment;
    //     if (is_reduction) begin
    //         if (!is_last && (next_frag + 1 < FRAGS_PER_REG)) begin
    //             res_frag.row_vd   = ROW_W'(next_frag + 1);   // pure tail row
    //             res_frag.elements = '0;
    //         end else begin
    //             res_frag.row_vd   = '0;                      // row holding vd[0]
    //             res_frag.elements = is_last ? vl_t'(1) : '0; // vd[0] is written only on the last step
    //         end
    //         // elem_base in vd element space, so merge_write_data's row_g0 is correct
    //         res_frag.elem_base = vl_t'(res_frag.row_vd) * vl_t'(DW / get_eew_bits(sew));
    //     end
    // end

    // assign if_exe_wrapper.exe_wrapper_result.instr_fragment = res_frag;

endmodule