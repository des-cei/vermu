module tb_vpu_top;

    logic clk_i;
    logic rst_ni;

    // Clock generation
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; // 100MHz clock
    end

    // Reset sequence
    initial begin
        rst_ni = 0;
        #20 rst_ni = 1;
    end


    `include "cvxif_types.svh"

    // CVXIF Types
    typedef `READREGFLAGS_T(cvxif_types_pkg::CVE2Cfg) readregflags_t;
    typedef `WRITEREGFLAGS_T(cvxif_types_pkg::CVE2Cfg) writeregflags_t;
    typedef `ID_T(cvxif_types_pkg::CVE2Cfg) id_t;
    typedef `HARTID_T(cvxif_types_pkg::CVE2Cfg) hartid_t;


    typedef `X_ISSUE_REQ_T(cvxif_types_pkg::CVE2Cfg, hartid_t, id_t) x_issue_req_t;
    typedef `X_ISSUE_RESP_T(cvxif_types_pkg::CVE2Cfg, writeregflags_t, readregflags_t) x_issue_resp_t;
    typedef `X_REGISTER_T(cvxif_types_pkg::CVE2Cfg, hartid_t, id_t, readregflags_t) x_register_t;
    typedef `X_COMMIT_T(cvxif_types_pkg::CVE2Cfg, hartid_t, id_t) x_commit_t;
    typedef `X_RESULT_T(cvxif_types_pkg::CVE2Cfg, hartid_t, id_t, writeregflags_t) x_result_t;


    typedef `CVXIF_REQ_T(cvxif_types_pkg::CVE2Cfg, x_issue_req_t, x_register_t, x_commit_t) cvxif_req_t;
    typedef `CVXIF_RESP_T(cvxif_types_pkg::CVE2Cfg, x_issue_resp_t, x_result_t) cvxif_resp_t;

    // CVXIF interface
    cvxif_req_t  cvxif_req;
    cvxif_resp_t cvxif_resp;

    vpu_stimulus_gen #(
        .NrRgprPorts(cvxif_types_pkg::CVE2Cfg.X_NUM_RS),
        .XLEN(32),
        .readregflags_t(readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t(id_t),
        .hartid_t(hartid_t),
        .x_issue_req_t(x_issue_req_t),
        .x_issue_resp_t(x_issue_resp_t),
        .x_register_t(x_register_t),
        .x_commit_t(x_commit_t),
        .x_result_t(x_result_t),
        .cvxif_req_t(cvxif_req_t),
        .cvxif_resp_t(cvxif_resp_t)
    ) i_stim_gen (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .cvxif_req_o  (cvxif_req),
        .cvxif_resp_i (cvxif_resp)
    );

    vpu #(
        .NrRgprPorts(cvxif_types_pkg::CVE2Cfg.X_NUM_RS),
        .XLEN(32),
        .readregflags_t(readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t(id_t),
        .hartid_t(hartid_t),
        .x_issue_req_t(x_issue_req_t),
        .x_issue_resp_t(x_issue_resp_t),
        .x_register_t(x_register_t),
        .x_commit_t(x_commit_t),
        .x_result_t(x_result_t),
        .cvxif_req_t(cvxif_req_t),
        .cvxif_resp_t(cvxif_resp_t)
    ) i_vpu (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .cvxif_req_i  (cvxif_req),
        .cvxif_resp_o (cvxif_resp), 
        .masters_resp_i('0), 
        .masters_req_o () 
    );

    vpu_pipeline_checker #(
        .NrRgprPorts(cvxif_types_pkg::CVE2Cfg.X_NUM_RS),
        .XLEN(32),
        .readregflags_t(readregflags_t),
        .writeregflags_t(writeregflags_t),
        .id_t(id_t),
        .hartid_t(hartid_t),
        .x_issue_req_t(x_issue_req_t),
        .x_issue_resp_t(x_issue_resp_t),
        .x_register_t(x_register_t),
        .x_commit_t(x_commit_t),
        .x_result_t(x_result_t),
        .cvxif_req_t(cvxif_req_t),
        .cvxif_resp_t(cvxif_resp_t)
    ) i_checker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .cvxif_req_i    (cvxif_req),
        .cvxif_resp_i   (cvxif_resp),
        .vpu_dbg_operation_i         (i_vpu.debug_if.operation),
        .vpu_dbg_rdata1_i            (i_vpu.debug_if.rdata1),
        .vpu_dbg_rdata2_i            (i_vpu.debug_if.vrf_rdata2),
        .vpu_dbg_vd_old_i            (i_vpu.debug_if.vrf_vd_data),
        .vpu_dbg_simd_result_valid_i (i_vpu.debug_if.simd_result_valid),
        .vpu_dbg_result_i            (i_vpu.debug_if.result)
    );

endmodule