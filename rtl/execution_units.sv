module execution_units
import cvxif_types_pkg::*;
(
    // Clock and Reset
    input logic clk_i,
    input logic rst_ni,
    if_xif_exe.exe_unit if_exe_wrapper
    // output logic instr_accept_o,
    // input logic result_valid_i
);

    logic [31:0] alu_result_comb;
    // logic [31:0] alu_result_q;
    x_issue_t    alu_result_q;
    logic        result_valid_q;
    // logic        writeback_busy_q;

    logic        instr_accept;
    
    localparam  int op1 = 32'hBEBE0000;
    localparam  int op2 = 32'hCAFE;

    // ALU
    always_comb begin
        alu_result_comb = op1 + op2;
    end

    // always_ff @(posedge clk_i or negedge rst_ni) begin
    //     if (!rst_ni) begin
    //         writeback_busy_q <= 1'b0;
    //     end else if (result_valid_q) begin
    //         writeback_busy_q <= 1'b0;
    //     end else if (instr_accept && if_exe_wrapper.wrapper_exe_instr_issue.resp.writeback) begin
    //         writeback_busy_q <= 1'b1;
    //     end
    // end

    // Instruction accepted from XIF_wrapper
    assign instr_accept = if_exe_wrapper.wrapper_exe_instr_valid &&
                        //    if_exe_wrapper.wrapper_exe_recv_result_ready &&
                        //    (!if_exe_wrapper.wrapper_exe_instr_issue.resp.writeback || !writeback_busy_q);
                        if_exe_wrapper.wrapper_exe_recv_result_ready;

    // Shift register for instruction execution simulation
    shift_register #(
        .data_t (x_issue_t)
    ) shift_Register_i (
        .clk_i,
        .rst_ni,
        .en_i (1'b1),

        .bit_i(instr_accept),
        .data_i(if_exe_wrapper.wrapper_exe_instr_issue),
        
        .bit_o(result_valid_q),
        .data_o(alu_result_q)
    );

    // Register result for testing
    // always_ff @(posedge clk_i or negedge rst_ni) begin
    //     if (!rst_ni) begin
    //         alu_result_q   <= '0;
    //         result_valid_q <= 1'b0;
    //     end else begin
    //         if (instr_accept) begin
    //             alu_result_q   <= alu_result_comb;
    //             result_valid_q <= 1'b1;
    //         end else if (if_exe_wrapper.wrapper_exe_recv_result_ready) begin
    //             result_valid_q <= 1'b0;
    //         end
    //     end
    // end

    // Output to wrapper
    // assign if_exe_wrapper.exe_wrapper_recv_instr_ready             = result_valid_q;
    assign if_exe_wrapper.exe_wrapper_recv_instr_ready             = 1'b1;
    assign if_exe_wrapper.exe_wrapper_result.result_valid_exec_o   = result_valid_q;
    assign if_exe_wrapper.exe_wrapper_result.result_data_exec_o    = alu_result_comb;
    assign if_exe_wrapper.exe_wrapper_result.issue_exec_o.req      = if_exe_wrapper.wrapper_exe_instr_issue.req;
    assign if_exe_wrapper.exe_wrapper_result.issue_exec_o.resp     = if_exe_wrapper.wrapper_exe_instr_issue.resp;
    // assign if_exe_wrapper.exe_wrapper_result.issue_exec_o.register = '0;
    assign if_exe_wrapper.exe_wrapper_result.issue_exec_o.register = alu_result_q.register;

    //Testing assignment
    // assign instr_accept_o = instr_accept;

endmodule