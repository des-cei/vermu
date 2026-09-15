// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module obi_lsu_top
import vpu_pkg::*;
#(
    parameter type                obi_req_t  = logic,
    parameter type                obi_resp_t = logic,
    parameter int unsigned        ADDR_WIDTH = 32,
    parameter int unsigned        DATA_WIDTH = 32,
    parameter int unsigned        SIZE_WIDTH = 16,
    parameter int unsigned        STRD_WIDTH = 32,
    parameter int unsigned        EXT_XBAR_NMASTER = VPU_N_IPU
)(
    input  logic      clk_i,
    input  logic      rst_ni,
    input  dw_t       data_i,
    output dw_t       data_o,
    if_xif_exe.exe_unit if_exe_wrapper,
    input  obi_resp_t [EXT_XBAR_NMASTER-1:0] masters_resp_i,
    output obi_req_t  [EXT_XBAR_NMASTER-1:0] masters_req_o
);

    localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
    localparam int unsigned PORTS = EXT_XBAR_NMASTER;
    localparam int unsigned POS_WIDTH = $clog2(DATA_BYTES + 1);

    vpu_decoded_t instr_req;
    logic instr_ready;
    logic start;
    logic accept;
    logic active_q;
    logic pending_q;
    logic rw_q;
    logic [2:0] sew_q;
    logic [POS_WIDTH-1:0] element_bytes_q;

    logic [ADDR_WIDTH-1:0] addr_q [PORTS];
    logic [SIZE_WIDTH-1:0] size_q [PORTS];
    logic [STRD_WIDTH-1:0] stride_q [PORTS];
    logic [DATA_WIDTH-1:0] store_data [PORTS];
    logic [DATA_WIDTH-1:0] load_data [PORTS];
    dw_t load_result_q;
    dw_t data_q;
    logic store_valid [PORTS];
    logic store_ready [PORTS];
    logic load_valid [PORTS];
    logic load_ready [PORTS];
    logic done_vec [PORTS];
    logic complete_q [PORTS];
    logic [POS_WIDTH-1:0] store_pos_q [PORTS];
    logic [POS_WIDTH-1:0] load_pos_q [PORTS];
    logic all_done;
    logic transfer_done;

    logic [2:0] sew_d;
    logic [POS_WIDTH-1:0] element_bytes_d;
    logic [ADDR_WIDTH-1:0] addr_d [PORTS];
    logic [SIZE_WIDTH-1:0] size_d [PORTS];
    logic [STRD_WIDTH-1:0] stride_d [PORTS];
    integer element_count;
    integer elements_per_port;
    integer offset_elements;
    integer remaining_elements;
    integer port_elements;
    integer stride_value;

    assign instr_req = if_exe_wrapper.wrapper_exe_instr_issue.instr_decoded;
    assign instr_ready = !active_q && !pending_q;
    assign accept = if_exe_wrapper.wrapper_exe_instr_valid && instr_ready &&
                    (instr_req.is_load || instr_req.is_store);
    assign start = pending_q;
    always_comb begin
        integer done_i;
        all_done = 1'b1;
        for (done_i = 0; done_i < PORTS; done_i++) begin
            all_done &= complete_q[done_i];
        end
    end

    assign transfer_done = active_q && all_done;
    assign data_o = load_result_q;

    always_comb begin
        integer config_i;
        unique case (instr_req.width)
            3'b000: begin               // SEW_8
                sew_d = 3'd3;
                element_bytes_d = 1;
            end
            3'b101: begin               // SEW_16
                sew_d = 3'd4;
                element_bytes_d = 2;
            end
            3'b110: begin               // SEW_32
                sew_d = 3'd5;
                element_bytes_d = 4;
            end
            default: begin
                sew_d = 3'd0;
                element_bytes_d = 0;
            end
        endcase

        element_count = int'(instr_req.vl);
        elements_per_port = (element_bytes_d == 0) ? 0 : DATA_BYTES / element_bytes_d;  // max_elem_per_port
        stride_value = (instr_req.mop == 2'b10) ? int'(instr_req.rs2_data) :
                       int'(element_bytes_d);   // TODO: other mop cases

        for (config_i = 0; config_i < PORTS; config_i++) begin
            offset_elements = config_i * elements_per_port;
            remaining_elements = (element_count > offset_elements) ?
                                 element_count - offset_elements : 0;
            port_elements = (remaining_elements > elements_per_port) ?
                            elements_per_port : remaining_elements;
            addr_d[config_i] = instr_req.rs1_data + ADDR_WIDTH'(offset_elements * stride_value);   // TODO: DATA_WIDTH? 
            size_d[config_i] = SIZE_WIDTH'(port_elements * element_bytes_d);
            stride_d[config_i] = STRD_WIDTH'(stride_value);
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        integer port_i;
        if (!rst_ni) begin
            active_q <= 1'b0;
            pending_q <= 1'b0;
            rw_q <= 1'b0;
            sew_q <= '0;
            element_bytes_q <= '0;
            data_q <= '0;
            load_result_q <= '0;
            complete_q <= '{default: 1'b0};
            store_pos_q   <= '{default: '0};
            load_pos_q    <= '{default: '0};
            for (port_i = 0; port_i < PORTS; port_i++) begin
                addr_q[port_i] <= '0;
                size_q[port_i] <= '0;
                stride_q[port_i] <= '0;
            end
        end else begin
            if (accept) begin
                pending_q <= 1'b1;
                rw_q <= instr_req.is_store;
                sew_q <= sew_d;
                element_bytes_q <= element_bytes_d;
                data_q <= data_i;
                complete_q <= '{default: 1'b0};
                store_pos_q <= '{default: '0};
                load_pos_q  <= '{default: '0};
                load_result_q <= '0;
                for (port_i = 0; port_i < PORTS; port_i++) begin
                    addr_q[port_i] <= addr_d[port_i];
                    size_q[port_i] <= size_d[port_i];
                    stride_q[port_i] <= stride_d[port_i];
                end
            end else if (start) begin
                active_q <= 1'b1;
                pending_q <= 1'b0;
            end else if (transfer_done) begin
                active_q <= 1'b0;
            end

            for (port_i = 0; port_i < PORTS; port_i++) begin
                if (done_vec[port_i]) begin
                    complete_q[port_i] <= 1'b1;
                end
                if (store_valid[port_i] && store_ready[port_i]) begin
                    store_pos_q[port_i] <= store_pos_q[port_i] + element_bytes_q;
                end
                if (load_valid[port_i] && load_ready[port_i]) begin
                    if (element_bytes_q == 1)
                        load_result_q[port_i*DATA_WIDTH + load_pos_q[port_i]*8 +: 8] <= load_data[port_i][7:0];
                    else if (element_bytes_q == 2)
                        load_result_q[port_i*DATA_WIDTH + load_pos_q[port_i]*8 +: 16] <= load_data[port_i][15:0];
                    else if (element_bytes_q == 4)
                        load_result_q[port_i*DATA_WIDTH + load_pos_q[port_i]*8 +: 32] <= load_data[port_i][31:0];
                    load_pos_q[port_i] <= load_pos_q[port_i] + element_bytes_q;
                end
            end
        end
    end

    always_comb begin
        integer data_i_idx;
        for (data_i_idx = 0; data_i_idx < PORTS; data_i_idx++) begin
            store_data[data_i_idx] = '0;
            if (element_bytes_q == 1)
                store_data[data_i_idx][7:0] = data_q[data_i_idx*DATA_WIDTH + store_pos_q[data_i_idx]*8 +: 8];
            else if (element_bytes_q == 2)
                store_data[data_i_idx][15:0] = data_q[data_i_idx*DATA_WIDTH + store_pos_q[data_i_idx]*8 +: 16];
            else if (element_bytes_q == 4)
                store_data[data_i_idx][31:0] = data_q[data_i_idx*DATA_WIDTH + store_pos_q[data_i_idx]*8 +: 32];
        end
    end

    logic active_d;

    // always_ff @(posedge clk_i or negedge rst_ni) begin
    //     if (!rst_ni)
    //         active_d = 0;
    //     else 
    //         if (if_exe_wrapper.wrapper_exe_instr_valid) begin
    //             active_d = 1'b1; 
    //         end else if (all_done) begin
    //             active_d = 1'b0;
            
    // end
    always_comb begin
        active_d = 1;
        if (if_exe_wrapper.exe_wrapper_recv_instr_ready && !if_exe_wrapper.wrapper_exe_instr_valid) begin
            active_d = 1'b0; 
        end else if (all_done) begin
            active_d = 1'b0;
        end
    end

    genvar g;
    generate
        for (g = 0; g < PORTS; g++) begin : gen_obione
            assign store_valid[g] = active_q && rw_q && (size_q[g] != '0);
            assign load_ready[g] = active_q && !rw_q;

            obione #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .SIZE_WIDTH(SIZE_WIDTH),
                .STRD_WIDTH(STRD_WIDTH)
            ) i_obione (
                .clk_i        (clk_i),
                .rst_ni       (rst_ni),
                .clr_i        (!active_q && !start),
                .start_i      (start),
                .rw_i         (rw_q),
                .done_o       (done_vec[g]),
                .addr_i       (addr_q[g]),
                .size_i       (size_q[g]),
                .stride_i     (stride_q[g]),
                .sew_i        (sew_q),
                .master_req_o (masters_req_o[g]),
                .master_resp_i(masters_resp_i[g]),
                .data_i       (store_data[g]),
                .valid_i      (store_valid[g]),
                .ready_o      (store_ready[g]),
                .data_o       (load_data[g]),
                .byte_en_o    (),
                .valid_o      (load_valid[g]),
                .ready_i      (load_ready[g])
            );
        end
    endgenerate

    assign if_exe_wrapper.exe_wrapper_recv_instr_ready = instr_ready;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_valid_exec_o = transfer_done;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.result_data_exec_o = '0;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.req =
        if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.req;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.resp =
        if_exe_wrapper.wrapper_exe_instr_issue.instr_issue.resp;
    assign if_exe_wrapper.exe_wrapper_result.xif_fifo_result.issue_exec_o.register = '0;
    assign if_exe_wrapper.exe_wrapper_result.instr_decoded = instr_req;
    assign if_exe_wrapper.exe_wrapper_result.instr_fragment =
        if_exe_wrapper.wrapper_exe_instr_issue.instr_fragment;

    a_vl_fits_ports :
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        (instr_req.vl <= (PORTS * DATA_BYTES / element_bytes_d))
    )
    else $error(
        "VL (%0d) exceeds maximum supported elements (%0d)",
        instr_req.vl,
        (PORTS * DATA_BYTES / element_bytes_d)
    );

endmodule
