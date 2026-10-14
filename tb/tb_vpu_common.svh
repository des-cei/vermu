// -----------------------------------------------------------------------------
// tb_vpu_common.svh : shared VPU testbench infrastructure (included INSIDE a module)
//
//   CV-X-IF model --> vpu_top --> OBI memory model
//
// It provides:
//   clk_i / rst_ni, DUT, xif_model, mem          (the three blocks above)
//   do_reset()                                   reset sequence
//   fail() / check() / case_errors / ...         error bookkeeping
//   configure_vtype(sew, lmul_log2, avl, exp_vl) vsetvli / vsetivli + vl check
//   issue_instr(instr, rs1, expect_accept, ...)  issue, check accept/reject, wait result
//   issue_instr_res(..., accepted, res)          same, also returns the x_result_t
//   read_elem(base, idx, sew)                    element read from the memory model
//   X_RD_VL / X_AVL / X_ADDR / X_SCALAR          scalar register indices used by tests
// -----------------------------------------------------------------------------

    // Scalar registers used by the tests (the model passes the value directly)
    localparam logic [4:0] X_RD_VL   = 5'd1;
    localparam logic [4:0] X_AVL     = 5'd10;   // AVL value for vsetvli
    localparam logic [4:0] X_ADDR    = 5'd11;   // base address of loads/stores
    localparam logic [4:0] X_SCALAR  = 5'd12;   // scalar operand of .vx instructions

    localparam int unsigned AVL_MAX  = 16'hFFFF; // "give me VLMAX"

    //----------------------------------------------------------------------
    // Signals
    //----------------------------------------------------------------------
    logic clk_i;
    logic rst_ni;

    logic          x_issue_valid;
    logic          x_issue_ready;
    x_issue_req_t  x_issue_req;
    x_issue_resp_t x_issue_resp;
    logic          x_register_valid;
    logic          x_register_ready;
    x_register_t   x_register;
    logic          x_commit_valid;
    x_commit_t     x_commit;
    logic          x_result_valid;
    logic          x_result_ready;
    x_result_t     x_result;

    obi_req_t  [NUM_PORTS-1:0] obi_req;
    obi_resp_t [NUM_PORTS-1:0] obi_resp;

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    //----------------------------------------------------------------------
    // DUT + models
    //----------------------------------------------------------------------
    vpu_top #(
        .NrRgprPorts    (X_NUM_RS),
        .XLEN           (X_RFR_WIDTH),
        .readregflags_t (readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t           (id_t),
        .hartid_t       (hartid_t),
        .x_issue_req_t  (x_issue_req_t),
        .x_issue_resp_t (x_issue_resp_t),
        .x_register_t   (x_register_t),
        .x_commit_t     (x_commit_t),
        .x_result_t     (x_result_t),
        .obi_req_t      (obi_req_t),
        .obi_resp_t     (obi_resp_t)
    ) dut (
        .clk_i,
        .rst_ni,
        .x_issue_valid_i   (x_issue_valid),
        .x_issue_ready_o   (x_issue_ready),
        .x_issue_req_i     (x_issue_req),
        .x_issue_resp_o    (x_issue_resp),
        .x_register_i      (x_register),
        .x_register_valid_i(x_register_valid),
        .x_register_ready_o(x_register_ready),
        .x_commit_valid_i  (x_commit_valid),
        .x_commit_i        (x_commit),
        .x_result_valid_o  (x_result_valid),
        .x_result_ready_i  (x_result_ready),
        .x_result_o        (x_result),
        .masters_resp_i    (obi_resp),
        .masters_req_o     (obi_req)
    );

    cvxif_cpu_model xif_model (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .x_issue_valid_o    (x_issue_valid),
        .x_issue_ready_i    (x_issue_ready),
        .x_issue_req_o      (x_issue_req),
        .x_issue_resp_i     (x_issue_resp),
        .x_register_o       (x_register),
        .x_register_valid_o (x_register_valid),
        .x_register_ready_i (x_register_ready),
        .x_commit_valid_o   (x_commit_valid),
        .x_commit_o         (x_commit),
        .x_result_i         (x_result),
        .x_result_valid_i   (x_result_valid),
        .x_result_ready_o   (x_result_ready)
    );

    obi_mem_model #(
        .PORTS        (NUM_PORTS),
        .DATA_W       (OBI_DATA_W),
        .GNT_STALL_PCT(GNT_STALL_PCT),
        .RSP_LATENCY  (RSP_LATENCY),
        .RSP_EXTRA_MAX(RSP_EXTRA_MAX)
    ) mem (
        .clk_i (clk_i),
        .rst_ni(rst_ni),
        .req_i (obi_req),
        .resp_o(obi_resp)
    );

    //----------------------------------------------------------------------
    // Reset
    //----------------------------------------------------------------------
    id_t next_id;

    task automatic do_reset();
        rst_ni  = 1'b0;
        next_id = '0;
        repeat (3) @(posedge clk_i);
        rst_ni  = 1'b1;
        repeat (2) @(posedge clk_i);
    endtask

    // Global watchdog
    initial begin
        #50ms;
        $fatal(1, "Global timeout");
    end

    //----------------------------------------------------------------------
    // Bookkeeping
    //----------------------------------------------------------------------
    int unsigned error_count  = 0;
    int unsigned case_count   = 0;
    int unsigned case_failed  = 0;
    int unsigned case_errors  = 0;            // errors of the case being run

    task automatic fail(input string msg);
        error_count++;
        case_errors++;
        if (case_errors <= 6)                 // do not flood the log
            $error("[%0t] %s", $time, msg);
    endtask

    task automatic check(input bit cond, input string msg);
        if (!cond) fail(msg);
    endtask

    //----------------------------------------------------------------------
    // Instruction helpers
    //----------------------------------------------------------------------
    function automatic id_t alloc_id();
        id_t id = next_id;
        next_id++;
        return id;
    endfunction

    // vsetvli / vsetivli (immediate form when avl <= 31) and check of the returned vl
    task automatic configure_vtype(input int sew, input int lmul_log2, input int avl,
                                   input int exp_vl);
        logic [10:0] vtype = vtb_vtype(sew, lmul_log2, VTA, VMA);
        id_t         id    = alloc_id();
        x_result_t   res;
        logic [31:0] instr;
        bit          accepted;

        if (avl <= 31) instr = vtb_vsetivli(X_RD_VL, 5'(avl), vtype);
        else           instr = vtb_vsetvli (X_RD_VL, X_AVL,   vtype);

        xif_model.queue_instruction(instr, HARTID, id, avl, 0);
        xif_model.wait_issue_resp(id, accepted);
        if (!accepted) fail($sformatf("vsetvli with ID=%h REJECTED", id));
        xif_model.wait_for_result(id, res);

        check(32'(res.data) == 32'(exp_vl),
              $sformatf("vl mismatch: got %0d, expected %0d", 32'(res.data), exp_vl));
    endtask

    // Issue any instruction. Checks accept/reject against the expectation and,
    // if accepted, waits for its result and returns it. 'rs1' is the value of the
    // scalar operand.
    task automatic issue_instr_res(input logic [31:0] instr, input logic [31:0] rs1,
                                   input bit expect_accept, input string tag,
                                   output bit accepted, output x_result_t res);
        id_t id = alloc_id();

        res = '0;
        xif_model.queue_instruction(instr, HARTID, id, rs1, 0);
        xif_model.wait_issue_resp(id, accepted);

        if (accepted !== expect_accept)
            fail($sformatf("%s: instruction with ID=%h  %s but %s was expected", tag, id,
                           accepted ? "ACCEPTED" : "REJECTED",
                           expect_accept ? "accept" : "reject"));

        if (accepted) xif_model.wait_for_result(id, res);
    endtask

    // Same, when the result is not needed
    task automatic issue_instr(input logic [31:0] instr, input logic [31:0] rs1,
                               input bit expect_accept, input string tag,
                               output bit accepted);
        x_result_t res;
        issue_instr_res(instr, rs1, expect_accept, tag, accepted, res);
    endtask

    //----------------------------------------------------------------------
    // Memory helpers
    //----------------------------------------------------------------------
    // Element 'idx' (SEW bits, little endian) starting at byte address 'base'
    function automatic logic [31:0] read_elem(input bit [31:0] base, input int idx,
                                              input int sew);
        logic [31:0] v = '0;
        for (int b = 0; b < sew / 8; b++)
            v[8*b +: 8] = mem.read8(base + idx * (sew / 8) + b);
        return v;
    endfunction
