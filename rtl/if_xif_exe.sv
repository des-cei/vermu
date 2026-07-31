// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Based on if_xif_exe.sv from the INTERA-GROUP/xif_wrapper project
// (licensed under the Apache License 2.0).
// Modifications by Ane Corral (ane.corral@upm.es).

import cvxif_types_pkg::x_issue_fifo_res_t;
import vpu_pkg::*;

interface if_xif_exe;

    // instruction issue signal
    logic              wrapper_exe_instr_valid;      // instruction valid
    vpu_issue_t        wrapper_exe_instr_issue;
    logic              exe_wrapper_recv_instr_ready; // exe block is ready to receive new instruction

    logic              wrapper_exe_recv_result_ready;// ready to receive result
    vpu_issue_fifo_res_t exe_wrapper_result;

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