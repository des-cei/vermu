// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_vregfile
    import vpu_pkg::*;
(
    input logic clk_i,
    input logic rst_ni,

    input  dw_t wdata_i [2:0],
    output dw_t rdata1_o [2:0],
    output dw_t rdata2_o [2:0],
    output dw_t rdata_vd_o [2:0],

    if_xif_exe.register_file if_monitor_valu,
    if_xif_exe.register_file if_monitor_vlsu,
    if_xif_exe.register_file if_monitor_vsld
);

    // logic [NRVREG-1:0][VPU_VLEN-1:0] vreg;
    localparam int unsigned NUM_FRAGS  = VPU_VLEN / (VPU_N_IPU * ELEN);

    logic [NRVREG-1:0][NUM_FRAGS-1:0][VPU_N_IPU*ELEN-1:0] vreg;

    logic [2:0] rf_we;

    assign rf_we[FU_VALU] = if_monitor_valu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o;
    assign rf_we[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o;
    assign rf_we[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.xif_fifo_result.result_valid_exec_o;

    vpu_decoded_t decoded_req [3];

    assign decoded_req[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_decoded;
    assign decoded_req[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_decoded;
    assign decoded_req[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_decoded;

    logic [4:0] raddr1 [3];

    assign raddr1[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.dispatch_vs1;
    assign raddr1[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.dispatch_vs1;
    assign raddr1[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.dispatch_vs1;

    logic [4:0] raddr2 [3];

    assign raddr2[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.dispatch_vs2;
    assign raddr2[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.dispatch_vs2;
    assign raddr2[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.dispatch_vs2;

    logic [4:0] vd [3];

    always_comb begin
        vd = '{default: '0};

        if (if_monitor_valu.exe_wrapper_result.instr_fragment.dispatch_vd < NRVREG)
            vd[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.dispatch_vd;
        if (if_monitor_vlsu.exe_wrapper_result.instr_fragment.dispatch_vd < NRVREG)
            vd[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.dispatch_vd;
        if (if_monitor_vsld.exe_wrapper_result.instr_fragment.dispatch_vd < NRVREG)
            vd[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.dispatch_vd;
    end

    logic [FRAG_CNT_W-1:0] frag_idx [3];
    vl_t frag_vl [3];

    assign frag_idx[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.frag_idx;
    assign frag_idx[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.frag_idx;
    assign frag_idx[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.frag_idx;

    assign frag_vl[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.elements;
    assign frag_vl[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.elements;
    assign frag_vl[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.elements;

    function automatic dw_t active_elements_mask(
        input vpu_decoded_t request,
        input logic [FRAG_CNT_W-1:0] fragment,
        input vl_t fragment_vl
    );
        dw_t mask;
        int sew_bits;
        int bytes_per_element;
        int elements_per_fragment;
        int fragment_start;
        int element_index;
        int global_element;

        mask = '0;
        sew_bits = get_sew_bits(request.vtype.vsew);
        bytes_per_element = sew_bits / 8;
        elements_per_fragment = (VPU_N_IPU * ELEN) / sew_bits;
        fragment_start = fragment * elements_per_fragment;

        for (int byte_index = 0; byte_index < (VPU_N_IPU * ELEN) / 8; byte_index++) begin
            element_index = byte_index / bytes_per_element;
            global_element = fragment_start + element_index;
            if ((element_index < fragment_vl) &&
                (global_element >= request.vstart) &&
                (global_element < request.vl)) begin
                mask[8 * byte_index +: 8] = '1;
            end
        end

        return mask;
    endfunction

    function automatic dw_t merge_write_data(
        input int             fu,
        input vpu_decoded_t   request,
        input dw_t            result_data,
        input dw_t            old_vd,
        input logic [FRAG_CNT_W-1:0] fragment,
        input vl_t              fragment_vl
    );
        dw_t merged_data;
        int sew_bits;
        int bytes_per_element;
        int elements_per_fragment;
        int fragment_start;
        int element_index;
        int global_element;
        logic element_in_body;
        logic element_enabled;

        int unsigned FRAGB = VLENB / VPU_N_IPU;

        merged_data = old_vd;
        sew_bits = get_sew_bits(request.vtype.vsew);
        bytes_per_element = sew_bits / 8;
        elements_per_fragment = (VPU_N_IPU * ELEN) / sew_bits;
        fragment_start = fragment * elements_per_fragment;      // Starting vl idx 

        // Loads use EEW rather than SEW. Stores are filtered before this function.
        if (request.is_load || request.is_store) begin
            case (request.width)
                3'b000: bytes_per_element = 1;
                3'b101: bytes_per_element = 2;
                3'b110: bytes_per_element = 4;
                default: ;
                // default: bytes_per_element = sew_bits / 8;
            endcase
        end
        
        for (int byte_index = 0; byte_index < FRAGB; byte_index++) begin
            element_index = byte_index / bytes_per_element;
            global_element = fragment_start + element_index;    // Global element idx
            element_in_body = (element_index < fragment_vl) &&
                              (global_element >= request.vstart) &&
                              (global_element < request.vl);

            if (element_in_body) begin
                // vm=1 disables masking. Otherwise v0 supplies one bit per element.
                element_enabled = request.vm || vreg[0][fragment][element_index];
                if (element_enabled) begin
                    merged_data[8 * byte_index +: 8] = result_data[8 * byte_index +: 8];    // TODO: add VID case
                end else if (request.vtype.vma) begin   
                    merged_data[8 * byte_index +: 8] = 8'hFF;
                end
            end else if ((global_element >= request.vl) && request.vtype.vta) begin
                merged_data[8 * byte_index +: 8] = 8'hFF;
            end
            // Prestart and undisturbed elements retain old_vd.
        end

        return merged_data;
    endfunction

    always_comb begin : read_data
        for (int fu = 0; fu < 3; fu++) begin
            rdata1_o[fu] = '0;
            rdata2_o[fu] = '0;
            rdata_vd_o[fu] = '0;

            if (raddr1[fu] < NRVREG) begin
                rdata1_o[fu] = vreg[raddr1[fu]][frag_idx[fu]] &
                                active_elements_mask(decoded_req[fu], frag_idx[fu], frag_vl[fu]);
            end
            if (raddr2[fu] < NRVREG) begin
                rdata2_o[fu] = vreg[raddr2[fu]][frag_idx[fu]] &
                                active_elements_mask(decoded_req[fu], frag_idx[fu], frag_vl[fu]);
            end
            if (vd[fu] < NRVREG) begin
                // vd is intentionally unmasked for undisturbed writeback policy.
                rdata_vd_o[fu] = vreg[vd[fu]][frag_idx[fu]];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : write_data
        if (!rst_ni) begin
            vreg <= '{default: '0};
        end else begin
            for (int fu = 0; fu < 3; fu++) begin
                if (rf_we[fu] && !decoded_req[fu].is_store && (vd[fu] < NRVREG)) begin
                    vreg[vd[fu]][frag_idx[fu]] <= merge_write_data(
                        fu,
                        decoded_req[fu],
                        wdata_i[fu],
                        vreg[vd[fu]][frag_idx[fu]],
                        frag_idx[fu],
                        frag_vl[fu]
                    );
                end
            end
        end
    end

endmodule


