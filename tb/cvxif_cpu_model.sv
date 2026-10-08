// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// -----------------------------------------------------------------------------
// cvxif_cpu_model : behavioural "CPU side" of CV-X-IF for the VPU testbenches
//
// Changes w.r.t. the original version:
//   * queue_instruction()  : NON-blocking enqueue (send_instruction() = queue + wait).
//   * Rejected instructions (accept = 0) now complete the issue handshake and the
//     model moves on. Before, a reject left the instruction stuck on the bus forever.
//   * issue_log / wait_issue_resp() : the testbench can check accept / reject.
//   * wait_for_result() has a timeout instead of hanging silently.
//   * Prints are gated by VERBOSE (a sweep of hundreds of tests is unreadable otherwise).
// -----------------------------------------------------------------------------

module cvxif_cpu_model
import cvxif_types_pkg::*;
import vpu_pkg::*;
#(
    parameter int unsigned QUEUE_DEPTH     = 4,
    parameter int unsigned RESULT_TIMEOUT  = 2000,   // cycles
    parameter bit          VERBOSE         = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    output logic          x_issue_valid_o,
    input  logic          x_issue_ready_i,
    output x_issue_req_t  x_issue_req_o,
    input  x_issue_resp_t x_issue_resp_i,

    output x_register_t   x_register_o,
    output logic          x_register_valid_o,
    input  logic          x_register_ready_i,

    output logic          x_commit_valid_o,
    output x_commit_t     x_commit_o,

    input  x_result_t     x_result_i,
    input  logic          x_result_valid_i,
    output logic          x_result_ready_o
);

    // Instruction / operand queues (filled by the testbench)
    x_issue_req_t instr_queue[$];
    x_register_t  reg_queue[$];

    // Instruction currently presented on the issue interface
    x_issue_req_t current_instr;
    x_register_t  current_reg;
    logic         current_instr_valid;
    logic         waiting_for_result;
    id_t          waiting_result_id;

    // Observed transactions
    x_result_t result_queue[$];

    typedef struct {
        id_t id;
        bit  accept;
        bit  writeback;
    } issue_rsp_t;
    issue_rsp_t issue_log[$];

    // CPU is always ready to accept a coprocessor result.
    assign x_result_ready_o = 1'b1;

    // -------------------------------------------------------------------
    // Current cycle
    // -------------------------------------------------------------------
    logic result_hs;                 // coprocessor result is valid AND the CPU takes it
    logic issue_hs;                  // instruction presented AND coprocessor ready
    logic issue_accepted;            // issue_handshake AND accept (not a reject)
    logic result_unblocks_issue;     // result of the instruction we were waiting for
    logic issue_blocks_on_result;    // accepted writeback instr whose result is not here yet
    logic waiting_for_result_next;   // value waiting_for_result takes next cycle
    logic issue_slot_free;           // issue interface is free to present a new instruction

    assign result_hs             = x_result_valid_i && x_result_ready_o;
    assign issue_hs              = current_instr_valid && x_issue_ready_i;
    assign issue_accepted        = issue_hs && x_issue_resp_i.accept;
    assign result_unblocks_issue = result_hs && waiting_for_result &&
                                   (x_result_i.id == waiting_result_id);
    assign issue_blocks_on_result = issue_accepted && x_issue_resp_i.writeback &&
                                    !(result_hs && x_result_i.id == current_instr.id);
    assign issue_slot_free       = !current_instr_valid || issue_hs;

    always_comb begin
        waiting_for_result_next = waiting_for_result;
        if (result_unblocks_issue)  waiting_for_result_next = 1'b0;
        if (issue_blocks_on_result) waiting_for_result_next = 1'b1;
    end

    // -------------------------------------------------------------------
    // State update
    // -------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            current_instr       <= '0;
            current_reg         <= '0;
            current_instr_valid <= 1'b0;
            waiting_for_result  <= 1'b0;
            waiting_result_id   <= '0;
        end else begin
            waiting_for_result <= waiting_for_result_next;

            // Result channel: record what the coprocessor returned
            if (result_hs) begin
                result_queue.push_back(x_result_i);
                if (VERBOSE) $display("[%0t] CVXIF MODEL: Result received, id=%0d", $time, x_result_i.id);
            end

            // Issue channel: the handshake completes with ready, whatever accept says
            if (issue_hs) begin
                issue_log.push_back('{id: current_instr.id,
                                      accept: x_issue_resp_i.accept,
                                      writeback: x_issue_resp_i.writeback});
                if (VERBOSE)
                    $display("[%0t] CVXIF MODEL: Instruction %s, id=%0d", $time,
                             x_issue_resp_i.accept ? "accepted" : "REJECTED", current_instr.id);
                current_instr_valid <= 1'b0;
                if (issue_blocks_on_result) waiting_result_id <= current_instr.id;
            end

            // Present the next queued instruction (overrides the clear above)
            if (issue_slot_free && !waiting_for_result_next && instr_queue.size() != 0) begin
                current_instr       <= instr_queue.pop_front();
                current_reg         <= reg_queue.pop_front();
                current_instr_valid <= 1'b1;
            end
        end
    end

    assign x_issue_valid_o = current_instr_valid;
    assign x_issue_req_o   = current_instr;

    // Register interface
    assign x_register_o       = current_reg;
    assign x_register_valid_o = current_instr_valid;

    // Commit interface.
    assign x_commit_o.id          = x_issue_req_o.id;
    assign x_commit_o.hartid      = x_issue_req_o.hartid;
    assign x_commit_o.commit_kill = '0;
    assign x_commit_valid_o       = x_issue_valid_o;

    ///////////
    // Tasks //
    ///////////

    // Enqueue an instruction (does not wait for anything).
    task automatic queue_instruction(
        input logic [31:0] instr,
        input hartid_t     hartid,
        input id_t         id,
        input logic [31:0] rs1,
        input logic [31:0] rs2
    );
        x_issue_req_t  req;
        x_register_t   register;
        vec_funct3_e   fmt;
        major_opcode_e opcode;

        req        = '0;
        req.instr  = instr;
        req.hartid = hartid;
        req.id     = id;
        instr_queue.push_back(req);

        register = '0;
        fmt      = vec_funct3_e'(instr[14:12]);
        opcode   = major_opcode_e'(instr[6:0]);

        if (opcode == OPCODE_OP_V) begin
            if (fmt == FMT_OPCFG_CSRRCI || fmt == FMT_OPIVX || fmt == FMT_OPMVX_CSRRSI) begin
                register.rs_valid = 3'b001;
                register.rs[0]    = rs1;
            end
        end else if (opcode == OPCODE_LOAD || opcode == OPCODE_STORE) begin
            register.rs_valid = 3'b011;
            register.rs[0]    = rs1;
            register.rs[1]    = rs2;
        end
        reg_queue.push_back(register);

        if (VERBOSE) $display("[%0t] CVXIF MODEL: Instruction queued, id=%0d", $time, req.id);
    endtask

    // Wait for the issue-handshake of instruction 'id'; reports accept/reject.
    task automatic wait_issue_resp(input id_t id, output bit accept);
        int unsigned cycles = 0;
        forever begin
            for (int i = 0; i < issue_log.size(); i++) begin
                if (issue_log[i].id == id) begin
                    accept = issue_log[i].accept;
                    issue_log.delete(i);
                    return;
                end
            end
            @(posedge clk_i);
            if (++cycles > RESULT_TIMEOUT)
                $fatal(1, "CVXIF MODEL: timeout waiting for issue response of id=%0d", id);
        end
    endtask

    // Wait until a result with the requested ID has been received.
    task automatic wait_for_result(input id_t expected_id, output x_result_t result);
        int unsigned cycles = 0;
        forever begin
            for (int i = 0; i < result_queue.size(); i++) begin
                if (result_queue[i].id == expected_id) begin
                    result = result_queue[i];
                    result_queue.delete(i);
                    if (VERBOSE) $display("[%0t] CVXIF MODEL: Result found, id=%0d (%0d cycles)",
                                          $time, expected_id, cycles);
                    return;
                end
            end
            @(posedge clk_i);
            if (++cycles > RESULT_TIMEOUT)
                $fatal(1, "CVXIF MODEL: timeout waiting for result of id=%0d", expected_id);
        end
    endtask

    // Backwards compatible helper: enqueue and wait for the result.
    task automatic send_instruction(
        input logic [31:0] instr,
        input hartid_t     hartid,
        input id_t         id,
        input logic [31:0] rs1,
        input logic [31:0] rs2
    );
        x_result_t res;
        queue_instruction(instr, hartid, id, rs1, rs2);
        wait_for_result(id, res);
    endtask

endmodule