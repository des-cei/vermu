// tb_vpu_vregfile.sv
// -------------------------------------------------------------------------
// Self-checking testbench for vpu_vregfile, using vpu_decoder to turn raw
// (partial) RVV-style instruction words into vpu_decoded_t, and driving the
// if_xif_exe interfaces the same way an execution wrapper would.
//
// Because vpu_decoder's functional case statement switches on the already
// -resolved `vec_instr_e` enum (not on the raw funct6 bits), the raw
// instruction word only needs to carry the fields the decoder actually
// extracts: vm[25], vs2[24:20], vs1/rs1/imm5[19:15], fmt[14:12], vd[11:7],
// and for loads/stores nf[31:29]/mew[28]/mop[27:26]/umop[24:20]/width[14:12].
// funct6[31:26] is captured but not used to steer decoding, so it is left
// as don't-care/zero here.
//
// The dispatch_sideband_t (dispatch_vd/vs1/vs2), which is what
// vpu_vregfile actually uses for addressing, is modeled here the way a
// real dispatcher would build it: straight from the raw instruction's
// vd/vs1/vs2 bit positions, independent of vpu_decoded_t's own vd/vs1/vs2
// fields (which the decoder deliberately leaves 0 for loads/stores, see
// vpu_decoder.sv lines ~769-782).
// -------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_vpu_vregfile;

    import vpu_pkg::*;
    import rvv_instr_pkg::*;
    import cvxif_types_pkg::*;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    localparam time CLK_PERIOD = 10ns;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------------------------------------------------------
    // DUT I/O
    // ---------------------------------------------------------------
    logic [2:0][VPU_VLEN-1:0] wdata;
    logic [2:0][VPU_VLEN-1:0] rdata1;
    logic [2:0][VPU_VLEN-1:0] rdata2;
    logic [2:0][VPU_VLEN-1:0] rdata_vd;

    // Three separately named (non-arrayed) interface instances. Drive
    // tasks below take `fu` and case-dispatch to the matching instance
    // via plain interface ports (not virtual interfaces) - this avoids
    // simulator-specific gaps around arrays/handles of virtual interfaces
    // while still letting one task body serve all three FUs.
    if_xif_exe if_valu ();
    if_xif_exe if_vlsu ();
    if_xif_exe if_vsld ();

    vpu_vregfile u_dut (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        .wdata_i      (wdata),
        .rdata1_o     (rdata1),
        .rdata2_o     (rdata2),
        .rdata_vd_o   (rdata_vd),
        .if_monitor_valu (if_valu.register_file),
        .if_monitor_vlsu (if_vlsu.register_file),
        .if_monitor_vsld (if_vsld.register_file)
    );

    // ---------------------------------------------------------------
    // Decoders (one per FU) - purely combinational
    // ---------------------------------------------------------------
    vpu_issue_t   issue_req   [3];
    logic         dec_valid   [3];
    vtype_t       vtype_cfg   [3];
    vl_t          vl_cfg      [3];
    vl_t          vstart_cfg  [3];
    logic         dec_resp_valid [3];
    vpu_decoded_t decoded     [3];
    logic [XLEN-1:0] avl      [3];

    genvar gi;
    generate
        for (gi = 0; gi < 3; gi++) begin : gen_dec
            vpu_decoder #(
                .XLEN        (XLEN),
                .vpu_issue_t (vpu_pkg::vpu_issue_t)
            ) u_dec (
                .clk_i            (clk),
                .req_valid_i      (dec_valid[gi]),
                .instr_req_i      (issue_req[gi]),
                .vtype_i          (vtype_cfg[gi]),
                .vl_i             (vl_cfg[gi]),
                .vstart_i         (vstart_cfg[gi]),
                .dec_resp_valid_o (dec_resp_valid[gi]),
                .decoded_req_o    (decoded[gi]),
                .avl_o            (avl[gi])
            );
        end
    endgenerate

    // ---------------------------------------------------------------
    // Reference model - independent reimplementation of the merge policy
    // ---------------------------------------------------------------
    vlen_t ref_vreg [NRVREG];

    function automatic vlen_t ref_active_mask(input vpu_decoded_t req);
        vlen_t mask;
        int sew_bits, bpe, elem_cnt, eidx;
        mask     = '0;
        sew_bits = get_sew_bits(req.vtype.vsew);
        bpe      = sew_bits / 8;
        elem_cnt = VPU_VLEN / sew_bits;
        for (int b = 0; b < VLENB; b++) begin
            eidx = b / bpe;
            if (eidx >= req.vstart && eidx < req.vl && eidx < elem_cnt)
                mask[8*b +: 8] = 8'hFF;
        end
        return mask;
    endfunction

