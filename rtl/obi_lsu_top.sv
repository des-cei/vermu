// Load-store Unit for misalignment support

module obi_lsu_top
 import obi_pkg::*;
 import vpu_pkg::*;
 import cvxif_types_pkg::*;
 #(
    parameter type opcode_t                  = logic,
    parameter  int unsigned EXT_XBAR_NMASTER = 1
 )(
    input logic      clk_i,   
    input logic      rst_ni,
    input  vpu_req_t vpu_req_i,
    input  vl_t      vl_i,
    input  xlen_t    vlmax_i,
    input logic      state_was_busy_i,
    input vlen_t     vrf_rdata_i,            // Input data 
    input logic      vrf_rdata_done_i,       
    output vlen_t    vrf_wdata_o,            // Data to VRF 
    output logic     lsu_vrf_we_o,           // Write in VRF 
    output logic     lsu_rdata_valid_o,       
    output logic     lsu_result_valid_o,     // Load-store done in LSU unit

    input obi_resp_t masters_resp_i,
    output obi_req_t masters_req_o
);

    logic lsu_we, lsu_req, addr_incr_req, lsu_busy, data_pmp_err;
    logic vrf_rdata_done_q;
    logic lsu_resp_valid_q;
    logic [1:0] lsu_type;
    vl_t         req_idx, req_idx_next, active_req_idx;
    logic [2:0]  elem_bytes;
    logic [31:0] lsu_wdata, lsu_rdata;
    logic [31:0] adder_result_ex;
    logic [31:0] base_addr;
    logic [31:0] current_element_addr;
    logic [31:0] next_word_addr;
    logic        lsu_resp_valid;

    // Buffer signals
    logic [VLEN-1:0] int_buff;   
    vl_t             buff_counter;   
    logic            buff_ready, buff_ready_q;    
    

 
    load_store_unit_mis load_store_unit_mis_i (
        .clk_i           (clk_i), 
        .rst_ni          (rst_ni),
        .data_req_o      (masters_req_o.req),
        .data_gnt_i      (masters_resp_i.gnt),
        .data_rvalid_i   (masters_resp_i.rvalid),  
        .data_err_i      ('0),  
        .data_pmp_err_i  ('0), 
        .data_addr_o     (masters_req_o.addr),
        .data_we_o       (masters_req_o.we),
        .data_be_o       (masters_req_o.be),
        .data_wdata_o    (masters_req_o.wdata),
        .data_rdata_i    (masters_resp_i.rdata),
        //EX stage
        .lsu_we_i         (lsu_we),             
        .lsu_type_i       (lsu_type),        
        .lsu_wdata_i      (lsu_wdata),          
        .lsu_sign_ext_i   ('0),    
        .lsu_rdata_o      (lsu_rdata),          
        .lsu_rdata_valid_o(lsu_rdata_valid_o),  
        .lsu_req_i        (lsu_req),         
        .adder_result_ex_i(adder_result_ex), 
        .addr_incr_req_o  (addr_incr_req),   
                        
        .addr_last_o      (),       
                                      
        .lsu_resp_valid_o(lsu_resp_valid),     
        .load_err_o      (),
        .store_err_o     (),
        .busy_o          (lsu_busy),
        .perf_load_o     (),
        .perf_store_o    ()
    );

    ///////////////////
    // Control Logic //
    ///////////////////

    assign base_addr = vpu_req_i.rs1;
    
    // Address Generation
    always_comb begin
        lsu_req             = '0;
        lsu_we              = '0;
        lsu_result_valid_o  = '0;
        elem_bytes          = '0;
        active_req_idx      = '0;
        current_element_addr= '0;
        next_word_addr      = '0;
        adder_result_ex     = '0;
        lsu_type            = '0;

        unique case (vpu_req_i.width)
            W_8:  elem_bytes = 3'd1;
            W_16: elem_bytes = 3'd2;
            W_32: elem_bytes = 3'd4;
            default: ;
        endcase
        
        active_req_idx = (!state_was_busy_i) ? 5'd0 : req_idx;

        //Load-store stride type
        unique case (vpu_req_i.mop)
            2'b00: begin 
                unique case (vpu_req_i.lumop)
                    5'b00000:  current_element_addr = base_addr + (active_req_idx * elem_bytes);  //unit-stride
                    default: ;                                           
                endcase 
            end
            2'b10: begin 
                current_element_addr = base_addr + (active_req_idx * vpu_req_i.rs2);
            end 
            default:;                                                  //TODO: LS full support
        endcase

        // Calculate misalignment increment
        next_word_addr = {current_element_addr[31:2], 2'b00} + 32'd4;   
        adder_result_ex = addr_incr_req ? next_word_addr : current_element_addr;

        // begin: Request Control Logic
        if(vpu_req_i.mopcode == load_fp) begin 
            if (buff_ready && (active_req_idx == vl_i)) 
                lsu_result_valid_o = 1'b1; 
        end else if (vpu_req_i.mopcode == store_fp) begin
            if (buff_ready && (active_req_idx == vl_i) && lsu_resp_valid_q) 
                lsu_result_valid_o = 1'b1; 
        end 
 
        // Data type decode
        unique case (vpu_req_i.width) 
            W_8:     lsu_type = 2'b10;  // Byte       
            W_16:    lsu_type = 2'b01;  // Half-word
            W_32:    lsu_type = 2'b00;  // Word
            default: ;  
        endcase


        if (vpu_req_i.mopcode == load_fp) begin
            lsu_we = 1'b0;
            if (!lsu_busy && (active_req_idx < vl_i) && !buff_ready) begin  
                lsu_req = 1'b1; 
            end
        end  if (vpu_req_i.mopcode == store_fp) begin            
            if (vrf_rdata_done_q && !lsu_busy && (active_req_idx < vl_i) && !buff_ready && state_was_busy_i) begin 
                lsu_we =  1'b1; 
                lsu_req = 1'b1; 
            end
        end
        // end: Request Control Logic
    end

    always_comb begin
        req_idx_next = req_idx;

        if (!state_was_busy_i) begin
            req_idx_next = '0;
        end

        if ((vpu_req_i.mopcode == load_fp || vpu_req_i.mopcode == store_fp) && (lsu_req && masters_resp_i.gnt)) begin
            req_idx_next = req_idx_next + 1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            req_idx <= '0;
            vrf_rdata_done_q <= '0;
            lsu_resp_valid_q <= '0;
        end else begin
            req_idx <= req_idx_next;
            if (vpu_req_i.mopcode == store_fp)
                vrf_rdata_done_q <= vrf_rdata_done_i;
                lsu_resp_valid_q <= lsu_resp_valid; 
        end
    end
    
    assign lsu_vrf_we_o = buff_ready && !buff_ready_q;
    
    //////////////////
    // Buffer Logic //
    //////////////////   

    always_comb begin
        lsu_wdata = '0;
        vrf_wdata_o  = '0;

        if (vpu_req_i.mopcode == load_fp) begin 
                if (lsu_vrf_we_o) begin
                    vrf_wdata_o = int_buff;
                end
        end else if (vpu_req_i.mopcode == store_fp) begin
            if (vrf_rdata_done_q && !lsu_busy && (active_req_idx < vl_i) && !buff_ready && state_was_busy_i) begin
                unique case(vpu_req_i.width)
                    W_8:   lsu_wdata = {24'b0, int_buff[(active_req_idx* 8) +: 8]};   
                    W_16:  lsu_wdata = {16'b0, int_buff[(active_req_idx* 16) +: 16]}; 
                    default: lsu_wdata =         int_buff[(active_req_idx* 32) +: 32];  
                endcase
            end 
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin       
            buff_counter <= '0;     
            buff_ready   <= '0;
            buff_ready_q <= '0;
            int_buff     <= '0;
        end else begin
            buff_ready   <= '0;
            buff_ready_q <= buff_ready;
            //begin: data transfer on buffer
            if (vpu_req_i.mopcode == load_fp) begin 

                if (!state_was_busy_i) begin
                    buff_counter <= '0;
                    int_buff <= '0;
                end else begin
                    if (lsu_rdata_valid_o) begin
                        
                        unique case(vpu_req_i.width) 
                            vpu_pkg::W_8: int_buff[(buff_counter * 8) +: 8] <= lsu_rdata[7:0];                    
                            vpu_pkg::W_16: int_buff[(buff_counter * 16) +: 16] <= lsu_rdata[15:0];       
                            default: int_buff[(buff_counter * 32) +: 32] <= lsu_rdata;
                        endcase
                        buff_counter <= buff_counter + 1;   

                        // Buffer completion
                        if (active_req_idx == (vl_i)) begin   
                            buff_ready <= 1'b1; 
                        end 
                    end 
               end       
            end else if (vpu_req_i.mopcode == store_fp) begin 
                // First element store
                if (vrf_rdata_done_i && (active_req_idx == '0) && !lsu_busy && (active_req_idx < vl_i) && !buff_ready) begin
                    int_buff <= vrf_rdata_i;
                end 
 
                if (!state_was_busy_i) begin
                    buff_counter <= '0;
                    int_buff <= '0;
                end else begin
                    if (lsu_resp_valid) begin
                        if (buff_counter == (vl_i - 1)) begin   
                            buff_ready <= 1'b1; 
                            int_buff <= '0; 
                        end else begin
                            buff_counter <= active_req_idx; 
                        end
                    end 
                end
            end //end: data transfer on buffer
        end
    end


endmodule