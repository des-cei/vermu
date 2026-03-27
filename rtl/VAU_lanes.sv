// Copyright 2024 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)


module VAU_lanes 
 import vpu_pkg::*; 
 import vector_ops_pkg::*;
 #(
   	parameter type data_t = logic [31:0]
)(
    input logic   clk_i, 
    input logic   rst_ni,
    input op_e    operation_i,
    input logic   operation_valid_i, 
    input data_t  op_s1_i,
    input data_t  op_s2_i,
    input data_t  op_d_i,
    input logic   is_signed_i,
    input logic   carry_i,
	input vsew_e  sew_i,
    output data_t result_o,
    output logic  result_valid_o
);
 
    logic [7:0]  op_s1_8b1, op_s1_8b2, op_s2_8b1, op_s2_8b2, result_8b1, result_8b2, op_d8b1, op_d8b2; 
    logic [15:0] op_s1_16b, op_s2_16b, result_16b, op_d16;  
    logic [31:0] op_s1_32b, op_s2_32b, result_32b, op_d32;    
    logic [3:0]  result_valid;

    logic [31:0] op_s1, op_s2;
    logic is_signed, carry;
    operation_valid_t activate_lane;
    logic  is_signed_and_not_vmulhsu;

    assign op_s1     = op_s1_i;
    assign op_s2     = op_s2_i;
    assign is_signed = is_signed_i;
    assign carry     = carry_i;
        
   
    ///////////
    // Lanes //
    ///////////
   
    VAU #(
        .Width(8)
    ) i_lane_8b1 (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .operation_i      (operation_i),
        .operation_valid_i(activate_lane.sew8), 
        .op_s1_i          (op_s1_8b1),
        .op_s2_i          (op_s2_8b1),
        .op_d_i           (op_d8b1),
        .is_signed_i      (is_signed_i),
  	    .carry_i          (carry_i),
	    .sew_i            (sew_i),
        .result_o         (result_8b1),
        .result_valid_o   (result_valid[0])
    );
  
    VAU #(
        .Width(8)
    ) i_lane_8b2 (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .operation_i      (operation_i),
        .operation_valid_i(activate_lane.sew8), 
        .op_s1_i          (op_s1_8b2),
        .op_s2_i          (op_s2_8b2),
        .op_d_i           (op_d8b2),
        .is_signed_i      (is_signed_i),
  	    .carry_i          (carry_i),
	    .sew_i            (sew_i),
        .result_o         (result_8b2),
        .result_valid_o   (result_valid[1])
    );

    VAU #(
        .Width(16)
    ) i_lane_16b (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .operation_i      (operation_i),
        .operation_valid_i(activate_lane.sew16),   
        .op_s1_i          (op_s1_16b),
        .op_s2_i          (op_s2_16b),
        .op_d_i           (op_d16),
        .is_signed_i      (is_signed_i),
  	    .carry_i          (carry_i),
	    .sew_i            (sew_i),
        .result_o         (result_16b),
        .result_valid_o   (result_valid[2])
    );

    VAU #(
        .Width(32)
    ) i_lane_32b (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .operation_i      (operation_i),
        .operation_valid_i(activate_lane.sew32), 
        .op_s1_i          (op_s1_32b),
        .op_s2_i          (op_s2_32b),
        .op_d_i           (op_d32),
        .is_signed_i      (is_signed_i),
  	    .carry_i          (carry_i),
	    .sew_i            (sew_i),
        .result_o         (result_32b),
        .result_valid_o   (result_valid[3])
    );      

  
    /////////////////
    // Distributor //
    /////////////////
    
    always_comb begin: distributor
        op_s1_8b1  = '0;
        op_s1_8b2  = '0;
        op_s1_16b  = '0;
        op_s1_32b  = '0;
        op_s2_8b1  = '0;
        op_s2_8b2  = '0;
        op_s2_16b  = '0;
        op_s2_32b  = '0;
        op_d8b1    = '0;
        op_d8b2    = '0;
        op_d16     = '0;
        op_d32     = '0;

        activate_lane = '0;

        is_signed_and_not_vmulhsu = is_signed && (operation_i != VMULHSU) ;

        unique case(sew_i)
            SEW_8: begin
                op_s1_8b1 = op_s1[7:0];
                op_s1_8b2 = op_s1[15:8];
                op_s1_16b = (is_signed_and_not_vmulhsu) ? 16'($signed(op_s1[23:16])) : 16'(op_s1[23:16]);
                op_s1_32b = (is_signed_and_not_vmulhsu) ? 32'($signed(op_s1[31:24])) : 32'(op_s1[31:24]); 
                
                op_s2_8b1 = op_s2[7:0];
                op_s2_8b2 = op_s2[15:8];
                op_s2_16b = (is_signed_i) ? 16'($signed(op_s2[23:16])) : 16'(op_s2[23:16]); 
                op_s2_32b = (is_signed_i) ? 32'($signed(op_s2[31:24])) : 32'(op_s2[31:24]);
                activate_lane.sew8 = operation_valid_i;
                activate_lane.sew16 = operation_valid_i;
                activate_lane.sew32 = operation_valid_i;
                unique case(operation_i)
                    VMACC,
                    VNMSAC: begin       
                        op_d8b1 = op_d_i[7:0];
                        op_d8b2 = op_d_i[15:8];
                        op_d16  = 16'(op_d_i[23:16]);
                        op_d32  = 32'(op_d_i[31:24]);
                    end
                    default:;
                endcase
            end
            SEW_16: begin
                op_s1_16b = op_s1[15:0];
                op_s1_32b = (is_signed_and_not_vmulhsu) ? 32'($signed(op_s1[31:16])) : 32'(op_s1[31:16]);               
                op_s2_16b = op_s2[15:0];                                                                  
                op_s2_32b = (is_signed_i) ? 32'($signed(op_s2[31:16])) : 32'(op_s2[31:16]);                     
      
                activate_lane.sew16 = operation_valid_i;
                activate_lane.sew32 = operation_valid_i;
                unique case(operation_i)
                    VMACC,
                    VNMSAC: begin        
                        op_d16  = op_d_i[15:0];
                        op_d32  = 32'(op_d_i[31:16]);
                    end
                    default:;
                endcase
            end
            default: begin
                op_s1_32b = op_s1;
                op_s2_32b = op_s2;
                activate_lane.sew32 = operation_valid_i;
                unique case(operation_i)
                    VMACC,
                    VNMSAC: begin        
                        op_d32  = op_d_i;
                    end
                    default:;
                endcase
            end
        endcase
    end

    ///////////////
    // Collector //
    ///////////////

    always_comb begin: collector
        unique case(sew_i)
            SEW_8:  begin
                unique case (operation_i)
                    VMSEQ,
                    VMSNE,
                    VMSLTU,
                    VMSLT : result_o = {result_32b[0], result_16b[0], result_8b2[0], result_8b1[0]};
                    default : result_o = {result_32b[7:0], result_16b[7:0], result_8b2, result_8b1}; 
                endcase  
                result_valid_o = &result_valid;
            end
            SEW_16: begin
                unique case (operation_i)
                    VMSEQ,
                    VMSNE,
                    VMSLTU,
                    VMSLT : result_o = {result_32b[0], result_16b[0]};
                    default : result_o = {result_32b[15:0], result_16b}; 
                endcase  
                result_valid_o = result_valid[2] && result_valid[3]; 
            end        
            default: begin
                result_o = result_32b;
                result_valid_o = result_valid[3];
            end
        endcase
    end

endmodule
