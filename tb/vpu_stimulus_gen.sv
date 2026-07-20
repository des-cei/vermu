// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_stimulus_gen
import vpu_pkg::*;
 #(
    // CVXIF Types
    parameter  int unsigned NrRgprPorts      = 2,
    parameter  int unsigned XLEN             = 32,
    parameter  type         readregflags_t   = logic,
    parameter  type         writeregflags_t  = logic,
    parameter  type         id_t             = logic,
    parameter  type         hartid_t         = logic,
    parameter  type         x_issue_req_t    = logic,
    parameter  type         x_issue_resp_t   = logic,
    parameter  type         x_register_t     = logic,
    parameter  type         x_commit_t       = logic,
    parameter  type         x_result_t       = logic,
    localparam type         registers_t      = logic [NrRgprPorts-1:0][XLEN-1:0],
    parameter  int unsigned EXT_XBAR_NMASTER = 1
) (
    input logic               clk_i,
    input logic               rst_ni,

    // CVXIF Interface
    output logic              x_issue_valid_o,
    input  logic              x_issue_ready_i,
    output x_issue_req_t      x_issue_req_o,
    input  x_issue_resp_t     x_issue_resp_i,
    output x_register_t       x_register_o,
    output logic              x_register_valid_o,
    input  logic              x_register_ready_i,
    output logic              x_commit_valid_o,
    output x_commit_t         x_commit_o,
    input  logic              x_result_valid_i,
    output logic              x_result_ready_o,
    input  x_result_t         x_result_i
);

    int file_handle;
    int scan_result;
    int idle_after_eof_cycles;
    string stimulus_file;
    logic eof_seen;
    id_t issue_id_q;


    logic [31:0] curr_instr, curr_rs1, curr_rs2;
    string curr_mnemonic;

    typedef enum logic [1:0] {
        INIT,
        READ,
        SEND
    } state_t;
    state_t state, next_state;

    initial begin
        if (!$value$plusargs("stimulus_path=%s", stimulus_file)) begin
            stimulus_file = "stimulus.txt";
        end
        file_handle = $fopen(stimulus_file, "r");
        if (!file_handle) $fatal(1, "Cannot open stimulus file: %s", stimulus_file);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= INIT;
            x_issue_valid_o    <= '0;
            x_issue_req_o      <= '0;
            x_register_o       <= '0;
            x_register_valid_o <= '0;
            x_commit_valid_o   <= '0;
            x_commit_o         <= '0;
            x_result_ready_o   <= 1'b1;
            eof_seen           <= 1'b0;
            idle_after_eof_cycles <= 0;
            issue_id_q         <= '0;
        end else begin
            state <= next_state;

            case (state)
                READ: begin
                if (!$feof(file_handle)) begin
                    scan_result = $fscanf(file_handle, "%h %h %h %s\n", curr_instr, curr_rs1, curr_rs2,
                                        curr_mnemonic);
                    if (scan_result == 4) begin
                        x_issue_valid_o <= 1'b1;
                        x_issue_req_o.instr <= curr_instr;
                        x_issue_req_o.id <= issue_id_q;

                        x_register_valid_o <= 1'b1;
                        x_register_o.id <= issue_id_q;
                        x_register_o.rs[0] <= curr_rs1;
                        x_register_o.rs[1] <= curr_rs2;
                        if(major_opcode_e'(curr_instr[6:0]) == OPCODE_OP_V &&
                            (vec_funct3_e'(curr_instr[14:12]) == FMT_OPIVX || vec_funct3_e'(curr_instr[14:12]) == FMT_OPMVX_CSRRSI)) begin
                            x_register_o.rs_valid <= 3'b001;
                        end else if (major_opcode_e'(curr_instr[6:0]) == OPCODE_LOAD || major_opcode_e'(curr_instr[6:0]) == OPCODE_STORE) begin
                            x_register_o.rs_valid <= (curr_instr[27:26] == 2'b10) ? 3'b011 : 3'b001;
                        end else begin
                            x_register_o.rs_valid <= '0;
                        end

                        x_commit_valid_o <= 1'b1;
                        x_commit_o.id    <= issue_id_q;
                        
                        // Increment core id counter
                        issue_id_q <= issue_id_q + 1'b1;
                    end
                end else begin
                    eof_seen <= 1'b1;
                end
                end
                SEND: begin
                if (x_issue_ready_i) begin
                    x_issue_valid_o <= 1'b0;
                    x_register_valid_o <= 1'b0;
                end
                end
                default: ;  // Maintain state
            endcase

            if (eof_seen && !x_issue_valid_o && !x_register_valid_o) begin
                idle_after_eof_cycles <= idle_after_eof_cycles + 1;
                if (idle_after_eof_cycles > 20) begin
                    $display("Stimulus completed, finishing simulation.");
                    $finish;
                end
            end else begin
                idle_after_eof_cycles <= 0;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            INIT: next_state = READ;
            READ: if (scan_result == 4) next_state = SEND;
            SEND: if (x_issue_ready_i) next_state = READ;
        endcase
    end
endmodule
