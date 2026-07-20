

// Your typedefs, now package-scoped
package cvxif_types_pkg;

    parameter int unsigned X_NUM_RS       = 3;  
    parameter int unsigned X_ID_WIDTH     = 4;
    parameter int unsigned X_RFR_WIDTH    = 32;
    parameter int unsigned X_RFW_WIDTH    = 32;
    parameter int unsigned X_HARTID_WIDTH = 1;
    parameter int unsigned X_DUAL_READ    = 0;
    parameter int unsigned X_DUAL_WRITE   = 0;

    typedef struct packed {
        int unsigned X_NUM_RS;
        int unsigned X_DUALREAD;
        int unsigned X_DUALWRITE;
        int unsigned X_ID_WIDTH;
        int unsigned X_HARTID_WIDTH;
        int unsigned X_RFR_WIDTH;
        int unsigned X_RFW_WIDTH;
    } CVE2Cfg_t;

    // Build the config struct once inside the package
    localparam CVE2Cfg_t CVE2Cfg = '{
        X_NUM_RS,
        X_DUAL_READ,
        X_DUAL_WRITE,
        X_ID_WIDTH,
        X_HARTID_WIDTH,
        X_RFR_WIDTH,
        X_RFW_WIDTH
    };

    typedef logic [X_NUM_RS+X_DUAL_READ-1:0] readregflags_t;
    typedef logic [X_DUAL_WRITE:0]           writeregflags_t;
    typedef logic [X_ID_WIDTH-1:0]           id_t;
    typedef logic [X_HARTID_WIDTH-1:0]       hartid_t;

    // Issue Interface
    typedef struct packed {
        logic [31:0] instr;
        hartid_t     hartid;
        id_t         id;
    } x_issue_req_t;

    typedef struct packed {
        logic           accept;
        writeregflags_t writeback;
        readregflags_t  register_read;
    } x_issue_resp_t;

    // Register Interface
    typedef struct packed {
        hartid_t                              hartid;
        id_t                                  id;
        logic [X_NUM_RS-1:0][X_RFR_WIDTH-1:0] rs;
        readregflags_t                        rs_valid;
    } x_register_t;

    // Commit Interface
    typedef struct packed {
        hartid_t hartid;
        id_t     id;
        logic    commit_kill;
    } x_commit_t;

    // Result Interface
    typedef struct packed {
        hartid_t                hartid;
        id_t                    id;
        logic [X_RFW_WIDTH-1:0] data;
        logic [4:0]             rd;
        writeregflags_t         we;
    } x_result_t;

    // XIF Wrapper struct types
    // FIFO packed signals - We will input req and resp per instr
    typedef struct packed {
        x_issue_req_t  req;
        x_issue_resp_t resp;
        x_register_t   register;
    } x_issue_t;

    // Structure for PRE-DECODER    
    typedef struct packed {
        logic [31:0]              instr;
        logic [31:0]              mask;
        x_issue_resp_t            resp;
    } copro_issue_resp_t;

    // FIFO result packed signals  
    typedef struct packed{
        logic [X_RFW_WIDTH     -1:0]    result_data_exec_o;  // Result data from execution block
        logic                           result_valid_exec_o; // Result valid from execution block //TODO: not necessary
        x_issue_t                       issue_exec_o;        //Output from execution block
    }x_issue_fifo_res_t; 

endpackage
