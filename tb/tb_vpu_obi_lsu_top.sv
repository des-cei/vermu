`timescale 1ns/1ps

module tb_vpu_obi_lsu_top;

    import cvxif_types_pkg::*;
    import obi_pkg::*;
    import vpu_pkg::*;

    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned PORTS = 1;

    logic clk_i;
    logic rst_ni;
    dw_t data_i;
    dw_t data_o;
    logic [DATA_WIDTH-1:0] memory [0:255];
    logic [PORTS-1:0] read_pending_q;
    logic [31:0] read_address_q [PORTS];
    logic [PORTS-1:0] gnt;
    logic [PORTS-1:0] rvalid_q;
    logic [31:0] rdata_q [PORTS];

    if_xif_exe xif();
    obi_resp_t [PORTS-1:0] masters_resp_i;
    obi_req_t  [PORTS-1:0] masters_req_o;

    obi_lsu_top #(
        .obi_req_t       (obi_req_t),
        .obi_resp_t      (obi_resp_t),
        .EXT_XBAR_NMASTER(PORTS)
    ) dut (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .data_i        (data_i),
        .data_o        (data_o),
        .if_exe_wrapper(xif.exe_unit),
        .masters_resp_i(masters_resp_i),
        .masters_req_o (masters_req_o)
    );

    always #5 clk_i = ~clk_i;

    always_comb begin
        integer port_i;
        for (port_i = 0; port_i < PORTS; port_i++) begin
            gnt[port_i] = masters_req_o[port_i].req;
            masters_resp_i[port_i] = '{
                gnt:    gnt[port_i],
                rvalid: rvalid_q[port_i],
                rdata:  rdata_q[port_i]
            };
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        integer port_i;
        if (!rst_ni) begin
            for (port_i = 0; port_i < PORTS; port_i++) begin
                rvalid_q[port_i] <= 1'b0;
                rdata_q[port_i]  <= '0;
                read_pending_q[port_i] <= 1'b0;
                read_address_q[port_i] <= '0;
            end
            memory[32'h100 >> 2] <= 32'h44332211;
            memory[32'h104 >> 2] <= 32'h88776655;

        end else begin
            for (port_i = 0; port_i < PORTS; port_i++) begin
                // rvalid_q[port_i] <= read_pending_q[port_i];
                rvalid_q[port_i] <= masters_req_o[port_i].req && gnt[port_i];
                rdata_q[port_i]  <= memory[read_address_q[port_i][9:2]];

                read_pending_q[port_i] <= masters_req_o[port_i].req &&
                                          gnt[port_i] &&
                                          !masters_req_o[port_i].we;
                if (masters_req_o[port_i].req && gnt[port_i])
                    read_address_q[port_i] <= masters_req_o[port_i].addr;

                if (masters_req_o[port_i].req && gnt[port_i] &&
                    masters_req_o[port_i].we) begin
                    if (masters_req_o[port_i].be[0]) memory[masters_req_o[port_i].addr[9:2]][7:0]   <= masters_req_o[port_i].wdata[7:0];
                    if (masters_req_o[port_i].be[1]) memory[masters_req_o[port_i].addr[9:2]][15:8]  <= masters_req_o[port_i].wdata[15:8];
                    if (masters_req_o[port_i].be[2]) memory[masters_req_o[port_i].addr[9:2]][23:16] <= masters_req_o[port_i].wdata[23:16];
                    if (masters_req_o[port_i].be[3]) memory[masters_req_o[port_i].addr[9:2]][31:24] <= masters_req_o[port_i].wdata[31:24];
                end
            end
        end
    end

    task automatic clear_issue;
        xif.wrapper_exe_instr_valid = 1'b0;
        xif.wrapper_exe_instr_issue = '0;
        data_i = '0;
    endtask

    task automatic issue(
        input logic is_load,
        input logic is_store,
        input logic [2:0] width,
        input logic [1:0] mop,
        input logic [31:0] address,
        input logic [31:0] stride,
        input logic [7:0] vl,
        input dw_t store_value
    );
        @(posedge clk_i);
        xif.wrapper_exe_instr_issue = '0;
        xif.wrapper_exe_instr_issue.instr_decoded.is_load  = is_load;
        xif.wrapper_exe_instr_issue.instr_decoded.is_store = is_store;
        xif.wrapper_exe_instr_issue.instr_decoded.width    = width;
        xif.wrapper_exe_instr_issue.instr_decoded.mop      = mop;
        xif.wrapper_exe_instr_issue.instr_decoded.rs1_data = address;
        xif.wrapper_exe_instr_issue.instr_decoded.rs2_data = stride;
        xif.wrapper_exe_instr_issue.instr_decoded.vl       = vl;
        data_i = store_value;
        xif.wrapper_exe_instr_valid = 1'b1;
        @(posedge clk_i);
        xif.wrapper_exe_instr_valid = 1'b0;
    endtask

    task automatic wait_for_result;
        int unsigned cycles;
        cycles = 0;
        while (!xif.exe_wrapper_result.xif_fifo_result.result_valid_exec_o) begin
            @(posedge clk_i);
            cycles++;
            if (cycles > 50)
                $fatal(1, "Timed out waiting for DMA completion");
        end
        $display("Operation lasted: %d cycles.", cycles);
    endtask

    initial begin
        clk_i = 1'b0;
        rst_ni = 1'b0;

        clear_issue();
        // masters_resp_i = '{default: '0};
        // foreach (memory[index]) memory[index] = '0;

        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk_i);

        // Load:  sew8, unit-stride, vl = 6 
        // issue(1'b1, 1'b0, 3'b000, 2'b00, 32'h0000_0100, 32'd0, 8'd6, 32'b0);
        // wait_for_result();
        // if (data_o !== 64'h00006655_44332211)
        //     $fatal(1, "Multi-port byte load mismatch: got %h", data_o);

        // Store: sew16, unit-stride, vl = 4,  
        // issue(1'b0, 1'b1, 3'b110, 2'b00, 32'h0000_0120, 32'd0, 8'd2, 64'h5678_1234_DEAD_BEEF);
        // wait_for_result();
        // if (memory[32'h120 >> 2][15:0] !== 16'hBEEF)
        //     $fatal(1, "Port 0 halfword store mismatch: got %h", memory[32'h120 >> 2][15:0]);
        // if (memory[32'h124 >> 2][15:0] !== 16'h1234)
        //     $fatal(1, "Port 1 halfword store mismatch: got %h", memory[32'h124 >> 2][15:0]);

        issue(1'b0, 1'b1, 3'b110, 2'b00, 32'h0000_0120, 32'd0, 8'd1, 32'hDEAD_BEEF);
        wait_for_result();
        if (memory[32'h120 >> 2][15:0] !== 16'hBEEF)
            $fatal(1, "Port 0 halfword store mismatch: got %h", memory[32'h120 >> 2][15:0]);
        if (memory[32'h124 >> 2][15:0] !== 16'h1234)
            $fatal(1, "Port 1 halfword store mismatch: got %h", memory[32'h124 >> 2][15:0]);

        $display("tb_obi_lsu_top: PASS");
        $finish;
    
    end

endmodule