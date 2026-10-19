// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_dispatch
    import cvxif_types_pkg::*;
    import rvv_instr_pkg::*;
    import vpu_pkg::*;
 (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic                       disp_valid_i,     // head entry ready to dispatch
    input  vpu_decoded_t               disp_decoded_i,   // decoded fields
    input  vpu_issue_t                 disp_issue_i,     // CV-X-IF 
    output logic                       disp_ready_o,     // pop instr_fifo 
    output logic                       disp_empty_o,     // no dispatched work remains
    input  logic                       kill_valid_i,
    input  logic [X_HARTID_WIDTH-1:0]  kill_hartid_i,
    input  logic [X_ID_WIDTH-1:0]      kill_id_i,
    input  logic                       x_fifo_res_full_i,
    output x_issue_fifo_res_t          x_fifo_res_o,     // To result_fifo
    if_xif_exe.xif_wrapper             fu_valu,          // slot FU_VALU=0
    if_xif_exe.xif_wrapper             fu_vlsu,          // slot FU_VLSU=1
    if_xif_exe.xif_wrapper             fu_vsld           // slot FU_VSLD=2
);

    // In-flight slot definition
    typedef struct packed {
        logic                       valid;
        logic [4:0]                 vd_base;
        logic [4:0]                 vs1_base;
        logic [4:0]                 vs2_base;
        logic [XLEN-1:0]            rs1_base;
        logic [3:0]                 emul_val;       
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

    typedef struct packed {
        logic [4:0]            vs1, vs2, vd;
        logic [ROW_W-1:0]      row_vs1, row_vs2, row_vd;
        logic [FRAG_CNT_W-1:0] vd_frag;
        logic                  vd_frag_done;
    } opnd_view_t;

    slot_t [MAX_INFLIGHT-1:0]      slot_q, slot_d;
    opnd_view_t [MAX_INFLIGHT-1:0] view;

    dispatch_sideband_t [MAX_INFLIGHT-1:0] dispatch_last;   

    // Issue outputs to FUs
    logic [MAX_INFLIGHT-1:0]   fu_instr_valid;      
    vpu_compl_issue_t [MAX_INFLIGHT-1:0] fu_instr_issue, fu_instr_issue_d, fu_instr_issue_q;

    // FU inputs back to dispatcher
    logic [MAX_INFLIGHT-1:0]                fu_recv_instr_ready; // FU ready for next fragment
    vpu_issue_fifo_res_t [MAX_INFLIGHT-1:0] fu_result;           // FU result (per fragment)

    // Completed last fragments wait here until all older instructions have
    // completed and the result FIFO can accept them.
    logic [MAX_INFLIGHT-1:0]                 result_pending_q, result_pending_d;
    x_issue_fifo_res_t [MAX_INFLIGHT-1:0]    result_pending_data_q, result_pending_data_d;
    logic [MAX_INFLIGHT-1:0]                 slot_valid;

    for (genvar i = 0; i < MAX_INFLIGHT; i++) begin : gen_slot_valid
        assign slot_valid[i] = slot_q[i].valid;
    end

    // VALU 
    assign fu_valu.wrapper_exe_instr_valid       = fu_instr_valid[FU_VALU];
    assign fu_valu.wrapper_exe_instr_issue       = fu_instr_issue[FU_VALU];
    assign fu_valu.wrapper_exe_recv_result_ready = ~x_fifo_res_full_i && !result_pending_q[FU_VALU];
    assign fu_recv_instr_ready[FU_VALU]          = fu_valu.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VALU]                    = fu_valu.exe_wrapper_result;

    // VLSU 
    assign fu_vlsu.wrapper_exe_instr_valid       = fu_instr_valid[FU_VLSU];
    assign fu_vlsu.wrapper_exe_instr_issue       = fu_instr_issue[FU_VLSU];
    assign fu_vlsu.wrapper_exe_recv_result_ready = ~x_fifo_res_full_i && !result_pending_q[FU_VLSU];
    assign fu_recv_instr_ready[FU_VLSU]          = fu_vlsu.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VLSU]                    = fu_vlsu.exe_wrapper_result;

    // VSLD 
    assign fu_vsld.wrapper_exe_instr_valid       = fu_instr_valid[FU_VSLD];
    assign fu_vsld.wrapper_exe_instr_issue       = fu_instr_issue[FU_VSLD];
    assign fu_vsld.wrapper_exe_recv_result_ready = ~x_fifo_res_full_i && !result_pending_q[FU_VSLD];
    assign fu_recv_instr_ready[FU_VSLD]          = fu_vsld.exe_wrapper_recv_instr_ready;
    assign fu_result[FU_VSLD]                    = fu_vsld.exe_wrapper_result;

    function automatic logic [FRAG_CNT_W-1:0] calc_total_frags(
        input logic [7:0] vl,
        input sew_e       veew,     
        input logic [3:0] emul_val,
        input vec_instr_e vec_instr,
        input logic       vta
    );
        int unsigned epf;       // elements per fragment
        int unsigned tf;
        int unsigned max_frags;

        epf = calc_epf(veew);

        if (epf == '0) epf = 1;                        // TODO: not real
        tf        = (vl + epf - 1) / epf;
        if (vl != 0 && tf == 0) tf = 1;                // Instructions with single fragment
        if (vec_instr == VMV_SX && vl == 0) tf = 1;


        // $display(
        //     "vl=%0d veew=%0d DW=%0d epf=%0d tf(before)=%0d N_IPU=%0d emul_val=%0d limit=%0d",
        //     vl,
        //     veew,
        //     DW,
        //     epf,
        //     tf,
        //     VPU_N_IPU,
        //     emul_val,
        //     VPU_N_IPU * emul_val
        // );

        max_frags = FRAGS_PER_REG * emul_val;
        if (max_frags == '0) max_frags = 1;
        if (tf > max_frags) tf = max_frags;
        if (vta) tf = max_frags;                // If vta, whole register to be processed
        if (vec_instr == VMV_XS) tf = 1;          // Not considered LMUL > 1 

        // $display(
        //     "tf=%0d limit=%0d clamp=%0b",
        //     tf,
        //     VPU_N_IPU * emul_val,
        //     (tf > FRAG_CNT_W'(VPU_N_IPU * emul_val))
        // );

        return FRAG_CNT_W'(tf);
    endfunction

    function automatic vl_t calc_elements_for_frag(
        input vl_t             vl,
        input sew_e            veew,
        input vec_instr_e      instr,
        input logic [FRAG_CNT_W-1:0] frag
    );
        // TODO: add vstart consideration
        vl_t epf;
        vl_t consumed;
       
        epf = calc_epf(veew);   // Max elements per fragment 

        if (epf == '0) epf = 1;

        consumed = vl_t'(frag) * epf;
        if (instr == VMVNRR_V) 
            return epf;
        else if ((instr == VMV_XS ) && frag == '0)
            return 1;
            // TODO same vmv_sx condition?
        else if (instr == VMV_SX) begin
            if (frag == '0) return 1;
            else return 0;
        end else if (consumed >= vl)
            return '0;
        else if (vl - consumed > epf)
            return epf;
        else
            return vl - consumed;
    endfunction

    // Decode vlmul field to actual multiplier value 
    function automatic logic [3:0] vlmul_to_val(input logic [2:0] vlmul, input logic [2:0] nf, logic is_nf);
        logic [3:0] val;

        if (is_nf) begin
            val = 4'(nf) + 4'd1;  // vmv<nr>r.v: simm5[2:0] = nr-1 -> 1/2
        end else begin
            case (vlmul)
                3'b000:  val = 4'd1;
                3'b001:  val = 4'd2;
                3'b010:  val = 4'd4;
                3'b011:  val = 4'd8;
            default: val = 4'd1;   // fractional: treat as 1
        endcase
        end

        return val;
    endfunction

    function automatic logic id_is_older(
        input logic [X_ID_WIDTH-1:0] older_id,
        input logic [X_ID_WIDTH-1:0] newer_id
    );
        logic [X_ID_WIDTH-1:0] age;

        age = newer_id - older_id;
        return (age != '0) && !age[X_ID_WIDTH-1];
    endfunction

    function automatic opnd_view_t calc_view(input slot_t s,
                                            input logic [REG_OFF_W-1:0] roffset,
                                            input logic [ROW_W-1:0]     row);
        opnd_view_t v;
        logic last = (s.next_frag == s.total_frags - 1);

        // default: every operand walks the group in lockstep
        v.vs1 = s.vs1_base + 5'(roffset);
        v.vs2 = s.vs2_base + 5'(roffset);
        v.vd  = s.vd_base  + 5'(roffset);
        v.row_vs1 = row;    
        v.row_vs2 = row;    
        v.row_vd  = row;    
        v.vd_frag      = s.next_frag;
        v.vd_frag_done = 1'b1;

        if (s.decoded.is_reduction) begin
            // vs1[0] and vd[0] are scalars (EMUL=1); vd holds a partial sum until the last step
            v.vs1 = s.vs1_base;
            v.vd  = s.vd_base;
            v.row_vs1 = '0;
            v.row_vd  = '0; 
            v.vd_frag      = '0;
            v.vd_frag_done = last;
        end
        // future: is_widening / is_narrowing cases go here
        return v;
    endfunction

    /////////////////////////////////
    // Per-slot address derivation //
    /////////////////////////////////

    logic [MAX_INFLIGHT-1:0][REG_OFF_W-1:0] reg_offset;
    logic [MAX_INFLIGHT-1:0][ROW_W-1:0]     frag_in_reg;
    logic [MAX_INFLIGHT-1:0][XLEN-1:0]      mem_offset;     
    
    always_comb begin

        localparam int unsigned LOG2_N_IPU      = $clog2(VPU_N_IPU);
        localparam int unsigned LOG2_VREG_BYTES = $clog2(VPU_VLEN / 8);  // 4 for VLEN=128
            
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            // Which register in LMUL group
            reg_offset[i]  = REG_OFF_W'(slot_q[i].next_frag / FRAGS_PER_REG);
            // Which slice within register
            // frag_in_reg[i] = slot_q[i].next_frag[$clog2(FRAGS_PER_REG)-1:0];
            frag_in_reg[i] = slot_q[i].next_frag % FRAGS_PER_REG;
            // LS instructions
            mem_offset[i] = XLEN'( (slot_q[i].next_frag >> LOG2_N_IPU) << LOG2_VREG_BYTES );       
        end 
    end

    /////////////////////////////////
    // Fragment-level hazard check //
    /////////////////////////////////
    
    logic [MAX_INFLIGHT-1:0] slot_hazard; 
    // logic [4:0] cur_vs1, cur_vs2, cur_vd;

    always_comb begin
        slot_hazard = '0;

        for (int s = 0; s < MAX_INFLIGHT; s++) begin

            view[s] = calc_view(slot_q[s], reg_offset[s], ROW_W'(frag_in_reg[s]));

            // All fragments dispatched. No hazard.
            if (!slot_q[s].valid) continue;
            if (slot_q[s].next_frag >= slot_q[s].total_frags) continue;

            // Current register addresses for slot s's next fragment
            // if (slot_q[s].decoded.is_reduction) begin
            //     cur_vs1 = slot_q[s].vs1_base;
            //     cur_vs2 = slot_q[s].vs2_base + 5'(reg_offset[s]);
            //     cur_vd  = slot_q[s].vd_base;
            // end else begin
            //     cur_vs1 = slot_q[s].vs1_base + 5'(reg_offset[s]);
            //     cur_vs2 = slot_q[s].vs2_base + 5'(reg_offset[s]);
            //     cur_vd  = slot_q[s].vd_base  + 5'(reg_offset[s]);
            // end 

            for (int p = 0; p < MAX_INFLIGHT; p++) begin
                if (p == s)            continue;
                if (!slot_q[p].valid)  continue;

                // A consumer must never wait for a younger producer. The
                // instruction ID establishes program order when slots overlap.
                if (!id_is_older(slot_q[p].x_id, slot_q[s].x_id))
                    continue;

                // RAW: vs1 depends on p's vd
                if (slot_q[s].uses_vs1) begin
                    if (view[s].vs1 >= slot_q[p].vd_base && view[s].vs1 <  slot_q[p].vd_base + 5'(slot_q[p].emul_val)) begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        // fg index into p's frag_done_mask:
                        fg = FRAG_CNT_W'(view[s].vs1 - slot_q[p].vd_base) * 
                             FRAG_CNT_W'(FRAGS_PER_REG)  + 
                             FRAG_CNT_W'(view[s].row_vs1);

                        if (!slot_q[p].frag_done_mask[fg]) slot_hazard[s] = 1'b1;

                        // $display("%0t fg=%0d qmask=%b dmask=%b wb_valid=%0b wb_frag=%0d",
                        //     $time,
                        //     fg,
                        //     slot_q[p].frag_done_mask,
                        //     slot_d[p].frag_done_mask,
                        //     wb_valid[p],
                        //     wb_frag[p]);

                        // $display("%0t: RAW vs1, s=%0d p=%0d fg of p's=%0d view[s].vs1=%0d vd_base=%0d frag_in_reg=%0d FRAGS_PER_REG=%0d lmul=%0d",
                        //     $time, s, p, fg, view[s].vs1, slot_q[p].vd_base, frag_in_reg[s], FRAGS_PER_REG, slot_q[p].emul_val);
                    end
                end

                // RAW: vs2 depends on p's vd 
                if (slot_q[s].uses_vs2) begin
                    if (view[s].vs2 >= slot_q[p].vd_base &&
                        view[s].vs2 <  slot_q[p].vd_base + 5'(slot_q[p].emul_val))
                    begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        fg = FRAG_CNT_W'(view[s].vs2 - slot_q[p].vd_base) *
                             FRAG_CNT_W'(FRAGS_PER_REG) +
                             FRAG_CNT_W'(view[s].row_vs2);

                        if (!slot_q[p].frag_done_mask[fg]) begin
                            slot_hazard[s] = 1'b1;

                            // $display("%0t: RAW vs2, s=%0d p=%0d fg=%0d view[s].vs2=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                            //     $time, s, p, fg, view[s].vs2, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].emul_val);
                        end
                    end
                end

                // RAW: vd_src  
                if (slot_q[s].uses_vd_src) begin
                    if (view[s].vd >= slot_q[p].vd_base &&
                        view[s].vd <  slot_q[p].vd_base + 5'(slot_q[p].emul_val))
                    begin
                        automatic logic [FRAG_CNT_W-1:0] fg;
                        fg = FRAG_CNT_W'(view[s].vd - slot_q[p].vd_base) *
                             FRAG_CNT_W'(FRAGS_PER_REG) +
                             FRAG_CNT_W'(view[s].row_vd);
                        if (!slot_q[p].frag_done_mask[fg]) begin
                            slot_hazard[s] = 1'b1;

                            // $display("%0t: RAW vd_src, s=%0d p=%0d fg=%0d view[s].vd=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                            //     $time, s, p, fg, view[s].vd, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].emul_val);
                        end
                    end
                end

                // WAW: both slots writing same register group.
                if (view[s].vd >= slot_q[p].vd_base &&
                    view[s].vd <  slot_q[p].vd_base + 5'(slot_q[p].emul_val))
                begin
                    automatic logic [FRAG_CNT_W-1:0] fg;
                    fg = FRAG_CNT_W'(view[s].vd - slot_q[p].vd_base) *
                         FRAG_CNT_W'(FRAGS_PER_REG) +
                         FRAG_CNT_W'(view[s].row_vd);

                    if (!slot_q[p].frag_done_mask[fg]) begin
                        slot_hazard[s] = 1'b1;
                        
                        // $display("%0t: WAW, s=%0d p=%0d fg=%0d cur_vd=%0d vd_base=%0d frag_in_reg=%0d lmul=%0d",
                        //         $time, s, p, fg, view[s].vd, slot_q[p].vd_base, frag_in_reg[s], slot_q[p].emul_val);
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
        fu_instr_issue = fu_instr_issue_q;
        fu_instr_issue_d = fu_instr_issue_q;
        dispatch_last = '0;

        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            slot_issue_en[i] = slot_q[i].valid
                             && (slot_q[i].next_frag < slot_q[i].total_frags)
                             && !slot_hazard[i]
                             && fu_recv_instr_ready[i];

            fu_instr_valid[i] = slot_issue_en[i];
            if (slot_issue_en[i]) begin
                automatic sew_e esew = elem_eew(slot_q[i].decoded);

                // Fragment index for data allocation in functional units
                dispatch_last[i].next_frag    = slot_q[i].next_frag;
                dispatch_last[i].is_last      = (slot_q[i].next_frag == slot_q[i].total_frags - 1);
                // Patch register addresses considering LMUL impact
                dispatch_last[i].dispatch_vs1 = view[i].vs1;
                dispatch_last[i].dispatch_vs2 = view[i].vs2;
                dispatch_last[i].dispatch_vd  = view[i].vd;
                dispatch_last[i].row_vs1      = view[i].row_vs1;
                dispatch_last[i].row_vs2      = view[i].row_vs2;
                dispatch_last[i].row_vd       = view[i].row_vd;
                dispatch_last[i].vd_frag      = view[i].vd_frag;
                dispatch_last[i].vd_frag_done = view[i].vd_frag_done;
                dispatch_last[i].elem_base    = vl_t'(slot_q[i].next_frag) * calc_epf(esew);   // source element space
                dispatch_last[i].elements     = calc_elements_for_frag(slot_q[i].decoded.vl, esew,
                                                slot_q[i].decoded.instr_enum, slot_q[i].next_frag);
                // dispatch_last[i].dispatch_raddr1 = slot_q[i].rs1_base + mem_offset[i];
                dispatch_last[i].dispatch_raddr1 = '0;

                // Start from stored metadata
                issue = slot_q[i].issue_meta;
                
                fu_instr_issue[i].instr_issue    = issue;
                fu_instr_issue[i].instr_decoded  = slot_q[i].decoded;
                fu_instr_issue[i].instr_fragment = dispatch_last[i];

                fu_instr_issue_d[i] = fu_instr_issue[i];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < MAX_INFLIGHT; i++)
                fu_instr_issue_q[i] <= '0;
        end else begin
            fu_instr_issue_q <= fu_instr_issue_d;
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
        else if (disp_decoded_i.is_permutation || disp_decoded_i.is_reduction || disp_decoded_i.is_widening || disp_decoded_i.is_narrowing)
            new_fu_id = 2'(FU_VSLD);
        else
            new_fu_id = 2'(FU_VALU);   // arith, reductions, mask ops

        new_slot_free = !slot_q[new_fu_id].valid && !result_pending_q[new_fu_id];

    //     // Instruction-level WAW check
    //     begin
    //         logic [3:0] new_lmul;
    //         new_lmul  = vlmul_to_val(disp_decoded_i.vlmul);
    //         new_waw   = 1'b0;
    //         for (int p = 0; p < MAX_INFLIGHT; p++) begin
    //             if (slot_q[p].valid) begin
    //                 // Overlap if ranges intersect
    //                 if ((disp_decoded_i.vd < slot_q[p].vd_base + 5'(slot_q[p].emul_val)) &&
    //                     (slot_q[p].vd_base  < disp_decoded_i.vd + 5'(new_lmul)))
    //                     new_waw = 1'b1;
    //             end
    //         end
    //     end

        // dispatch_fire = disp_valid_i && new_slot_free && !new_waw;
        // dispatch_fire = disp_valid_i && new_slot_free;
        dispatch_fire = disp_valid_i && new_slot_free && 
                        (disp_decoded_i.fmt != FMT_OPCFG_CSRRCI) &&
                        // ((disp_decoded_i.major_opcode == OPCODE_OP_V) || (disp_decoded_i.major_opcode == OPCODE_LOAD) || (disp_decoded_i.major_opcode == OPCODE_STORE)) &&
                        (disp_decoded_i.major_opcode != OPCODE_SYSTEM);
    end

    assign disp_ready_o = dispatch_fire;
    assign disp_empty_o = !(|slot_valid) && !(|result_pending_q);
    // assign disp_empty_o =!(|slot_issue_en) && !(|result_pending_q);

    //////////////////////
    // Next-state logic //
    //////////////////////

    // Pre-compute result arrivals: which slot completed a fragment this cycle?
    // frag_idx is recovered from the slot's next_frag at the time of issue

    logic [MAX_INFLIGHT-1:0]                 wb_valid;   // fragment writeback this cycle
    logic [MAX_INFLIGHT-1:0][FRAG_CNT_W-1:0] wb_frag;    // which fragment completed
    logic [MAX_INFLIGHT-1:0]                 wb_is_last; // last fragment of instruction
    logic [MAX_INFLIGHT-1:0]                 wb_done;    // last fragment of instruction

    always_comb begin
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            wb_valid[i]   = fu_result[i].xif_fifo_result.result_valid_exec_o && slot_q[i].valid;
            wb_frag[i]    = fu_result[i].instr_fragment.vd_frag;
            wb_is_last[i] = fu_result[i].instr_fragment.is_last;
            wb_done[i]    = fu_result[i].instr_fragment.vd_frag_done;
        end
    end

    always_comb begin
        slot_d = slot_q;

        // Accumulate frag_done_mask from FU results
        // immediately unblocks a waiting instruction next cycle.
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            
            // Free slot when last fragment acknowledged
            if (wb_valid[i] && wb_done[i])
               slot_d[i].frag_done_mask[wb_frag[i]] = 1'b1;

            if (wb_valid[i] && wb_is_last[i])
                slot_d[i].valid = 1'b0;
            
                // $display("%0t: wb_valid=%0b wb_frag=%0d mask(before)=%b mask(after)=%b, total_frags_q=%0d",
                //     $time,
                //     wb_valid[i],
                //     wb_frag[i],
                //     slot_q[i].frag_done_mask,
                //     slot_d[i].frag_done_mask,
                //     slot_q[i].total_frags,);
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
            sew_e veew;
            // lv   = vlmul_to_val(disp_decoded_i.vtype.vlmul, disp_issue_i.instr_issue.req.instr[17:15], (disp_decoded_i.instr_enum == VMVNRR_V)); // Considers CSRs?
            // vsew = disp_decoded_i.vtype.vsew;
            lv   = vlmul_to_val(disp_decoded_i.emul, disp_issue_i.instr_issue.req.instr[17:15], (disp_decoded_i.instr_enum == VMVNRR_V)); // Considers CSRs?
            veew = disp_decoded_i.eew;

            slot_d[new_fu_id].valid          = 1'b1;
            // slot_d[new_fu_id].vd_base        = disp_decoded_i.vd;
            slot_d[new_fu_id].vd_base        = (disp_decoded_i.major_opcode == OPCODE_STORE) ? disp_decoded_i.vs3 : disp_decoded_i.vd;
            slot_d[new_fu_id].vs1_base       = disp_decoded_i.vs1;
            slot_d[new_fu_id].vs2_base       = disp_decoded_i.vs2;
            slot_d[new_fu_id].rs1_base       = disp_decoded_i.rs1_data;
            slot_d[new_fu_id].emul_val       = lv;
            slot_d[new_fu_id].total_frags    = calc_total_frags(
                                                   disp_decoded_i.vl, veew, lv, disp_decoded_i.instr_enum, disp_decoded_i.vtype.vta);
            slot_d[new_fu_id].uses_vs1       = disp_decoded_i.uses_vs1;
            slot_d[new_fu_id].uses_vs2       = disp_decoded_i.uses_vs2;
            slot_d[new_fu_id].uses_vd_src    = disp_decoded_i.uses_vd_src;
            slot_d[new_fu_id].next_frag      = '0;
            slot_d[new_fu_id].frag_done_mask = '0;
            slot_d[new_fu_id].hart_id        = disp_issue_i.instr_issue.req.hartid;
            slot_d[new_fu_id].x_id           = disp_issue_i.instr_issue.req.id;
            slot_d[new_fu_id].decoded        = disp_decoded_i;
            // if (disp_decoded_i.instr_enum == VMV_XS || disp_decoded_i.instr_enum == VMV_SX) slot_d[new_fu_id].decoded.vl = 1;
            slot_d[new_fu_id].issue_meta     = disp_issue_i.instr_issue;
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

    logic [MAX_INFLIGHT-1:0] result_blocked;
    integer                 selected_result;
    logic [X_ID_WIDTH-1:0] selected_result_id;

    always_comb begin
        result_pending_d      = result_pending_q;
        result_pending_data_d = result_pending_data_q;
        result_blocked        = '0;
        selected_result       = -1;
        selected_result_id    = '1;
        x_fifo_res_o = '0;

        // A completed result is blocked while any older instruction is still
        // in flight. Results with gaps in their IDs are handled naturally.
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            for (int j = 0; j < MAX_INFLIGHT; j++) begin
                if (result_pending_q[i] && slot_q[j].valid &&
                    id_is_older( slot_q[j].x_id, result_pending_data_q[i].issue_exec_o.req.id))
                    // (slot_q[j].x_id < result_pending_data_q[i].issue_exec_o.req.id))
                    result_blocked[i] = 1'b1;
            end

            if (result_pending_q[i] && !result_blocked[i] &&
                ((selected_result < 0) ||
                id_is_older( result_pending_data_q[i].issue_exec_o.req.id, selected_result_id ))) begin
                //  (result_pending_data_q[i].issue_exec_o.req.id < selected_result_id))) begin
                selected_result    = i;
                selected_result_id = result_pending_data_q[i].issue_exec_o.req.id;
            end
        end

        if (selected_result >= 0) begin
            x_fifo_res_o = result_pending_data_q[selected_result];

            // Keep valid asserted until the downstream result FIFO accepts it.
            if (!x_fifo_res_full_i && x_fifo_res_o.result_valid_exec_o)
                result_pending_d[selected_result] = 1'b0;
        end

        // Capture only the final fragment as an architectural result. The FU
        // result interface is backpressured while its pending entry is full.
        for (int i = 0; i < MAX_INFLIGHT; i++) begin
            if (fu_result[i].xif_fifo_result.result_valid_exec_o &&
                fu_result[i].instr_fragment.is_last && slot_q[i].valid &&
                !result_pending_q[i]) begin
                result_pending_d[i]      = 1'b1;
                result_pending_data_d[i] = fu_result[i].xif_fifo_result;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            result_pending_q      <= '0;
            result_pending_data_q <= '0;
        end else begin
            result_pending_q      <= result_pending_d;
            result_pending_data_q <= result_pending_data_d;
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