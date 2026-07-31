// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)


`timescale 1ns/1ps

import cvxif_types_pkg::*;
import vpu_pkg::*;

module tb_vpu_dispatch;

    // Parameters
    localparam int unsigned VLEN      = 256;
    localparam int unsigned N_IPU     = 2;      // VLEN / (N_IPU * ELEN) = 2 fragments per register
    localparam int unsigned LMUL_MAX  = 8;
    localparam int unsigned FRAG_MAX  = N_IPU * LMUL_MAX;  // 32 // TODO: not accurate. Modify form 'vpu_pkg.sv'
    localparam int          CLK_HALF  = 5;      // 10 ns period

    // Clock and reset
    logic clk, rst_n;
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // DUT ports
    logic         disp_valid;
    vpu_decoded_t disp_decoded;
    x_issue_t     disp_issue;
    logic         disp_ready;

    logic                       kill_valid;
    logic [X_HARTID_WIDTH-1:0]  kill_hartid;
    logic [X_ID_WIDTH-1:0]      kill_id;

    x_issue_fifo_res_t x_fifo_res;

    // FU interfaces  (one per functional unit)
    if_xif_exe fu_valu_if ();
    if_xif_exe fu_vlsu_if ();
    if_xif_exe fu_vsld_if ();


    vpu_dispatch    dut (
        .clk_i          (clk),
        .rst_ni         (rst_n),
        .disp_valid_i   (disp_valid),
        .disp_decoded_i (disp_decoded),
        .disp_issue_i   (disp_issue),
        .disp_ready_o   (disp_ready),
        .kill_valid_i   (kill_valid),
        .kill_hartid_i  (kill_hartid),
        .kill_id_i      (kill_id),
        .x_fifo_res_o   (x_fifo_res),
        .fu_valu        (fu_valu_if.xif_wrapper),
        .fu_vlsu        (fu_vlsu_if.xif_wrapper),
        .fu_vsld        (fu_vsld_if.xif_wrapper)
    );

    //////////////
    // FU model //
    //////////////

    // Per-FU stall controls (driven from test body for scenario 8)
    logic fu_valu_stall_ready = 0;
    logic fu_vlsu_stall_ready = 0;
    logic fu_vsld_stall_ready = 0;

    logic [31:0] result_seed;

    // Generic FU model task 
    task automatic fu_model (
        virtual if_xif_exe.exe_unit  iface,
        input int                    latency,
        input logic                  stall_ready_sig  // reference to stall control
    );

        vpu_issue_t current_issue;
       
        logic busy;
        int   cycles_left;

        busy        = 0;
        cycles_left = 0;
        
        iface.exe_wrapper_result          = '0;
        iface.exe_wrapper_recv_instr_ready = 1;

        forever begin
            @(posedge clk); #10;
            // Drive result when head entry latency expired 
            iface.exe_wrapper_result = '0;

            // Ready only if the FU is idle
            iface.exe_wrapper_recv_instr_ready = !busy && !stall_ready_sig;

            // Accept a new instruction
            if (!busy && iface.wrapper_exe_instr_valid && iface.exe_wrapper_recv_instr_ready) begin

                current_issue = iface.wrapper_exe_instr_issue;

                busy        = 1'b1;
                cycles_left = latency;
            end

            // Execute
            if (busy) begin
                iface.exe_wrapper_recv_instr_ready = 0;     

                if (cycles_left > 0)
                    cycles_left--;

                if (cycles_left == 0) begin

                    iface.exe_wrapper_result.xif_fifo_result.result_valid_exec_o = 1'b1;

                    iface.exe_wrapper_result.xif_fifo_result.issue_exec_o = current_issue.instr_issue;

                    iface.exe_wrapper_result.xif_fifo_result.result_data_exec_o = result_seed;
                    result_seed++;

                    iface.exe_wrapper_result.instr_fragment = current_issue.instr_fragment;
                    // TODO: necesary to add decoded?
                    busy = 1'b0;
                end
            end


        end
    endtask

    // Start FU models in background    
    initial begin
        fork
            fu_model(fu_valu_if.exe_unit, 0, fu_valu_stall_ready);
            fu_model(fu_vlsu_if.exe_unit, 2, fu_vlsu_stall_ready);  // mem latency=2
            fu_model(fu_vsld_if.exe_unit, 1, fu_vsld_stall_ready);
        join_none
    end

    //////////////////////////////
    // Helper functions / tasks //
    //////////////////////////////

    // Build vpu_decoded_t for arithmetic (VALU) instruction
    function automatic vpu_decoded_t make_arith(
        input logic [4:0]  vd,
        input logic [4:0]  vs1,
        input logic [4:0]  vs2,
        input logic [7:0]  vl        = 8'd4,    // default: 4 elements
        input logic [1:0]  vsew      = 2'b10,   // default: SEW=32
        input logic [2:0]  vlmul     = 3'b000,  // default: LMUL=1
        input logic        uses_vs1  = 1,
        input logic        uses_vs2  = 1,
        input logic        uses_vd_src = 0
    );
        vpu_decoded_t d;
        d             = '0;
        d.vd          = vd;
        d.vs1         = vs1;
        d.vs2         = vs2;
        d.is_arith    = 1'b1;
        d.uses_vs1    = uses_vs1;
        d.uses_vs2    = uses_vs2;
        d.uses_vd_src = uses_vd_src;
        d.vl          = vl;
        d.vsew        = sew_e'(vsew);
        d.vlmul       = lmul_e'(vlmul);
        return d;
    endfunction

    // Build vpu_decoded_t for load (VLSU)
    function automatic vpu_decoded_t make_load(
        input logic [4:0]  vd,
        input logic [7:0]  vl        = 8'd4,
        input logic [1:0]  vsew      = 2'b10,
        input logic [2:0]  vlmul     = 3'b000
    );
        vpu_decoded_t d;
        d             = '0;
        d.vd          = vd;
        d.is_load     = 1'b1;
        d.vl          = vl;
        d.vsew        = sew_e'(vsew);
        d.vlmul       = lmul_e'(vlmul);
        return d;
    endfunction

    // Build x_issue_t with id and hartid
    function automatic x_issue_t make_issue(
        input logic [X_ID_WIDTH-1:0]     id,
        input logic [X_HARTID_WIDTH-1:0] hartid = 1'b0,
        input readregflags_t             rs_valid = '0
    );
        x_issue_t issue;
        issue                   = '0;
        issue.req.id            = id;
        issue.req.hartid        = hartid;
        issue.register.rs_valid = rs_valid;
        return issue;
    endfunction

    // Reset all driven signals
    task automatic reset_inputs();
        disp_valid       = 0;
        disp_decoded     = '0;
        disp_issue       = '0;
        kill_valid       = 0;
        kill_hartid      = '0;
        kill_id          = '0;
        fu_valu_stall_ready = 0;
        fu_vlsu_stall_ready = 0;
        fu_vsld_stall_ready = 0;
    endtask

    // Present one instruction and wait for dispatch acceptance
    task automatic present_and_dispatch(
        input vpu_decoded_t dec,
        input x_issue_t     issue,
        input int           timeout_cy = 20
    );
        int cy;
        disp_decoded = dec;
        disp_issue   = issue;
        disp_valid   = 1;
        cy = 0;
        while (!disp_ready && cy < timeout_cy) begin
            @(posedge clk); #1;
            cy++;
        end
        @(posedge clk); #1;
        disp_valid = 0;
    endtask

    task automatic wait_cycles(input int n);
        repeat(n) @(posedge clk);
        #1;
    endtask

    //////////////////
    // Scorekeeping //
    //////////////////

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  PASS %0t %s", $time, name);
            pass_count++;
        end else begin
            $display("  FAIL %0t %s", $time, name);
            fail_count++;
        end
    endtask

    typedef struct {
        bit dispatched;
        bit issued;
        bit completed;
    } instr_state_t;

    instr_state_t instr_state[16];

    initial forever begin
        @(posedge clk); #1;

        if (fu_valu_if.wrapper_exe_instr_valid)
            instr_state[fu_valu_if.wrapper_exe_instr_issue.instr_issue.req.id].dispatched = 1;

        if (fu_vlsu_if.wrapper_exe_instr_valid)
            instr_state[fu_vlsu_if.wrapper_exe_instr_issue.instr_issue.req.id].dispatched = 1;

        if (fu_vsld_if.wrapper_exe_instr_valid)
            instr_state[fu_vsld_if.wrapper_exe_instr_issue.instr_issue.req.id].dispatched = 1;

        if (x_fifo_res.result_valid_exec_o)
            instr_state[x_fifo_res.issue_exec_o.req.id].completed = 1;
    end

    ///////////////
    // Test body // 
    ///////////////

    logic disp_ready_d;
    logic issued;

    always_ff @(posedge clk) begin
        disp_ready_d <= disp_ready;
    end
    
    initial begin
        $dumpfile("tb_vpu_dispatch.vcd");
        $dumpvars(0, tb_vpu_dispatch);

        reset_inputs();
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        result_seed = 32'hDEAD_BEEF;

/*
        // Scenario 1 — Single-fragment dispatch to VALU
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 2 , SEW = 32, LMUL = 1. elems_per_frag = (N_IPU * ELEN) / SEW = 2
        $display("\n=== Sc 1: single-fragment dispatch to VALU ===");
        begin
            vpu_decoded_t dec;
            x_issue_t     issue;

            instr_state[1] = '{default:0};

            dec = make_arith(.vd(5'd2), .vs1(5'd0), .vs2(5'd1), .vl(8'd2), .vsew(2'b10));
            issue = make_issue(.id(4'd1));
            disp_decoded = dec;
            disp_issue   = issue;
            disp_valid   = 1;

            @(posedge clk); #1;
            disp_valid = 0;
            wait_cycles(8); // let FU complete
            check("Instruction 1 issued", instr_state[1].dispatched);
            check("Instruction 1 completed", instr_state[1].completed);
        end

        
        // Scenario 2 — Multi-fragment
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 6, SEW = 32, LMUL = 1. 3 fragments
        $display("\n=== Sc 2: multi-fragment (vl=6, SEW=32, 3 frags) ===");
        begin
            vpu_decoded_t dec;
            x_issue_t     issue ;
            instr_state[2] = '{default:0}; 

            dec = make_arith(.vd(5'd4), .vs1(5'd0), .vs2(5'd1), .vl(8'd6), .vsew(2'b10));
            issue = make_issue(.id(4'd2));
            disp_decoded = dec;
            disp_issue   = issue;
            disp_valid   = 1;

            @(posedge clk); #1;
            disp_valid = 0;

            wait_cycles(8);
            check("Instruction 2 issued", instr_state[2].dispatched);
            check("Instruction 2 completed", instr_state[2].completed);
        end
        
        // Scenario 3 — Fragment-level chaining
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 3, SEW = 32, LMUL = 1. 2 fragments
        //   vle32 v5 dispatched to VLSU 
        //   vadd v6,v5,v1 dispatched to VALU (2 frags)
        //   vadd frag 0 must stall until VLSU result for frag 0 arrives,
        //   then vadd can pipeline one frag behind VLSU
        
        $display("\n=== Scenario 3: fragment-level chaining (vle32 then vadd) ===");
        begin
            instr_state[3] = '{default:0};
            instr_state[4] = '{default:0};

            disp_decoded = make_load(.vd(5'd5), .vl(8'd3), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd3), .rs_valid(3'd7));  // TODO: rs_valid value
            disp_valid   = 1;

            @(posedge clk); #1; 
            if (disp_ready_d)   // Another instruction to dispatch
                disp_valid = 1;
            else 
                disp_valid = 0;

            // Dispatch vadd (dependent on v5)
            // Should stall until VLSU writes frag 0 of v5
            disp_decoded = make_arith(.vd(5'd6), .vs1(5'd5), .vs2(5'd1),
                                      .vl(8'd3), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd4), .rs_valid(3'd7)); // TODO: doubt of rs_valid value

            @(posedge clk); #1;
            disp_valid = 0;  // No more instructions left

            wait (x_fifo_res.result_valid_exec_o == 1);

            wait_cycles(8);
            check("Instruction 3 issued",    instr_state[3].dispatched);
            check("Instruction 3 completed", instr_state[3].completed);
            check("Instruction 4 issued",    instr_state[4].dispatched);
            check("Instruction 4 completed", instr_state[4].completed);
        end

        //   Scenario 3b — Fragment-level chaining
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 7, SEW = 32, LMUL = 1. 4 fragments
        //   vle32 v5 dispatched to VLSU 
        //   vadd v6,v5,v1 dispatched to VALU (4 frags)
        //   vadd frag 0 must stall until VLSU result for frag 0 arrives,
        //   then vadd can pipeline one frag behind VLSU
        
        $display("\n=== Scenario 3b: fragment-level chaining long (vle32 then vadd) ===");
        begin
            instr_state[3] = '{default:0};
            instr_state[4] = '{default:0};
            
            disp_decoded = make_load(.vd(5'd5), .vl(8'd7), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd3), .rs_valid(3'd7));  // TODO: rs_valid value
            disp_valid   = 1;

            @(posedge clk); #1;
            if (disp_ready_d) // Another instruction to dispatch
                disp_valid = 1;
            else 
                disp_valid = 0;

            // Dispatch vadd (dependent on v5)
            // Should stall until VLSU writes frag 0 of v5
            disp_decoded = make_arith(.vd(5'd6), .vs1(5'd5), .vs2(5'd1),
                                      .vl(8'd7), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd4), .rs_valid(3'd7)); // TODO: rs_valid value

            @(posedge clk); #1;
            disp_valid   = 0; // No more instructions left

            wait (x_fifo_res.result_valid_exec_o == 1);

            wait_cycles(8);
            check("Instruction 3 issued",    instr_state[3].dispatched);
            check("Instruction 3 completed", instr_state[3].completed);
            check("Instruction 4 issued",    instr_state[4].dispatched);
            check("Instruction 4 completed", instr_state[4].completed);
        end
            

        //  Scenario 4 — Same-FU structural stall with same destination
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 4, SEW = 32, LMUL = 1. 2 fragments

        $display("\n=== Sc 4: WAW stall — same destination register ===");
        begin
            instr_state[5] = '{default:0};
            instr_state[6] = '{default:0};

            // First instruction to VALU writing v8
            disp_decoded = make_arith(.vd(5'd8), .vs1(5'd6), .vs2(5'd7),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd5));
            disp_valid   = 1;
            @(posedge clk); #1;
            if (disp_ready_d)   // Another instruction to dispatch
                disp_valid = 1;
            else 
                disp_valid = 0;

            // Second instruction writing same vd = v8 — must not dispatch
            disp_decoded = make_arith(.vd(5'd8), .vs1(5'd2), .vs2(5'd3),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd6));

            wait(x_fifo_res.result_valid_exec_o);

            @(posedge clk); #1;
            // Now second should dispatch. After first alu valid.
            disp_decoded = make_arith(.vd(5'd8), .vs1(5'd2), .vs2(5'd3),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd6));
            disp_valid   = 1;

            @(posedge clk); #1;
            disp_valid = 0; // No more instructions left
            wait_cycles(8);
            check("Instruction 5 issued",    instr_state[5].dispatched);
            check("Instruction 5 completed", instr_state[5].completed);
            check("Instruction 6 issued",    instr_state[6].dispatched);
            check("Instruction 6 completed", instr_state[6].completed);
        end

        // Scenario 4b — Cross-FU WAW: vadd(VALU) and vle32(VLSU) both write v9
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 4, SEW = 32, LMUL = 1. 2 fragments

        $display("\n=== Scenario 4b: cross-FU WAW — vadd and vle32 both write v9 ===");
        begin
            int valu_first_cy, vlsu_dispatch_cy, vlsu_first_issue_cy;
            int obs;
            valu_first_cy       = -1;
            vlsu_dispatch_cy    = -1;
            vlsu_first_issue_cy = -1;
            instr_state[7] = '{default:0};
            instr_state[8] = '{default:0};
            
            // P: vadd writing v9. VALU
            disp_decoded = make_arith(.vd(5'd9), .vs1(5'd1), .vs2(5'd2),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd7));
            disp_valid   = 1;

            @(posedge clk); #1;
            if (disp_ready_d) // Another instruction to dispatch
                disp_valid = 1;
            else 
                disp_valid = 0;
 
            // Q: vle32 writing v9. VLSU slot is free. Should dispatch.
            disp_decoded = make_load(.vd(5'd9), .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd8));

            @(posedge clk); #1;
            disp_valid = 0;

            // Observe for 16 cycles: VLSU must not issue frag 0 before VALU writes frag 0
            for (obs = 0; obs < 16; obs++) begin
                @(posedge clk); #1;
                if (fu_valu_if.wrapper_exe_instr_valid ) 
                    valu_first_cy = obs;
                if (fu_vlsu_if.wrapper_exe_instr_valid ) 
                    vlsu_first_issue_cy = obs;
            end

            $display("    VALU first issue cy=%0d, VLSU first issue cy=%0d",
                     valu_first_cy, vlsu_first_issue_cy);
 
            wait_cycles(8);
            check("Instruction 7 issued",    instr_state[7].dispatched);
            check("Instruction 7 completed", instr_state[7].completed);
            check("Instruction 8 issued",    instr_state[8].dispatched);
            check("Instruction 8 completed", instr_state[8].completed);
        end

*/
        // Scenario 5 — Structural stall: VALU slot occupied
        //   VLEN = 256, N_IPU = 2, DW = 64
        //   vl = 5, SEW = 32, LMUL = 1. 3 fragments
        //   Two arithmetic instrs, both target VALU
        //   Second must wait for first to fully complete (slot freed)

        $display("\n=== Sc5: structural stall (VALU slot full) ===");
        begin
            instr_state[9] = '{default:0};
            instr_state[10] = '{default:0};

            disp_decoded = make_arith(.vd(5'd10), .vs1(5'd0), .vs2(5'd1),
                                      .vl(8'd5), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd9));
            disp_valid   = 1;
            @(posedge clk); #1;
            if (disp_ready_d)   // Another instruction to dispatch
                disp_valid = 1;
            else 
                disp_valid = 0;

            // Same cycle: present second arith to VALU
            disp_decoded = make_arith(.vd(5'd11), .vs1(5'd2), .vs2(5'd3),
                                      .vl(8'd5), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd10));

            wait(x_fifo_res.result_valid_exec_o);

            @(posedge clk); #1;
            disp_decoded = make_arith(.vd(5'd11), .vs1(5'd2), .vs2(5'd3),
                                      .vl(8'd5), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd10));
            disp_valid   = 1;
            
            @(posedge clk); #1;
            disp_valid = 0;
            wait_cycles(8);
            check("Instruction 9 issued",    instr_state[9].dispatched);
            check("Instruction 9 completed", instr_state[9].completed);
            check("Instruction 10 issued",    instr_state[10].dispatched);
            check("Instruction 10 completed", instr_state[10].completed);
        end

/*        // Scenario 6 — Kill flushes in-flight slot
        $display("\n=== Scenario 6: kill flushes VALU slot ===");
        begin
            disp_decoded = make_arith(.vd(5'd12), .vs1(5'd0), .vs2(5'd1),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd9), .hartid(1'b0));
            disp_valid   = 1;
            @(posedge clk); #1;
            check("Sc6: dispatched before kill", disp_ready);
            disp_valid = 0;

            // Kill it before it finishes
            @(posedge clk); #1;
            kill_valid  = 1;
            kill_hartid = 1'b0;
            kill_id     = 4'd9;
            @(posedge clk); #1;
            kill_valid  = 0;
            @(posedge clk); #1;

            // VALU slot should now be free → new dispatch accepted
            disp_decoded = make_arith(.vd(5'd13), .vs1(5'd0), .vs2(5'd1),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd10));
            disp_valid   = 1;
            @(posedge clk); #1;
            check("Sc6: VALU slot free after kill", disp_ready);
            disp_valid = 0;
            wait_cycles(8);
        end

        // Scenario 7 — LMUL=2: register group spanning v4 and v5
        //   vl=8, SEW=32, LMUL=2 → total_frags = ceil(8/2) = 4
        //   Fragments 0,1 use reg_offset=0 (v4), frags 2,3 use reg_offset=1 (v5)

        $display("\n=== Sc7: LMUL=2 register group stepping ===");
        begin
            logic [4:0] observed_vd_addr [4];
            int frag_count, obs;
            frag_count = 0;
            for (int i = 0; i < 4; i++) observed_vd_addr[i] = '0;

            // vl=8, SEW=32, LMUL=2 (vlmul=3'b001)
            disp_decoded = make_arith(.vd(5'd4), .vs1(5'd6), .vs2(5'd8),
                                      .vl(8'd8), .vsew(2'b10), .vlmul(3'b001));
            disp_issue   = make_issue(.id(4'd11));
            disp_valid   = 1;
            @(posedge clk); #1;
            check("Sc7: LMUL=2 dispatch accepted", disp_ready);
            disp_valid = 0;

            // Sample vd address on each VALU issue pulse for 12 cycles
            for (obs = 0; obs < 12; obs++) begin
                @(posedge clk); #1;
                if (fu_valu_if.wrapper_exe_instr_valid && frag_count < 4) begin
                    // vd addr is in rs[2] per our convention
                    observed_vd_addr[frag_count] =
                        fu_valu_if.wrapper_exe_instr_issue.register.rs[2][4:0];
                    frag_count++;
                end
            end

            check("Sc7: 4 fragments issued for LMUL=2",   frag_count == 4);
            check("Sc7: frags 0,1 use vd_base=4",
                  observed_vd_addr[0] == 5'd4 && observed_vd_addr[1] == 5'd4);
            check("Sc7: frags 2,3 use vd_base+1=5",
                  observed_vd_addr[2] == 5'd5 && observed_vd_addr[3] == 5'd5);

            wait_cycles(8);
        end

        // Scenario 8 — FU back-pressure via recv_instr_ready=0
        //   VALU stalls in accepting fragments; next_frag must not advance
        $display("\n=== Sc8: FU back-pressure (recv_instr_ready=0) ===");
        begin
            int issue_cnt;
            issue_cnt = 0;

            fu_valu_stall_ready = 1;   // FU not ready to accept

            disp_decoded = make_arith(.vd(5'd14), .vs1(5'd0), .vs2(5'd1),
                                      .vl(8'd4), .vsew(2'b10));
            disp_issue   = make_issue(.id(4'd12));
            disp_valid   = 1;
            @(posedge clk); #1;
            // dispatch_fire (queue pop) should still happen — the structural
            // stall is inside the slot (FU not ready), not at dispatch time.
            // NOTE: whether to pop queue on dispatch_fire or on first fragment
            // accepted is a design choice.  Here dispatch_fire = queue pop,
            // fragment issue happens when FU is ready.
            check("Sc8: queue dispatch accepted", disp_ready);
            disp_valid = 0;

            // While stalled, VALU should not see instr_valid
            @(posedge clk); #1;
            check("Sc8: VALU instr_valid=0 while stalled",
                  !fu_valu_if.wrapper_exe_instr_valid);

            // Release stall
            fu_valu_stall_ready = 0;
            @(posedge clk); #1;
            check("Sc8: VALU instr_valid=1 after stall release",
                  fu_valu_if.wrapper_exe_instr_valid);

            wait_cycles(8);
        end
*/
        // Summary
        @(posedge clk); #1;
        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — review waveform tb_vpu_dispatch.vcd");
        $finish;
    end

    // Watchdog
    initial begin
        #50000;
        $display("TIMEOUT — simulation exceeded limit");
        $finish;
    end

endmodule : tb_vpu_dispatch