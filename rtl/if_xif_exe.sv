import cvxif_types_pkg::x_issue_t;
import cvxif_types_pkg::x_issue_fifo_res_t;

interface if_xif_exe;

    // instruction issue signal
    logic              wrapper_exe_instr_valid;      // instruction valid
    x_issue_t          wrapper_exe_instr_issue;      // instruction issued
    logic              exe_wrapper_recv_instr_ready; // exe block is ready to receive new instruction

    logic              wrapper_exe_recv_result_ready;
    x_issue_fifo_res_t exe_wrapper_result;

    modport exe_unit (    // Execution unit point of view
        input  wrapper_exe_instr_valid,
        input  wrapper_exe_instr_issue,
        output exe_wrapper_recv_instr_ready,
        input  wrapper_exe_recv_result_ready,
        output exe_wrapper_result
    );

    modport xif_wrapper (   // Wrapper point of view
        output wrapper_exe_instr_valid,
        output wrapper_exe_instr_issue,
        input  exe_wrapper_recv_instr_ready,
        output wrapper_exe_recv_result_ready,
        input  exe_wrapper_result
    );

endinterface //if_xif_exe