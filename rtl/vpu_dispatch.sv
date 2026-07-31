// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_dispatch
    import cvxif_types_pkg::*;
    import vpu_pkg::*;
 (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic                       disp_valid_i,     // head entry ready to dispatch
    input  vpu_decoded_t               disp_decoded_i,   // decoded fields
    input  x_issue_t                   disp_issue_i,     // CV-X-IF 
    output logic                       disp_ready_o,     // pop instr_fifo 
    input  logic                       kill_valid_i,
    input  logic [X_HARTID_WIDTH-1:0]  kill_hartid_i,
    input  logic [X_ID_WIDTH-1:0]      kill_id_i,
    output x_issue_fifo_res_t          x_fifo_res_o,     // To result_fifo
    if_xif_exe.xif_wrapper              fu_valu,         // slot FU_VALU=0
    if_xif_exe.xif_wrapper              fu_vlsu,         // slot FU_VLSU=1
    if_xif_exe.xif_wrapper              fu_vsld          // slot FU_VSLD=2
);

    // In-flight slot definition
    typedef struct packed {
        logic                       valid;
        logic [4:0]                 vd_base;
        logic [4:0]                 vs1_base;
        logic [4:0]                 vs2_base;
        logic [3:0]                 lmul_val;       
        logic [FRAG_CNT_W-1:0]      total_frags;    
        logic                       uses_vs1;
        logic                       uses_vs2;
        logic                       uses_vd_src;    
        logic [FRAG_CNT_W-1:0]      next_frag;      // next fragment to issue to FU
        logic [FRAG_MSK_W-1:0]      frag_done_mask; // bit k set when frag k written to VRF
        logic [X_HARTID_WIDTH-1:0]  hart_id;        // Kill and result routing
        logic [X_ID_WIDTH-1:0]      x_id;
        vpu_decoded_t               decoded;        // Full decoded VPU fields
        x_issue_t                   issue_meta;
    } slot_t;

    slot_t [MAX_INFLIGHT-1:0] slot_q, slot_d;

    dispatch_sideband_t [MAX_INFLIGHT-1:0] dispatch_last;   

    // Issue outputs to FUs
    logic [MAX_INFLIGHT-1:0]   fu_instr_valid;      
    vpu_issue_t [MAX_INFLIGHT-1:0] fu_instr_issue;

    // FU inputs back to dispatcher
    logic [MAX_INFLIGHT-1:0]                fu_recv_instr_ready; // FU ready for next fragment
    vpu_issue_fifo_res_t [MAX_INFLIGHT-1:0] fu_result;           // FU result (per fragment)

    // VALU 
    assign fu_valu.wrapper_exe_instr_valid       = fu_instr_valid[FU_VALU];
    assign fu_valu.wrapper_exe_instr_issue       = fu_instr_issue[FU_VALU];
    assign fu_valu.wrapper_exe_recv_result_ready = 1'b1; 
    assign fu_recv_instr_ready[FU_VALU]          = fu_valu.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VALU]                    = fu_valu.exe_wrapper_result;

    // VLSU 
    assign fu_vlsu.wrapper_exe_instr_valid       = fu_instr_valid[FU_VLSU];
    assign fu_vlsu.wrapper_exe_instr_issue       = fu_instr_issue[FU_VLSU];
    assign fu_vlsu.wrapper_exe_recv_result_ready = 1'b1;
    assign fu_recv_instr_ready[FU_VLSU]          = fu_vlsu.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VLSU]                    = fu_vlsu.exe_wrapper_result;

    // VSLD 
    assign fu_vsld.wrapper_exe_instr_valid       = fu_instr_valid[FU_VSLD];
    assign fu_vsld.wrapper_exe_instr_issue       = fu_instr_issue[FU_VSLD];
    assign fu_vsld.wrapper_exe_recv_result_ready = 1'b1;
    assign fu_recv_instr_ready[FU_VSLD]          = fu_vsld.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VSLD]                    = fu_vsld.exe_wrapper_result;

    function automatic logic [FRAG_CNT_W-1:0] calc_total_frags(
        input logic [7:0] vl,
        input logic [2:0] vsew,     
        input logic [3:0] lmul_val  
    );
        logic [FRAG_CNT_W-1:0] epf;       // elements per fragment
        logic [FRAG_CNT_W-1:0] tf;
        logic [FRAG_CNT_W-1:0] max_frags;

        case (vsew)
            3'd0:    epf = FRAG_CNT_W'(DW /  8);  // SEW=8
            3'd1:    epf = FRAG_CNT_W'(DW / 16);  // SEW=16
            3'd2:    epf = FRAG_CNT_W'(DW / 32);  // SEW=32
            default: epf = FRAG_CNT_W'(DW / 32);  // default: SEW=32
        endcase
        if (epf == '0) epf = 1;  
        tf        = (FRAG_CNT_W'(vl) + epf - 1) / epf;

        // $display(
            // "vl=%0d vsew=%0d DW=%0d epf=%0d tf(before)=%0d N_IPU=%0d lmul_val=%0d limit=%0d",
            // vl,
            // vsew,
            // DW,
            // epf,
            // tf,
            // VPU_N_IPU,
            // lmul_val,
            // VPU_N_IPU * lmul_val
        // );

        max_frags = FRAG_CNT_W'(FRAGS_PER_REG) * FRAG_CNT_W'(lmul_val);
        if (max_frags == '0) max_frags = 1;
        if (tf > max_frags) tf = max_frags;

        // $display(
        //     "tf=%0d limit=%0d clamp=%0b",
        //     tf,
        //     VPU_N_IPU * lmul_val,
        //     (tf > FRAG_CNT_W'(VPU_N_IPU * lmul_val))
        // );

        return tf;
    endfunction

    // Decode vlmul field to actual multiplier value 
    function automatic logic [3:0] vlmul_to_val(input logic [2:0] vlmul);
        case (vlmul)
            3'b000:  return 4'd1;
            3'b001:  return 4'd2;
            3'b010:  return 4'd4;
            3'b011:  return 4'd8;
            default: return 4'd1;   // fractional: treat as 1
        endcase
    endfunction

    /////////////////////////////////
    // Per-slot address derivation //
    /////////////////////////////////

    logic [MAX_INFLIGHT-1:0][REG_OFF_W-1:0]             reg_offset;
    logic [MAX_INFLIGHT-1:0][$clog2(FRAGS_PER_REG)-1:0] frag_in_reg;

    always_comb begin
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            // Which register in LMUL group
            reg_offset[i]  = REG_OFF_W'(slot_q[i].next_frag / FRAGS_PER_REG);
            // Which slice within register
            frag_in_reg[i] = slot_q[i].next_frag[$clog2(FRAGS_PER_REG)-1:0]; 
        end
    end

    /////////////////////////////////
    // Fragment-level hazard check //
    /////////////////////////////////
    
    logic [MAX_INFLIGHT-1:0] slot_hazard; 
    logic [4:0] cur_vs1, cur_vs2, cur_vd;

    always_comb begin
        slot_hazard = '0;

        for (int s = 0; s < MAX_INFLIGHT; s++) begin
            // All fragments dispatched. No hazard.
            if (!slot_q[s].valid) continue;
            if (slot_q[s].next_frag >= slot_q[s].total_frags) continue;

            // Current register addresses for slot s's next fragment
            cur_vs1 = slot_q[s].vs1_base + 5'(reg_offset[s]);
            cur_vs2 = slot_q[s].vs2_base + 5'(reg_offset[s]);
            cur_vd  = slot_q[s].vd_base  + 5'(reg_offset[s]);

            for (int p = 0; p < MAX_INFLIGHT; p++) begin
                if (p == s)            continue;
                if (!slot_q[p].valid)  continue;

                // RAW: vs1 depends on p's vd
                if (slot_q[s].uses_vs1) begin
                    if (cur_vs1 >= slot_q[p].vd_base && cur_vs1 <  slot_q[p].vd_base + 5'(slot_q[p].lmul_val)) begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        // fg index into p's frag_done_mask:
                        fg = FRAG_CNT_W'((cur_vs1 - slot_q[p].vd_base)) *
                             FRAG_CNT_W'(FRAGS_PER_REG) +
                             FRAG_CNT_W'(frag_in_reg[s]);

                        // $display("%0t fg=%0d qmask=%b dmask=%b wb_valid=%0b wb_frag=%0d",
                        //     $time,
                        //     fg,
                        //     slot_q[p].frag_done_mask,
                        //     slot_d[p].frag_done_mask,
                        //     wb_valid[p],
                        //     wb_frag[p]);

                        if (!slot_q[p].frag_done_mask[fg]) begin
                            slot_hazard[s] = 1'b1;

                            // $display("%0t: RAW vs1, s=%0d p=%0d fg=%0d cur_vs1=%0d vd_base=%0d frag_in_reg=%0d FRAGS_PER_REG=%0d lmul=%0d",
                            //     $time, s, p, fg, cur_vs1, slot_q[p].vd_base, frag_in_reg[s], FRAGS_PER_REG, slot_q[p].lmul_val);
                        end
                    end
                end

                // RAW: vs2 depends on p's vd 
                if (slot_q[s].uses_vs2) begin
                    if (cur_vs2 >= slot_q[p].vd_base &&
                        cur_vs2 <  slot_q[p].vd_base + 5'(slot_q[p].lmul_val))
                    begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        fg = FRAG_CNT_W'((cur_vs2 - slot_q[p].vd_base)) *
                             FRAG_CNT_W'(FRAGS_PER_REG) +
                             FRAG_CNT_W'(frag_in_reg[s]);

                        if (!slot_q[p].frag_done_mask[fg]) begin
                            slot_hazard[s] = 1'b1;

                            // $display("%0t: RAW vs2, s=%0d p=%0d fg=%0d cur_vs2=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                                // $time, s, p, fg, cur_vs2, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].lmul_val);
                        end
                    end
                end

                // RAW: vd_src  
                if (slot_q[s].uses_vd_src) begin
                    if (cur_vd >= slot_q[p].vd_base &&
                        cur_vd <  slot_q[p].vd_base + 5'(slot_q[p].lmul_val))
                    begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        fg = FRAG_CNT_W'((cur_vd - slot_q[p].vd_base)) *
                             FRAG_CNT_W'(FRAGS_PER_REG) +
                             FRAG_CNT_W'(frag_in_reg[s]);
                        if (!slot_q[p].frag_done_mask[fg]) begin
                            slot_hazard[s] = 1'b1;

                            // $display("%0t: RAW vd_src, s=%0d p=%0d fg=%0d cur_vd=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                                // $time, s, p, fg, cur_vd, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].lmul_val);
                        end
                    end
                end

                // WAW: both slots writing same register group
                // Older instructions never wait for younger ones.
                if (slot_q[p].x_id > slot_q[s].x_id)
                    continue;

                if (cur_vd >= slot_q[p].vd_base &&
                    cur_vd <  slot_q[p].vd_base + 5'(slot_q[p].lmul_val))
                begin
                    automatic logic [FRAG_CNT_W-1:0] fg;
                    fg = FRAG_CNT_W'((cur_vd - slot_q[p].vd_base)) *
                         FRAG_CNT_W'(FRAGS_PER_REG) +
                         FRAG_CNT_W'(frag_in_reg[s]);

                    if (!slot_q[p].frag_done_mask[fg]) begin
                        slot_hazard[s] = 1'b1;
                        
                        // $display("%0t: WAW, s=%0d p=%0d fg=%0d cur_vd=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                        //         $time, s, p, fg, cur_vd, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].lmul_val);
                        // $display(
                        //     "WAW: s=%0d p=%0d s_id=%0d p_id=%0d next_frag_s=%0d next_frag_p=%0d",
                        //     s, p,
                        //     slot_q[s].x_id,
                        //     slot_q[p].x_id,
                        //     slot_q[s].next_frag,
                        //     slot_q[p].next_frag
                        // );
                    end
                end

                // $display(
                //     "%0t: next_frag=%0d total_frags=%0d wb_frag=%0d wb_valid=%0b",
                //     $time,
                //     slot_q[p].next_frag,
                //     slot_q[p].total_frags,
                //     wb_frag[p],
                //     wb_valid[p]
                // );

            end // for p
        end // for s
    end

    /////////////////////////////////////
    // Per-slot issue_en and x_issue_t //
    /////////////////////////////////////

    logic [MAX_INFLIGHT-1:0] slot_issue_en; // slot fires to FU this cycle
    x_issue_t            issue; 

    always_comb begin
        fu_instr_valid = '0;
        fu_instr_issue = '0;

        dispatch_last = '0;

        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            logic [4:0]          vs1_addr, vs2_addr, vd_addr;

            slot_issue_en[i] = slot_q[i].valid
                             && (slot_q[i].next_frag < slot_q[i].total_frags)   
                             && !slot_hazard[i]
                             && fu_recv_instr_ready[i];

            fu_instr_valid[i] = slot_issue_en[i];
            if (slot_issue_en[i]) begin
                vs1_addr = slot_q[i].vs1_base + 5'(reg_offset[i]);
                vs2_addr = slot_q[i].vs2_base + 5'(reg_offset[i]);
                vd_addr  = slot_q[i].vd_base  + 5'(reg_offset[i]);
                // Fragment index for data allocation in functional units
                dispatch_last[i].is_last = (slot_q[i].next_frag == slot_q[i].total_frags - 1);
                dispatch_last[i].frag_idx = frag_in_reg[i];

                // Start from stored metadata
                issue = slot_q[i].issue_meta;

                // Patch register addresses considering LMUL impact
                dispatch_last[i].dispatch_vs1 = vs1_addr;
                dispatch_last[i].dispatch_vs2 = vs2_addr;
                dispatch_last[i].dispatch_vd = vd_addr;

                fu_instr_issue[i].instr_issue    = issue;
                fu_instr_issue[i].instr_decoded  = disp_decoded_i;  
                fu_instr_issue[i].instr_fragment = dispatch_last[i];
            end
        end
    end


    /////////////////////////////////////////////
    // New instruction dispatch to a free slot //
    /////////////////////////////////////////////

    logic [1:0]  new_fu_id;
    logic        new_slot_free;
    // logic        new_waw;
    logic        dispatch_fire;

    always_comb begin
        // Route to target FU by instruction type
        if (disp_decoded_i.is_load || disp_decoded_i.is_store)
            new_fu_id = 2'(FU_VLSU);
        else if (disp_decoded_i.is_widening || disp_decoded_i.is_narrowing)
            new_fu_id = 2'(FU_VSLD);
        else
            new_fu_id = 2'(FU_VALU);   // arith, reductions, mask ops

        new_slot_free = !slot_q[new_fu_id].valid;

    //     // Instruction-level WAW check
    //     begin
    //         logic [3:0] new_lmul;
    //         new_lmul  = vlmul_to_val(disp_decoded_i.vlmul);
    //         new_waw   = 1'b0;
    //         for (int p = 0; p < MAX_INFLIGHT; p++) begin
    //             if (slot_q[p].valid) begin
    //                 // Overlap if ranges intersect
    //                 if ((disp_decoded_i.vd < slot_q[p].vd_base + 5'(slot_q[p].lmul_val)) &&
    //                     (slot_q[p].vd_base  < disp_decoded_i.vd + 5'(new_lmul)))
    //                     new_waw = 1'b1;
    //             end
    //         end
    //     end

        // dispatch_fire = disp_valid_i && new_slot_free && !new_waw;
        dispatch_fire = disp_valid_i && new_slot_free;
    end

    assign disp_ready_o = dispatch_fire;


    //////////////////////
    // Next-state logic //
    //////////////////////

    // Pre-compute result arrivals: which slot completed a fragment this cycle?
    // frag_idx is recovered from the slot's next_frag at the time of issue

    logic [MAX_INFLIGHT-1:0]                 wb_valid;   // fragment writeback this cycle
    logic [MAX_INFLIGHT-1:0][FRAG_CNT_W-1:0] wb_frag;    // which fragment completed
    logic [MAX_INFLIGHT-1:0]                 wb_is_last; // last fragment of instruction

    always_comb begin
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            wb_valid[i] = fu_result[i].xif_fifo_result.result_valid_exec_o && slot_q[i].valid;
            wb_frag[i] = fu_result[i].instr_fragment.frag_idx;
            wb_is_last[i] = fu_result[i].instr_fragment.is_last;
        end
    end

    always_comb begin
        slot_d = slot_q;

        // Accumulate frag_done_mask from FU results
        // immediately unblocks a waiting instruction next cycle.
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            if (wb_valid[i]) begin
                slot_d[i].frag_done_mask[wb_frag[i]] = 1'b1;
                // Free slot when last fragment acknowledged
                // if (wb_is_last[i])
                if (wb_frag[i] == slot_q[i].total_frags - 1)    // TODO: wb_is_last or wb_frag?
                    slot_d[i].valid = 1'b0;
            end
                // $display("%0t: wb_valid=%0b wb_frag=%0d mask(before)=%b mask(after)=%b",
                //     $time,
                //     wb_valid[i],
                //     wb_frag[i],
                //     slot_q[i].frag_done_mask,
                //     slot_d[i].frag_done_mask);
        end

        // Advance next_frag when this cycle's issue was accepted
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            if (fu_instr_valid[i]) begin
                slot_d[i].next_frag = slot_q[i].next_frag + 1;
            end
        end

        // Allocate new slot on dispatch 
        if (dispatch_fire) begin
            logic [3:0] lv;
            logic [2:0] vsew;
            lv   = vlmul_to_val(disp_decoded_i.vlmul);
            vsew = disp_decoded_i.vsew;

            slot_d[new_fu_id].valid          = 1'b1;
            slot_d[new_fu_id].vd_base        = disp_decoded_i.vd;
            slot_d[new_fu_id].vs1_base       = disp_decoded_i.vs1;
            slot_d[new_fu_id].vs2_base       = disp_decoded_i.vs2;
            slot_d[new_fu_id].lmul_val       = lv;
            slot_d[new_fu_id].total_frags    = calc_total_frags(
                                                   disp_decoded_i.vl, vsew, lv);
            slot_d[new_fu_id].uses_vs1       = disp_decoded_i.uses_vs1;
            slot_d[new_fu_id].uses_vs2       = disp_decoded_i.uses_vs2;
            slot_d[new_fu_id].uses_vd_src    = disp_decoded_i.uses_vd_src;
            slot_d[new_fu_id].next_frag      = '0;
            slot_d[new_fu_id].frag_done_mask = '0;
            slot_d[new_fu_id].hart_id        = disp_issue_i.req.hartid;
            slot_d[new_fu_id].x_id           = disp_issue_i.req.id;
            slot_d[new_fu_id].decoded        = disp_decoded_i;
            slot_d[new_fu_id].issue_meta     = disp_issue_i;
        end

        // Kill — clear all slots matching hart_id 
        if (kill_valid_i) begin
            for (int i = 0; i < MAX_INFLIGHT; i++) begin
                if (slot_q[i].valid && slot_q[i].hart_id == kill_hartid_i)
                    slot_d[i].valid = 1'b0;
            end
        end

    end

    ////////////////
    // XIF Result //
    ////////////////

    always_comb begin  
        x_fifo_res_o = '0;
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            if (fu_result[i].xif_fifo_result.result_valid_exec_o && fu_result[i].instr_fragment.is_last)
                x_fifo_res_o = fu_result[i].xif_fifo_result;
        end 
    end 

    ///////////////
    // Registers //
    ///////////////

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < MAX_INFLIGHT; i++)
                slot_q[i] <= '0;
        end else begin
            slot_q <= slot_d;
        end            
    end

    ////////////////
    // Assertions //
    ////////////////

`ifndef NO_ASSERT

    property p_no_double_alloc;
        @(posedge clk_i) disable iff (!rst_ni)
        dispatch_fire |-> !slot_q[new_fu_id].valid;
    endproperty
    assert property (p_no_double_alloc)
        else $error("DISPATCH: double-alloc on FU slot %0d", new_fu_id);

    // p_frag_no_overflow — next_frag must never exceed total_frags
    // One property per slot (for loops are illegal inside property bodies).
    property p_frag_no_overflow_s0;
        @(posedge clk_i) disable iff (!rst_ni)
        slot_q[0].valid |-> (slot_q[0].next_frag <= slot_q[0].total_frags);
    endproperty
    assert property (p_frag_no_overflow_s0)
        else $error("DISPATCH: next_frag overflow in slot 0 (VALU)");
 
    property p_frag_no_overflow_s1;
        @(posedge clk_i) disable iff (!rst_ni)
        slot_q[1].valid |-> (slot_q[1].next_frag <= slot_q[1].total_frags);
    endproperty
    assert property (p_frag_no_overflow_s1)
        else $error("DISPATCH: next_frag overflow in slot 1 (VLSU)");
 
    property p_frag_no_overflow_s2;
        @(posedge clk_i) disable iff (!rst_ni)
        slot_q[2].valid |-> (slot_q[2].next_frag <= slot_q[2].total_frags);
    endproperty
    assert property (p_frag_no_overflow_s2)
        else $error("DISPATCH: next_frag overflow in slot 2 (VSLD)");
 
    // p_wb_on_valid_slot — result must only arrive on an occupied slot
    // One property per slot.
    property p_wb_on_valid_s0;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_valid[0] |-> slot_q[0].valid;
    endproperty
    assert property (p_wb_on_valid_s0)
        else $error("DISPATCH: result arrived on idle slot 0 (VALU)");
 
    property p_wb_on_valid_s1;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_valid[1] |-> slot_q[1].valid;
    endproperty
    assert property (p_wb_on_valid_s1)
        else $error("DISPATCH: result arrived on idle slot 1 (VLSU)");
 
    property p_wb_on_valid_s2;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_valid[2] |-> slot_q[2].valid;
    endproperty
    assert property (p_wb_on_valid_s2)
        else $error("DISPATCH: result arrived on idle slot 2 (VSLD)");


    property p_inflight_limit;
        @(posedge clk_i) disable iff (!rst_ni)
        $countones({slot_q[0].valid, slot_q[1].valid, slot_q[2].valid})
            <= MAX_INFLIGHT;
    endproperty
    assert property (p_inflight_limit)
        else $error("DISPATCH: exceeded MAX_INFLIGHT");

`endif

endmodule : vpu_dispatch