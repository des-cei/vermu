// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

module vpu_pipeline_checker
import vpu_pkg::*;
import vector_ops_pkg::*;
#(
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
    localparam type         registers_t      = logic [NrRgprPorts-1:0][XLEN-1:0],
    parameter  int unsigned EXT_XBAR_NMASTER = 1
) (
    input logic          clk_i,
    input logic          rst_ni,

    // X-IF Interface
    //input logic          x_issue_valid_i,
    //input  logic          x_issue_ready_i,
    input x_issue_req_t  x_issue_req_i,
    //input  x_issue_resp_t x_issue_resp_i,
    //output x_register_t   x_register_o,
    //output logic          x_register_valid_o,
    //input  logic          x_register_ready_i,
    //output logic          x_commit_valid_o,
    //output x_commit_t     x_commit_o,
    //input  logic          x_result_valid_i,
    //output logic          x_result_ready_o,
    //input  x_result_t     x_result_i,

    // Debug hooks directly into the VPU
    input op_e            vpu_dbg_operation_i,
    input logic           vpu_dbg_is_narrowing_i,
    input logic [VLEN-1:0]   vpu_dbg_rdata1_i,
    input logic [VLEN-1:0]   vpu_dbg_rdata2_i,
    input logic [VLEN-1:0]   vpu_dbg_vd_old_i,
    input logic           vpu_dbg_simd_result_valid_i,
    input logic [VLEN-1:0]   vpu_dbg_result_i
);

    typedef struct {
            logic [31:0]  instr;
            op_e          op;
            logic [VLEN-1:0] v_op1;
            logic [VLEN-1:0] v_op2;
            logic [VLEN-1:0] v_vd_old;
    } instr_ctx_t;

    logic is_narrowing;
    assign is_narrowing = vpu_dbg_is_narrowing_i;

    always_ff @(negedge clk_i) begin
        if (vpu_dbg_simd_result_valid_i) begin
        // Grab the signals exactly as they appear on the wires right now
        check_math(x_issue_req_i.instr, vpu_dbg_operation_i, vpu_dbg_rdata1_i,
                    vpu_dbg_rdata2_i, vpu_dbg_vd_old_i, vpu_dbg_result_i);
        end
    end

    task automatic check_math(logic [31:0] current_instr, op_e current_op, logic [VLEN-1:0] op1,
                                logic [VLEN-1:0] op2, logic [VLEN-1:0] vd, logic [VLEN-1:0] actual_result);
        localparam int SEW = 16;
        localparam int VL = VLEN/SEW;
        logic [VL*SEW-1:0] expected_vec;

        major_opcode_e mopcode;
        mopcode = major_opcode_e'(current_instr[6:0]);

        if (mopcode == 7'h57) begin
            expected_vec = '0;
            case (current_op)
                VADD: begin
                    for (int i = 0; i < VL; i++) begin
                            expected_vec[i*SEW+:SEW] = op1[i*SEW+:SEW] + op2[i*SEW+:SEW];
                    end

                    assert_vadd :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vadd_math PASSED | Result: %h", $time, actual_result);
                    else $error("VADD Failed: Expected %h, Got %h", expected_vec, actual_result);

                    cover_vadd : cover (actual_result == expected_vec);
                end

                VSUB: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] - op1[i*SEW+:SEW];
                    end
                    assert_vsub :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vsub PASSED | Result: %h", $time, actual_result);
                    else $error("VSUB Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vsub : cover (actual_result == expected_vec);
                end

                VRSUB: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op1[i*SEW+:SEW] - op2[i*SEW+:SEW];
                    end
                    assert_vrsub :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vrsub PASSED | Result: %h", $time, actual_result);
                    else $error("VRSUB Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vrsub : cover (actual_result == expected_vec);
                end

                    VAND: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] & op1[i*SEW+:SEW];
                    end
                    assert_vand :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vand PASSED | Result: %h", $time, actual_result);
                    else $error("VAND Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vand : cover (actual_result == expected_vec);
                end

                VOR: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] | op1[i*SEW+:SEW];
                    end
                    assert_vor :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vor PASSED | Result: %h", $time, actual_result);
                    else $error("VOR Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vor : cover (actual_result == expected_vec);
                end

                VXOR: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] ^ op1[i*SEW+:SEW];
                    end
                    assert_vxor :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vxor PASSED | Result: %h", $time, actual_result);
                    else $error("VXOR Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vxor : cover (actual_result == expected_vec);
                end

                VSLL: begin
                    for (int i = 0; i < VL; i++) begin
                        // Shift amount is only the lower log2(SEW) bits of op1
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] << (op1[i*SEW+:SEW] & 4'hF);
                    end
                    assert_vsll :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vsll PASSED | Result: %h", $time, actual_result);
                    else $error("VSLL Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vsll : cover (actual_result == expected_vec);
                end

                VSRL: begin
                    if (is_narrowing) begin
                        for (int i = 0; i < VL / 2; i++) begin
                        expected_vec[i*SEW+:SEW] = {'0, op2[i*2*SEW+:2*SEW] >> (op1[i*2*SEW+:2*SEW] & 4'hF)};
                        end
                    end else begin
                        for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = op2[i*SEW+:SEW] >> (op1[i*SEW+:SEW] & 4'hF);
                        end
                    end
                    assert_vsrl :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vsrl PASSED | Result: %h", $time, actual_result);
                    else $error("VSRL Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vsrl : cover (actual_result == expected_vec);
                end

                VSRA: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = $signed(op2[i*SEW+:SEW]) >>> (op1[i*SEW+:SEW] & 4'hF);
                    end
                    assert_vsra :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vsra PASSED | Result: %h", $time, actual_result);
                    else $error("VSRA Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vsra : cover (actual_result == expected_vec);
                end

                VMIN: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = ($signed(op2[i*SEW+:SEW]) <= $signed(op1[i*SEW+:SEW])) ?
                            op2[i*SEW+:SEW] : op1[i*SEW+:SEW];
                    end
                    assert_vmin :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmin PASSED | Result: %h", $time, actual_result);
                    else $error("VMIN Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmin : cover (actual_result == expected_vec);
                end

                VMINU: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = (op2[i*SEW+:SEW] <= op1[i*SEW+:SEW]) ? 
                                                op2[i*SEW+:SEW] : op1[i*SEW+:SEW];
                    end
                    assert_vminu :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vminu PASSED | Result: %h", $time, actual_result);
                    else $error("VMINU Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vminu : cover (actual_result == expected_vec);
                end

                VMAX: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = ($signed(op2[i*SEW+:SEW]) > $signed(op1[i*SEW+:SEW])) ?
                            op2[i*SEW+:SEW] : op1[i*SEW+:SEW];
                    end
                    assert_vmax :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmax PASSED | Result: %h", $time, actual_result);
                    else $error("VMAX Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmax : cover (actual_result == expected_vec);
                end

                VMAXU: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = (op2[i*SEW+:SEW] > op1[i*SEW+:SEW]) ? 
                                                op2[i*SEW+:SEW] : op1[i*SEW+:SEW];
                    end
                    assert_vmaxu :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmaxu PASSED | Result: %h", $time, actual_result);
                    else $error("VMAXU Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmaxu : cover (actual_result == expected_vec);
                end

                VMSEQ: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i] = (op2[i*SEW+:SEW] == op1[i*SEW+:SEW]) ? 1'h1 : 1'h0;
                    end
                    assert_vmseq :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmseq PASSED | Result: %h", $time, actual_result);
                    else $error("VMSEQ Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmseq : cover (actual_result == expected_vec);
                end

                VMSNE: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i] = (op2[i*SEW+:SEW] != op1[i*SEW+:SEW]) ? 1'h1 : 1'h0;
                    end
                    assert_vmsne :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmsne PASSED | Result: %h", $time, actual_result);
                    else $error("VMSNE Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmsne : cover (actual_result == expected_vec);
                end

                VMSLTU: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i] = (op2[i*SEW+:SEW] < op1[i*SEW+:SEW]) ? 1'h1 : 1'h0;
                    end
                    assert_vmsltu :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmsltu PASSED | Result: %h", $time, actual_result);
                    else $error("VMSLTU Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmsltu : cover (actual_result == expected_vec);
                end

                VMSLT: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i] = ($signed(op2[i*SEW+:SEW]) < $signed(op1[i*SEW+:SEW])) ? 1'h1 : 1'h0;
                    end
                    assert_vmslt :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmslt PASSED | Result: %h", $time, actual_result);
                    else $error("VMSLT Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmslt : cover (actual_result == expected_vec);
                end

                VMUL: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = (op1[i*SEW+:SEW] * op2[i*SEW+:SEW]);
                    end
                    assert_vmul :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmul PASSED | Result: %h", $time, actual_result);
                    else $error("VMUL Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmul : cover (actual_result == expected_vec);
                end

                VMULH: begin
                    for (int i = 0; i < VL; i++) begin
                        // Cast to 32-bit before multiplying to preserve the upper bits
                        automatic
                        logic signed [31:0]
                        temp_mul = $signed(
                            op1[i*SEW+:SEW]
                        ) * $signed(
                            op2[i*SEW+:SEW]
                        );
                        expected_vec[i*SEW+:SEW] = temp_mul[31:16];
                    end
                    assert_vmulh :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmulh PASSED | Result: %h", $time, actual_result);
                    else $error("VMULH Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmulh : cover (actual_result == expected_vec);
                end

                VMULHU: begin
                    for (int i = 0; i < VL; i++) begin
                        automatic logic [31:0] temp_mul = op1[i*SEW+:SEW] * op2[i*SEW+:SEW];
                        expected_vec[i*SEW+:SEW] = temp_mul[31:16];
                    end
                    assert_vmulhu :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmulhu PASSED | Result: %h", $time, actual_result);
                    else $error("VMULHU Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmulhu : cover (actual_result == expected_vec);
                end

                VMULHSU: begin
                    for (int i = 0; i < VL; i++) begin
                        // Mixed signed/unsigned requires careful casting in SV
                        automatic
                        logic signed [31:0]
                        temp_op1 = $signed(
                            {1'b0, op1[i*SEW+:SEW]}
                        );  // Zero-extend unsigned
                        automatic
                        logic signed [31:0]
                        temp_op2 = $signed(
                            op2[i*SEW+:SEW]
                        );  // Sign-extend signed
                        automatic logic signed [31:0] temp_mul = temp_op1 * temp_op2;
                        expected_vec[i*SEW+:SEW] = temp_mul[31:16];
                    end
                    assert_vmulhsu :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmulhsu PASSED | Result: %h", $time, actual_result);
                    else $error("VMULHSU Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmulhsu : cover (actual_result == expected_vec);
                end

                VMACC: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = (op1[i*SEW+:SEW] * op2[i*SEW+:SEW]) + vd[i*SEW+:SEW];
                    end
                    assert_vmacc :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmacc PASSED | Result: %h", $time, actual_result);
                    else $error("VMACC Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmacc : cover (actual_result == expected_vec);
                end

                VNMSAC: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = -(op1[i*SEW+:SEW] * op2[i*SEW+:SEW]) + vd[i*SEW+:SEW];
                    end
                    assert_vnmsac :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vnmsac PASSED | Result: %h", $time, actual_result);
                    else $error("VNMSAC Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vnmsac : cover (actual_result == expected_vec);
                end

                VMADD: begin
                    for (int i = 0; i < VL; i++) begin
                        expected_vec[i*SEW+:SEW] = (op1[i*SEW+:SEW] * vd[i*SEW+:SEW]) + op2[i*SEW+:SEW];
                    end
                    assert_vmadd :
                    assert final (actual_result == expected_vec)
                        $display("[Time %0t] chk_vmadd PASSED | Result: %h", $time, actual_result);
                    else $error("VMACC Failed: Expected %h, Got %h", expected_vec, actual_result);
                    cover_vmadd : cover (actual_result == expected_vec);
                end

                default: ;
            endcase
        end
    endtask

endmodule

