// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)


module vregfile 
    import vpu_pkg::*;  
    import rvv_instr_pkg::*;  
#(
    parameter type data_t    = logic[VLEN-1:0]
)(
    input logic           clk_i,
    input logic           rst_ni,
    input vpu_req_t       vpu_req_i,
    input vtype_t         csr_vtype_i,
    input vl_t            csr_vl_i,
    input vl_t            vstart_i,
    input logic           op_valid_i,
    input encode_funct3_e funct3_i,
    input addr_t          waddr_i,
    input logic           we_i,               
    input data_t          wdata_i,
    output logic          done_w_o, 
    input addr_t          raddr1_i,
    input addr_t          raddr2_i,
    input addr_t          raddr3_i,
    output data_t         rdata1_o, 
    output data_t         rdata2_o,
    output data_t         rdata3_o,
    output logic          done_r2_o,
    output vlen_t         mask_o

);


	logic [NRVREG-1:0][VLEN-1:0]vreg;  

    logic mask_bit;
    logic prestart;
    logic body    ;
    logic tail    ;
    logic active  ;
    logic inactive;

    int sew_bits;
    int elem_idx;
    int   bytes_per_elem;
    vlen_t active_vl;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            vreg           <= '0;
            done_w_o       <= '0;
            bytes_per_elem <= '0;
            prestart       <= '0;
            body           <= '0;
            tail           <= '0;
            active         <= '0;
            inactive       <= '0;
            mask_bit       <= '0;
        end else begin
            done_w_o <= 1'b0;
            if (we_i && waddr_i < NRVREG && op_valid_i) begin

                 if (vpu_req_i.opcode == VMV_SX) begin
                    unique case (csr_vtype_i.vsew)
                        SEW_8: vreg[waddr_i][7:0] <= wdata_i[7:0]; 
                        SEW_16: vreg[waddr_i][15:0] <= wdata_i[15:0]; 
                        default: vreg[waddr_i][31:0] <= wdata_i[31:0]; 
                    endcase
                end else begin 
                    if (vpu_req_i.mopcode == load_fp || vpu_req_i.mopcode == store_fp) begin
                        bytes_per_elem = get_eew_bits(vpu_req_i.width) >> 3;
                    end else begin 
                        bytes_per_elem = get_sew_bits(csr_vtype_i.vsew) >> 3;
                    end 

                    for (int b = 0; b < VLENB; b++) begin : WRITE_LOOP

                        elem_idx = b / bytes_per_elem;

                        // Subsets
                        prestart = (elem_idx < vstart_i);
                        body     = (elem_idx >= vstart_i) && (elem_idx < csr_vl_i);
                        tail     = (elem_idx >= csr_vl_i);

                        // Mask
                        mask_bit = (vpu_req_i.vm) ? 1'b1 : vreg[0][elem_idx];

                        active   = body && mask_bit;
                        inactive = body && !mask_bit;

                        // Data writing
                        if (active) begin
                            if (vpu_req_i.opcode == VID_V) begin
                                int byte_sel;
                                byte_sel = b % bytes_per_elem;
                                vreg[waddr_i][8*b +: 8] <= elem_idx[(byte_sel*8) +: 8];
                            end else begin
                                vreg[waddr_i][8*b +: 8] <= wdata_i[8*b +: 8];
                            end
                        end else if (inactive) begin
                            // BODY + MASK=0
                            if (csr_vtype_i.vma) begin
                                // mask agnostic
                                vreg[waddr_i][8*b +: 8] <= 8'hFF;
                            end
                        end else if (tail) begin
                            if (csr_vtype_i.vta) begin
                                // tail agnostic
                                vreg[waddr_i][8*b +: 8] <= 8'hFF;
                            end
                        end
                        // prestart
                    end
                end

                if (done_w_o)
                    done_w_o <= 1'b0;
                else 
                    done_w_o <= 1'b1;
            end
        end
    end

    always_comb begin 
        rdata1_o = '0;
        rdata2_o = '0;
        rdata3_o = '0;
        active_vl = '0;
        mask_o    = '0; 
        sew_bits = get_sew_bits(csr_vtype_i.vsew);

        if (op_valid_i) begin
            // Number of bits to read based on vl and sew_bits
            automatic int num_bits = csr_vl_i * sew_bits;
            
            if (vpu_req_i.opcode == VMV_XS ) begin
                 active_vl = (logic'(1) << sew_bits) - 1;
            end else begin             
                if (num_bits >= VLEN) 
                    active_vl = '1;
                else 
                    active_vl = (logic'(1) << num_bits) - 1;
            end

            //Read rdata3_o
            if (raddr3_i < NRVREG) begin
                rdata3_o = vreg[raddr3_i] & active_vl;
            end 

            // Read rdata2_o
            if (raddr2_i < NRVREG) begin
                rdata2_o = vreg[raddr2_i] & active_vl;     
            end

            // Read rdata1_o
            unique case (funct3_i)
                vpu_pkg::OPIVV,
                vpu_pkg::OPMVV_CSRRS: begin
                    if (raddr1_i < NRVREG) begin
                        rdata1_o = vreg[raddr1_i] & active_vl;    
                    end
                end
                default: rdata1_o = '0;
            endcase

            mask_o = vreg[0];
        end
    end

    assign done_r2_o = op_valid_i;
endmodule


