
module cvxif_cpu_model 
import cvxif_types_pkg::*;
#(
    parameter int unsigned QUEUE_DEPTH = 16
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

    // Instruction queue
    x_issue_req_t instr_queue[$];

    x_issue_req_t current_instr;
    logic         current_instr_valid;
    logic         waiting_for_result;
    id_t          waiting_result_id;


    // Result storage
    x_result_t result_queue[$];

    // Result interface
    // CPU is always ready to accept a coprocessor result.
    assign x_result_ready_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if (rst_ni) begin
            if (x_result_valid_i && x_result_ready_o) begin
                result_queue.push_back(x_result_i);

                $display("[%0t] CVXIF MODEL: Result received, id=%0d",
                         $time, x_result_i.id);
            end
        end
    end

    // Issue interface

    x_issue_req_t next_instr;

    assign x_issue_valid_o = current_instr_valid;
    assign x_issue_req_o   = current_instr;

    always_ff @(posedge clk_i) begin

        if (!rst_ni) begin
            current_instr       <= '0;
            current_instr_valid <= 1'b0;
            waiting_for_result  <= 1'b0;
            waiting_result_id   <= '0;
        end

        else begin

            // A writeback instruction blocks issue until its result is received.
            if (waiting_for_result) begin
                if (x_result_valid_i && x_result_ready_o &&
                    x_result_i.id == waiting_result_id) begin
                    waiting_for_result <= 1'b0;

                    if (instr_queue.size() != 0) begin
                        next_instr = instr_queue.pop_front();
                        current_instr       <= next_instr;
                        current_instr_valid <= 1'b1;
                    end

                    // result_queue.delete(i);

                    $display(
                        "[%0t] CVXIF MODEL: Result found, id=%0d",
                        $time,
                        x_result_i.id
                    );
                end
            end

            // Current instruction was accepted.
            else if (current_instr_valid && x_issue_ready_i &&
                     x_issue_resp_i.accept) begin

                $display("[%0t] CVXIF MODEL: Instruction accepted, id=%0d",
                         $time, current_instr.id);

                if (x_issue_resp_i.writeback &&
                    !(x_result_valid_i && x_result_ready_o && x_result_i.id == current_instr.id)) begin
                    current_instr_valid  <= 1'b0;
                    waiting_for_result   <= 1'b1;
                    waiting_result_id    <= current_instr.id;
                end
                else if (instr_queue.size() != 0) begin

                    next_instr = instr_queue.pop_front();

                    current_instr       <= next_instr;
                    // current_instr       <= instr_queue.pop_front();
                    current_instr_valid <= 1'b1;

                    $display("[%0t] CVXIF MODEL: Next instruction presented, id=%0d",
                             $time, next_instr.id);
                end
                else begin
                    current_instr_valid <= 1'b0;
                end
            end

            // No instruction currently being presented.
            // Load one from the queue.
            else if (!current_instr_valid) begin

                if (instr_queue.size() != 0) begin
                    current_instr       <= instr_queue.pop_front();
                    current_instr_valid <= 1'b1;
                end
            end
        end
    end

    // Register interface
    assign x_register_o       = '0;   // No register response is generated unless explicitly added.
    assign x_register_valid_o = 1'b0;

    // Commit interface
    assign x_commit_o.id          = x_issue_req_o.id;    
    assign x_commit_o.hartid      = x_issue_req_o.hartid;
    assign x_commit_o.commit_kill = '0;    
    assign x_commit_valid_o     = x_issue_valid_o;

    ///////////
    // Tasks //
    ///////////

    // Add an instruction to the CPU instruction stream.
    task automatic send_instruction(
        input logic [31:0] instr,
        input hartid_t     hartid,
        input id_t         id
    );
        x_issue_req_t req;

        req = '0;

        req.instr = instr;
        req.hartid = hartid;
        req.id = id;  

        instr_queue.push_back(req);

        $display("[%0t] CVXIF MODEL: Instruction queued, id=%0d",
                 $time, req.id);
    endtask


    // Wait until a result with the requested ID is received.
    task automatic wait_for_result(
        input logic [3:0] expected_id,
        output x_result_t result
    );

        forever begin

            // Check results already received.
            for (int i = 0; i < result_queue.size(); i++) begin

                if (result_queue[i].id == expected_id) begin

                    result = result_queue[i];
                    result_queue.delete(i);

                    $display(
                        "[%0t] CVXIF MODEL: Result found, id=%0d",
                        $time,
                        expected_id
                    );

                    return;
                end
            end
            @(posedge clk_i);
        end

    endtask


    // Convenience task:
    // Send instruction and wait for its result.
    // task automatic execute_instruction(
    //     input  x_issue_req_t req,
    //     output x_result_t    result
    // );

    //     send_instruction(req, 0, 0);
    //     wait_for_result(req.id, result);

    // endtask

endmodule