//?
    function automatic vlen_t ref_merge(
        input vpu_decoded_t req,
        input vlen_t         result_data,
        input vlen_t         old_vd,
        input vlen_t         v0_mask_reg
    );
        vlen_t merged;
        int sew_bits, bpe, eidx;
        logic in_body, enabled;
        merged   = old_vd;
        sew_bits = get_sew_bits(req.vtype.vsew);
        bpe      = sew_bits / 8;

        if (req.is_load) begin
            unique case (req.width)
                3'b000: bpe = 1;
                3'b101: bpe = 2;
                3'b110: bpe = 4;
                default: ;
            endcase
        end

        for (int b = 0; b < VLENB; b++) begin
            eidx    = b / bpe;
            in_body = (eidx >= req.vstart) && (eidx < req.vl);
            if (in_body) begin
                enabled = req.vm || v0_mask_reg[eidx];
                if (enabled)
                    merged[8*b +: 8] = result_data[8*b +: 8];
                else if (req.vtype.vma)
                    merged[8*b +: 8] = 8'hFF;
            end else if ((eidx >= req.vl) && req.vtype.vta) begin
                merged[8*b +: 8] = 8'hFF;
            end
        end
        return merged;
    endfunction

    // ---------------------------------------------------------------
    // Bookkeeping
    // ---------------------------------------------------------------
    int errors = 0;
    int checks = 0;

    task automatic check_vlen(input vlen_t exp, input vlen_t got, input string msg);
        checks++;
        if (exp !== got) begin
            errors++;
            $error("[FAIL] %s\n  expected = %h\n  got      = %h", msg, exp, got);
        end else begin
            $display("[PASS] %s", msg);
        end
    endtask

    //////////////
    // Encoding //
    //////////////

    function automatic logic [31:0] enc_vv(
        input logic vm, input logic [4:0] vs2, input logic [4:0] vs1, input logic [4:0] vd
    );
        return {6'd0, vm, vs2, vs1, FMT_OPIVV, vd, OPCODE_OP_V};    
    endfunction

    function automatic logic [31:0] enc_vx(
        input logic vm, input logic [4:0] vs2, input logic [4:0] vd
    );
        return {6'd0, vm, vs2, 5'd0, FMT_OPIVX, vd, OPCODE_OP_V};
    endfunction

    function automatic logic [31:0] enc_vi(
        input logic vm, input logic [4:0] vs2, input logic [4:0] imm5, input logic [4:0] vd
    );
        return {6'd0, vm, vs2, imm5, FMT_OPIVI_CSRRC, vd, OPCODE_OP_V};
    endfunction

    // Unit-stride load/store. width: 000=8b,101=16b,110=32b EEW.
    function automatic logic [31:0] enc_ls_unit_stride(
        input logic vm, input logic [2:0] width, input logic [4:0] vd_vs3, input logic is_store
    );
        // [31:29]=nf=0 [28]=mew=0 [27:26]=mop=00(unit-stride) [25]=vm
        // [24:20]=umop=00000(unit-stride, not mask-load/whole-reg) [19:15]=rs1(unused,val via register.rs)
        // [14:12]=width [11:7]=vd/vs3 [6:0]=opcode
        return {3'd0, 1'b0, 2'b00, vm, 5'b00000, 5'd0, width, vd_vs3,
                (is_store ? OPCODE_STORE : OPCODE_LOAD)};
    endfunction

    function automatic dispatch_sideband_t make_frag(input logic [31:0] raw_instr);
        dispatch_sideband_t f;
        f              = '0;
        f.is_last      = 1'b1;
        f.dispatch_vd  = raw_instr[11:7];
        f.dispatch_vs1 = raw_instr[19:15];
        f.dispatch_vs2 = raw_instr[24:20];
        return f;
    endfunction

    /////////////
    // Drivers //
    //////////////

    // Runs the raw instruction through the real decoder for the given FU
    task automatic decode_instr(
        input  int              fu,
        input  vec_instr_e      vinstr,
        input  logic [31:0]     raw_instr,
        input  vtype_t          vt,
        input  vl_t             vl_c,
        input  vl_t             vstart_c,
        input  logic [XLEN-1:0] rs1_val,
        input  logic [XLEN-1:0] rs2_val,
        output vpu_decoded_t    decoded_out
    );
        vpu_issue_t iss;
        iss                          = '0;
        iss.vec_instr                = vinstr;
        iss.instr_issue.req.instr    = raw_instr;
        iss.instr_issue.resp.writeback = 1'b1;
        iss.instr_issue.register.rs[0] = rs1_val;
        iss.instr_issue.register.rs[1] = rs2_val;

        issue_req[fu]  = iss;
        vtype_cfg[fu]  = vt;
        vl_cfg[fu]     = vl_c;
        vstart_cfg[fu] = vstart_c;
        dec_valid[fu]  = 1'b1;
        #1;
        decoded_out    = decoded[fu];
    endtask

    // Drives one write into the DUT for FU `fu`, and mirrors it into the
    // reference model. `fu` fans out to one of the three named interface
    // instances via a case statement (kept as three plain instances,
    // rather than an array, for maximum simulator portability).
    task automatic rf_write(
        input int           fu,
        input vpu_decoded_t decoded_req,
        input dispatch_sideband_t frag,
        input vlen_t         result_data
    );
        x_issue_fifo_res_t fifo_res;
        fifo_res = '0;
        fifo_res.result_valid_exec_o = 1'b1;

        @(negedge clk);
        unique case (fu)
            FU_VALU: begin
                if_valu.exe_wrapper_result.xif_fifo_result = fifo_res;
                if_valu.exe_wrapper_result.instr_decoded   = decoded_req;
                if_valu.exe_wrapper_result.instr_fragment  = frag;
            end
            FU_VLSU: begin
                if_vlsu.exe_wrapper_result.xif_fifo_result = fifo_res;
                if_vlsu.exe_wrapper_result.instr_decoded   = decoded_req;
                if_vlsu.exe_wrapper_result.instr_fragment  = frag;
            end
            FU_VSLD: begin
                if_vsld.exe_wrapper_result.xif_fifo_result = fifo_res;
                if_vsld.exe_wrapper_result.instr_decoded   = decoded_req;
                if_vsld.exe_wrapper_result.instr_fragment  = frag;
            end
        endcase
        wdata[fu] = result_data;

        // Mirror into the reference model at the same edge the DUT uses.
        if (!decoded_req.is_store && (frag.dispatch_vd < NRVREG)) begin
            ref_vreg[frag.dispatch_vd] = ref_merge(
                decoded_req, result_data, ref_vreg[frag.dispatch_vd], ref_vreg[0]
            );
        end

        @(posedge clk);
        @(negedge clk);
        unique case (fu)
            FU_VALU: if_valu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o = 1'b0;
            FU_VLSU: if_vlsu.exe_wrapper_result.xif_fifo_result.result_valid_exec_o = 1'b0;
            FU_VSLD: if_vsld.exe_wrapper_result.xif_fifo_result.result_valid_exec_o = 1'b0;
        endcase
        dec_valid[fu] = 1'b0;
    endtask

    // Reads back the full (unmasked) 256b content of a vector register
    // through port 2 (vs2) of the given FU, bypassing the decoder by
    // building a minimal decoded request directly (SEW=8, vl=VLENB,
    // vstart=0, vm=1 => active_elements_mask covers the whole register).
    task automatic read_full(input int fu, input logic [4:0] reg_addr, output vlen_t val);
        vpu_decoded_t d;
        dispatch_sideband_t f;
        d               = '0;
        d.vtype.vsew    = SEW_8;
        d.vl             = VLENB;
        d.vstart         = '0;
        d.vm             = 1'b1;
        f                = '0;
        f.dispatch_vs2   = reg_addr;

        unique case (fu)
            FU_VALU: begin
                if_valu.exe_wrapper_result.instr_decoded  = d;
                if_valu.exe_wrapper_result.instr_fragment = f;
            end
            FU_VLSU: begin
                if_vlsu.exe_wrapper_result.instr_decoded  = d;
                if_vlsu.exe_wrapper_result.instr_fragment = f;
            end
            FU_VSLD: begin
                if_vsld.exe_wrapper_result.instr_decoded  = d;
                if_vsld.exe_wrapper_result.instr_fragment = f;
            end
        endcase
        #1;
        val = rdata2[fu];
    endtask

    // ---------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------
    vtype_t vt_e32_ma_ta;   // sew32, vma=1, vta=1
    vtype_t vt_e32_undist;  // sew32, vma=0, vta=0 (undisturbed policy)
    vtype_t vt_e8_undist;

    vpu_decoded_t d;
    dispatch_sideband_t f;
    logic [31:0] raw;
    vlen_t got, exp, mask_data;

    initial begin
        rst_n = 1'b0;
        wdata = '0;
        for (int fu = 0; fu < 3; fu++) begin
            dec_valid[fu]  = 1'b0;
            vtype_cfg[fu]  = '0;
            vl_cfg[fu]     = '0;
            vstart_cfg[fu] = '0;
            issue_req[fu]  = '0;
        end
        if_valu.exe_wrapper_result = '0;
        if_vlsu.exe_wrapper_result = '0;
        if_vsld.exe_wrapper_result = '0;
        for (int r = 0; r < NRVREG; r++) ref_vreg[r] = '0;

        vt_e32_ma_ta  = '{vill: 1'b0, vma: 1'b1, vta: 1'b1, vsew: SEW_32, vlmul: LMUL_1};
        vt_e32_undist = '{vill: 1'b0, vma: 1'b0, vta: 1'b0, vsew: SEW_32, vlmul: LMUL_1};
        vt_e8_undist  = '{vill: 1'b0, vma: 1'b0, vta: 1'b0, vsew: SEW_8,  vlmul: LMUL_1};

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // -----------------------------------------------------------
        // T1: reset clears all registers
        // -----------------------------------------------------------
        read_full(FU_VALU, 5'd1, got);
        check_vlen('0, got, "T1: v1 reads 0 after reset");

        // -----------------------------------------------------------
        // T2: VADD_VV, unmasked, full vl -> whole 256b register written
        // -----------------------------------------------------------
        raw = enc_vv(1'b1, 5'd2, 5'd3, 5'd1);  // vm=1(unmasked), vs2=2, vs1=3, vd=1
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);

        mask_data = {8{32'hDEAD_BEEF}};
        $display("DEBUG raw=%h d.is_store=%0d d.vl=%0d d.vstart=%0d frag.vd=%0d frag.vs1=%0d frag.vs2=%0d",
                  raw, d.is_store, d.vl, d.vstart, f.dispatch_vd, f.dispatch_vs1, f.dispatch_vs2);
        rf_write(FU_VALU, d, f, mask_data);
        $display("DEBUG after write: vreg[1]=%h rf_we=%b",
                  u_dut.vreg[1], u_dut.rf_we);

        read_full(FU_VALU, 5'd1, got);
        check_vlen(mask_data, got, "T2: unmasked full-vl write lands exactly in v1");

        // -----------------------------------------------------------
        // T3: masked write, vma=0 (undisturbed) - v0 supplies the mask,
        //     element 0 disabled must retain old value, element 1 enabled
        //     must take new data (SEW=32 => 4-byte elements, VPU_VLEN=256
        //     => 8 elements. v0[0]=0, v0[1]=1, rest can be 0/don't-care
        //     with vl limited to 2 so tail policy doesn't interfere.)
        // -----------------------------------------------------------
        // seed v0 mask register directly (vd=0) with element0=0, element1=1
        raw = enc_vv(1'b1, 5'd0, 5'd0, 5'd0);
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VALU, d, f, 256'h2); // bit1=1 (element index 1 enabled)

        // seed v4 = known old value before the masked write
        raw = enc_vv(1'b1, 5'd0, 5'd0, 5'd4);
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VALU, d, f, {8{32'hAAAA_AAAA}});

        // masked write into v4, vl=2, vstart=0, vm=0, vma=0/vta=0 => undisturbed
        raw = enc_vv(1'b0, 5'd2, 5'd3, 5'd4);
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_undist, 32'd2, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VALU, d, f, {8{32'h1111_1111}});

        read_full(FU_VALU, 5'd4, got);
        exp = {{6{32'hAAAA_AAAA}}, 32'h1111_1111, 32'hAAAA_AAAA}; // elem7..2=old, elem1=new, elem0=old(undisturbed)
        check_vlen(exp, got, "T3: masked write, undisturbed inactive elements, new data on enabled element");

        // -----------------------------------------------------------
        // T4: mask-agnostic (vma=1) - disabled element becomes all-1s
        // -----------------------------------------------------------
        raw = enc_vv(1'b1, 5'd0, 5'd0, 5'd5);
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VALU, d, f, {8{32'h5555_5555}});

        raw = enc_vv(1'b0, 5'd2, 5'd3, 5'd5); // vm=0, masked, vma=1/vta=1
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, 32'd2, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VALU, d, f, {8{32'h2222_2222}});

        read_full(FU_VALU, 5'd5, got);
        exp = {{6{32'hFFFF_FFFF}}, 32'h2222_2222, 32'hFFFF_FFFF}; // elem0 disabled->0xFF..., elem1 enabled->new, tail(2..7)->0xFF via vta
        check_vlen(exp, got, "T4: mask-agnostic disabled element and tail-agnostic tail both go to all-ones");

        // -----------------------------------------------------------
        // T5: is_store must never write back
        // -----------------------------------------------------------
        raw = enc_ls_unit_stride(1'b1, 3'b010, 5'd6, 1'b1); // VSE32_V into "v6" (vs3 field)
        decode_instr(FU_VLSU, VSE32_V, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VLSU, d, f, {8{32'hFEED_FACE}});

        read_full(FU_VLSU, 5'd6, got);
        check_vlen('0, got, "T5: VSE32_V (store) does not modify the vector register file");

        // -----------------------------------------------------------
        // T6: narrower EEW load merge (VLE8_V into wide SEW=32 vtype
        //     context) - bpe should come from width, not vtype.vsew
        // -----------------------------------------------------------
        raw = enc_ls_unit_stride(1'b1, 3'b000, 5'd7, 1'b0); // VLE8_V, width=000 => 1B/elem
        decode_instr(FU_VLSU, VLE8_V, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        rf_write(FU_VLSU, d, f, {8{32'h01234567}});

        read_full(FU_VLSU, 5'd7, got);
        check_vlen({8{32'h01234567}}, got,
            "T6: VLE8_V with vl=VLENB(byte count) merges byte-granular EEW=8 data");

        // -----------------------------------------------------------
        // T7: concurrent writes from two different FUs to two different
        //     destination registers commit in the same cycle
        // -----------------------------------------------------------
        raw = enc_vv(1'b1, 5'd0, 5'd0, 5'd10);
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);

        begin
            vpu_decoded_t d2;
            dispatch_sideband_t f2;
            logic [31:0] raw2;
            raw2 = enc_vv(1'b1, 5'd0, 5'd0, 5'd11);
            decode_instr(FU_VSLD, VADD_VV, raw2, vt_e32_ma_ta, VLENB, '0, '0, '0, d2);
            f2 = make_frag(raw2);

            fork
                rf_write(FU_VALU, d, f, {8{32'hC0FF_EE00}});
                rf_write(FU_VSLD, d2, f2, {8{32'h5EED_1234}});
            join
        end

        read_full(FU_VALU, 5'd10, got);
        check_vlen({8{32'hC0FF_EE00}}, got, "T7a: FU_VALU concurrent write landed in v10");
        read_full(FU_VSLD, 5'd11, got);
        check_vlen({8{32'h5EED_1234}}, got, "T7b: FU_VSLD concurrent write landed in v11");

        // -----------------------------------------------------------
        // T8: out-of-range destination (>= NRVREG) must be gated off
        // -----------------------------------------------------------
        raw = enc_vv(1'b1, 5'd0, 5'd0, 5'd1); // reuse vd=1 encoding, override frag below
        decode_instr(FU_VALU, VADD_VV, raw, vt_e32_ma_ta, VLENB, '0, '0, '0, d);
        f = make_frag(raw);
        f.dispatch_vd = 5'd31; // still legal (NRVREG=32, so 31 is valid) -> use a truly OOB proxy instead
        // NRVREG = 32 with a 5-bit field means no encodable address is actually
        // out-of-range; instead verify the "vd < NRVREG" guard for reads with a
        // legal high address, and rely on functional coverage of T1-T7 for the
        // guard logic itself.
        rf_write(FU_VALU, d, f, {8{32'hABCD_EF01}});
        read_full(FU_VALU, 5'd31, got);
        check_vlen({8{32'hABCD_EF01}}, got, "T8: highest addressable register (v31) writes correctly");

        // -----------------------------------------------------------
        $display("\n=================================================");
        $display(" tb_vpu_vregfile: %0d checks run, %0d failed", checks, errors);
        $display("=================================================\n");
        if (errors != 0) $fatal(1, "TESTBENCH FAILED");
        $finish;
    end

    // Safety timeout
    initial begin
        #(CLK_PERIOD * 2000);
        $fatal(1, "TIMEOUT: testbench did not finish");
    end

endmodule