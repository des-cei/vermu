module vpu_stimulus_gen #(
    // CVXIF Types
    parameter  int unsigned NrRgprPorts      = 2,
    parameter  int unsigned XLEN             = 32,
    parameter  type         readregflags_t   = logic,
    parameter  type         writeregflags_t  = logic,
    parameter  type         id_t             = logic,
    parameter  type         hartid_t         = logic,
    parameter  type         x_issue_req_t    = logic,
    parameter  type         x_issue_resp_t   = logic,
    parameter  type         x_register_t     = logic,
    parameter  type         x_commit_t       = logic,
    parameter  type         x_result_t       = logic,
    parameter  type         cvxif_req_t      = logic,
    parameter  type         cvxif_resp_t     = logic,
    localparam type         registers_t      = logic [NrRgprPorts-1:0][XLEN-1:0],
    parameter  int unsigned EXT_XBAR_NMASTER = 1
) (
    input logic clk_i,
    input logic rst_ni,

    // CVXIF Master Interface
    output cvxif_req_t  cvxif_req_o,
    input  cvxif_resp_t cvxif_resp_i
);

  int file_handle;
  int scan_result;
  string stimulus_file;

  logic [31:0] curr_instr, curr_rs1, curr_rs2;
  string curr_mnemonic;

  typedef enum logic [1:0] {
    INIT,
    READ,
    SEND
  } state_t;
  state_t state, next_state;

  initial begin
    if (!$value$plusargs("stimulus_path=%s", stimulus_file)) begin
      stimulus_file = "stimulus.txt";
    end
    file_handle = $fopen(stimulus_file, "r");
    if (!file_handle) $fatal(1, "Cannot open stimulus file: %s", stimulus_file);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state <= INIT;
      cvxif_req_o <= '0;
    end else begin
      state <= next_state;

      case (state)
        READ: begin
          if (!$feof(file_handle)) begin
            scan_result = $fscanf(file_handle, "%h %h %h %s\n", curr_instr, curr_rs1, curr_rs2,
                                  curr_mnemonic);
            if (scan_result == 4) begin
              cvxif_req_o.issue_valid <= 1'b1;
              cvxif_req_o.issue_req.instr <= curr_instr;
              cvxif_req_o.register.rs[0] <= curr_rs1;
              cvxif_req_o.register.rs[1] <= curr_rs2;
            end
          end
        end
        SEND: begin
          if (cvxif_resp_i.issue_ready) begin
            cvxif_req_o.issue_valid <= 1'b0;
          end
        end
        default: ;  // Maintain state
      endcase
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      INIT: next_state = READ;
      READ: if (scan_result == 4) next_state = SEND;
      SEND: if (cvxif_resp_i.issue_ready) next_state = READ;
    endcase
  end
endmodule
