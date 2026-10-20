// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_vregfile
    import vpu_pkg::*;
    import rvv_instr_pkg::*;
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

    vpu_decoded_t decoded_req [3];

    assign decoded_req[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_decoded; // Not necessary to separate issue-req instr_decoded ?
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

    assign vd[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment.dispatch_vd;
    assign vd[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment.dispatch_vd;
    assign vd[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment.dispatch_vd;

    dispatch_sideband_t issue_frag [3];
    dispatch_sideband_t res_frag [3];

    assign issue_frag[FU_VALU] = if_monitor_valu.wrapper_exe_instr_issue.instr_fragment;
    assign issue_frag[FU_VLSU] = if_monitor_vlsu.wrapper_exe_instr_issue.instr_fragment;
    assign issue_frag[FU_VSLD] = if_monitor_vsld.wrapper_exe_instr_issue.instr_fragment;

    assign res_frag[FU_VALU] = if_monitor_valu.exe_wrapper_result.instr_fragment;
    assign res_frag[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.instr_fragment;
    assign res_frag[FU_VSLD] = if_monitor_vsld.exe_wrapper_result.instr_fragment;

    logic [2:0] rf_we;

    assign rf_we[FU_VALU] = if_monitor_valu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o; // Not necessary to separate issue-req instr_decoded ?
    assign rf_we[FU_VLSU] = if_monitor_vlsu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o;
    assign rf_we[FU_VSLD] = (decoded_req[FU_VSLD].instr_enum == VMV_XS ||
                            ((decoded_req[FU_VSLD].instr_enum == VMV_SX) && (decoded_req[FU_VSLD].vl == '0)) ||
                            ((decoded_req[FU_VSLD].is_reduction) && (decoded_req[FU_VSLD].vl == '0))) ? '0: if_monitor_vsld.exe_wrapper_result.xif_fifo_result.result_valid_exec_o;

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
        // sew_bits = get_sew_bits(request.vtype.vsew); //TODO: EEW/SEW
        sew_bits = get_eew_bits(request.eew); //TODO: EEW/SEW
        bytes_per_element = sew_bits / 8;
        elements_per_fragment = (VPU_N_IPU * ELEN) / sew_bits;
        fragment_start = fragment * elements_per_fragment;

        for (int byte_index = 0; byte_index < (VPU_N_IPU * ELEN) / 8; byte_index++) begin
            element_index = byte_index / bytes_per_element;
            global_element = fragment_start + element_index;
// `ifndef SYNTHESIS
//         $display("[%0t] active_elements_mask: sew_bits=%0d bytes_per_element=%0d elements_per_fragment=%0d fragment=%0d fragment_vl=%0d fragment_start=%0d vstart=%0d vl=%0d element_index=%0d global_element=%0d",
//                  $time, sew_bits, bytes_per_element, elements_per_fragment,
//                  fragment, fragment_vl, fragment_start, request.vstart, request.vl, element_index, global_element);
// `endif
            if ((request.instr_enum == VMV_XS) &&
                (element_index < fragment_vl)) begin
                mask[8 * byte_index +: 8] = '1;
            end else if ((element_index < fragment_vl) &&
                (global_element >= request.vstart) &&
                (global_element < request.vl)) begin
                mask[8 * byte_index +: 8] = '1;
            end else if ((request.instr_enum == VMVNRR_V) && (global_element >= request.vstart)) begin  // TODO: move to result interface in unit
                // vmv<nr>r.v: whole register move, ignores vl/LMUL (valid even with vl = 0)
                mask[8 * byte_index +: 8] = '1;
            end
        end

// `ifndef SYNTHESIS
//         $display("[%0t] active_elements_mask: mask=%h", $time, mask);
// `endif

        return mask;
    endfunction

    function automatic dw_t merge_write_data(
        input vpu_decoded_t       req,
        input dw_t                result_data,
        input dw_t                old_vd,
        input dispatch_sideband_t f            // result (destination) view
    );
        dw_t  merged = old_vd;
        int   bpe    = get_eew_bits(req.eew) / 8;   // (EEW for loads, as now)
        int   epf    = DW / (bpe * 8);
        vl_t  row_g0 = (f.elem_base / epf) * epf;          // global idx of element 0 in this row
        vl_t  vl_eff = req.is_reduction ? vl_t'(1) : req.vl;
        vl_t  g;
        logic in_step, active;

// `ifndef SYNTHESIS
//         $display("[%0t] merge_write_data: eew=%0d bpe=%0d epf=%0d elem_base=%0d elements=%0d row_g0=%0d vl=%0d vl_eff=%0d vstart=%0d is_red=%0b vm=%0b vta=%0b vma=%0b",
//                  $time, get_eew_bits(req.eew), bpe, epf, f.elem_base, f.elements, row_g0,
//                  req.vl, vl_eff, req.vstart, req.is_reduction, req.vm, req.vtype.vta, req.vtype.vma);
// `endif

        // vstart >= vl (e.g. vl = 0): no element is updated, tail included
        if ((req.vstart >= req.vl) && (req.instr_enum != VMVNRR_V) && (req.instr_enum != VMV_XS))
            return old_vd;

        for (int b = 0; b < DW/8; b++) begin
            g       = row_g0 + vl_t'(b / bpe);
            in_step = (g >= f.elem_base) && (g < f.elem_base + f.elements);
// `ifndef SYNTHESIS
//             $display("[%0t]   b=%0d g=%0d in_step=%0b", $time, b, g, in_step);
// `endif
            if (g < req.vstart) begin
                ;                                                               // prestart: undisturbed
            end else if ((g >= vl_eff) && (req.instr_enum != VMVNRR_V)) begin 
                if (req.vtype.vta) merged[8*b +: 8] = 8'hFF;                    // tail
            end else if (in_step) begin                                         // body of THIS step
                active = req.vm || req.is_reduction || vreg[0][g / DW][g % DW];
                if (active)                merged[8*b +: 8] = result_data[8*b +: 8];
                else if (req.vtype.vma)    merged[8*b +: 8] = 8'hFF;
            end
            // else: body element owned by another step (narrowing half-row) -> keep
        end
        return merged;
    endfunction


    always_comb begin : read_data
        for (int fu = 0; fu < 3; fu++) begin
            rdata1_o[fu] = '0;
            rdata2_o[fu] = '0;
            rdata_vd_o[fu] = '0;
            // $display("unit %0h", fu);
            if (raddr1[fu] < NRVREG) begin
                rdata1_o[fu] = vreg[raddr1[fu]][issue_frag[fu].row_vs1] &
                                active_elements_mask(decoded_req[fu], issue_frag[fu].row_vs1, issue_frag[fu].elements);
            end
            if (raddr2[fu] < NRVREG) begin
                rdata2_o[fu] = vreg[raddr2[fu]][issue_frag[fu].row_vs2] &
                                active_elements_mask(decoded_req[fu], issue_frag[fu].row_vs2, issue_frag[fu].elements);
                // $display("[%0t] vreg_data[2]: %h", $time, vreg[raddr2[2]][issue_frag[2].row_vs2]);
            end
            if (vd[fu] < NRVREG) begin
                // vd is intentionally unmasked for undisturbed writeback policy.
                rdata_vd_o[fu] = vreg[vd[fu]][issue_frag[fu].row_vd];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : write_data
        if (!rst_ni) begin
            vreg <= '{default: '0};
        end else begin
            for (int fu = 0; fu < 3; fu++) begin
                if (rf_we[fu] && !decoded_req[fu].is_store && (vd[fu] < NRVREG)) begin
                    vreg[vd[fu]][res_frag[fu].row_vd] <= merge_write_data(
                        // fu,
                        decoded_req[fu],
                        wdata_i[fu],
                        // vreg[vd[fu]][frag_idx[fu]],
                        // frag_idx[fu],
                        // frag_vl[fu]
                        vreg[vd[fu]][res_frag[fu].row_vd],
                        res_frag[fu]
                    );
                end
            end
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (rf_we[FU_VALU] && (vd[FU_VALU] < NRVREG) &&
         rf_we[FU_VLSU] && decoded_req[FU_VLSU].is_load && (vd[FU_VLSU] < NRVREG) &&
         (res_frag[FU_VALU].dispatch_vd == res_frag[FU_VLSU].dispatch_vd)) |->
         (res_frag[FU_VALU].row_vd != res_frag[FU_VLSU].row_vd)
    ) else $error("VALU and VLSU write the same vector register and fragment");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (rf_we[FU_VALU] && (vd[FU_VALU] < NRVREG) &&
         rf_we[FU_VSLD] && (vd[FU_VSLD] < NRVREG) &&
         (res_frag[FU_VALU].dispatch_vd == res_frag[FU_VSLD].dispatch_vd)) |->
         (res_frag[FU_VALU].row_vd != res_frag[FU_VSLD].row_vd)
    ) else $error("VALU and VSLD write the same vector register and fragment");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (rf_we[FU_VLSU] && decoded_req[FU_VLSU].is_load && (vd[FU_VLSU] < NRVREG) &&
         rf_we[FU_VSLD] && (vd[FU_VSLD] < NRVREG) &&
         (res_frag[FU_VLSU].dispatch_vd == res_frag[FU_VSLD].dispatch_vd)) |->
         (res_frag[FU_VLSU].row_vd != res_frag[FU_VSLD].row_vd)
    ) else $error("VLSU and VSLD write the same vector register and fragment");
`endif

endmodule
