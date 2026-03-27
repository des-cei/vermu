onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_vpu_top/clk_i
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/curr_instr
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/file_handle
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/scan_result
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/curr_rs1
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/curr_rs2
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/state
add wave -noupdate -expand -group stim_gen /tb_vpu_top/i_stim_gen/next_state
add wave -noupdate -expand -group Debug /tb_vpu_top/i_checker/vpu_dbg_operation_i
add wave -noupdate -expand -group Debug /tb_vpu_top/i_vpu/debug_if/rdata1
add wave -noupdate -expand -group Debug /tb_vpu_top/i_vpu/debug_if/vrf_rdata2
add wave -noupdate -expand -group Debug /tb_vpu_top/i_vpu/debug_if/vrf_vd_data
add wave -noupdate -expand -group Debug /tb_vpu_top/i_vpu/debug_if/result
add wave -noupdate -expand -group Debug /tb_vpu_top/i_vpu/debug_if/simd_result_valid
add wave -noupdate -divider VPU
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/issue_req
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/issue_resp
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/issue_ready
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/register
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/registers
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/csr_result
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/we
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/instr_vrf_we
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/op_valid_simd
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/csr_valid
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/illegal_req
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/vpu_req
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/state_was_busy
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/csr_vtype
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/csr_vl
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/csr_vstart
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/vlmax
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/state
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/vrf_op_valid
add wave -noupdate -group vpu /tb_vpu_top/i_vpu/vrf_we_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_valid_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_req_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_ready_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_result_valid_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_resp_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/register_valid_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/register_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/registers_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/done_wi
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vmv_active_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vmv_offset_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/nreg_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/waiting_for_done_i
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_op_valid_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_we_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vpu_req_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/state_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_we_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/op_valid_simd_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/illegal_req_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vlmax_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_we_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_result_valid_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/result_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/state_was_busy_o
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/sel
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/hartid_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/id_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vpu_req_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vpu_req_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vsetvl_rs2
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/scalar_val
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/rs1_addr_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/rs1_addr_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vtype_supported
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_we_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_we_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_valid_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_valid_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_rs1
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/issue_rd
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/result_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/result_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vlmax_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vlmax_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/avl_int
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/new_vl_int
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_handle
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/csr_target
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/int_lmul4
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/op_valid_simd_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/op_valid_simd_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_op_valid_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_op_valid_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/vrf_we_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/illegal_req_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/illegal_req_q
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/state_d
add wave -noupdate -group instr_decoder /tb_vpu_top/i_vpu/instr_decoder_i/state_q
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/clk_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/rst_ni
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/operation_valid_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/op_s1_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/op_s2_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/op_d_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/vl_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/sew_i
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/result_o
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/result_valid_o
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/red_acc
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_op_s1
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_op_s2
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_d
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_result
add wave -noupdate -group simd_controller -expand /tb_vpu_top/i_vpu/simd_controller_i/lane_result_valid
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/sew_bits
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/bit_index
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_idx
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lane_offset
add wave -noupdate -group simd_controller /tb_vpu_top/i_vpu/simd_controller_i/lanes_result_valid
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/vpu_req_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/csr_vtype_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/csr_vl_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/op_valid_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/funct3_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/waddr_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/we_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/wdata_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/done_w_o
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/raddr1_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/raddr2_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/raddr3_i
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/rdata1_o
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/rdata2_o
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/rdata3_o
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/done_r2_o
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/mask_o
add wave -noupdate -group vregfile -group MASK /tb_vpu_top/i_vpu/vregfile_i/sew_bits
add wave -noupdate -group vregfile -group MASK /tb_vpu_top/i_vpu/vregfile_i/elem_idx
add wave -noupdate -group vregfile -group MASK /tb_vpu_top/i_vpu/vregfile_i/bytes_per_elem
add wave -noupdate -group vregfile -group MASK /tb_vpu_top/i_vpu/vregfile_i/active_vl
add wave -noupdate -group vregfile /tb_vpu_top/i_vpu/vregfile_i/vreg
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s1_i}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s2_i}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_d_i}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/is_signed_and_not_vmulhsu}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/carry_i}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/sew_i}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_o}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_valid_o}
add wave -noupdate -group lane_3 -expand {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_valid}
add wave -noupdate -group lane_3 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/activate_lane}
add wave -noupdate -group lane_3 -group lane_8b1 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s1_8b1}
add wave -noupdate -group lane_3 -group lane_8b1 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s2_8b1}
add wave -noupdate -group lane_3 -group lane_8b1 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_d8b1}
add wave -noupdate -group lane_3 -group lane_8b1 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_8b1}
add wave -noupdate -group lane_3 -group lane_8b2 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s1_8b2}
add wave -noupdate -group lane_3 -group lane_8b2 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s2_8b2}
add wave -noupdate -group lane_3 -group lane_8b2 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_d8b2}
add wave -noupdate -group lane_3 -group lane_8b2 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_8b2}
add wave -noupdate -group lane_3 -group lane_16 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s1_16b}
add wave -noupdate -group lane_3 -group lane_16 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s2_16b}
add wave -noupdate -group lane_3 -group lane_16 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_16b}
add wave -noupdate -group lane_3 -group lane_16 {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_d16}
add wave -noupdate -group lane_3 -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s1_32b}
add wave -noupdate -group lane_3 -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_s2_32b}
add wave -noupdate -group lane_3 -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/result_32b}
add wave -noupdate -group lane_3 -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/op_d32}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/clk_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/rst_ni}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/operation_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/operation_valid_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/op_s1_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/op_s2_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/op_d_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/is_signed_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/carry_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/sew_i}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/result_o}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/result_valid_o}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/is_mult}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/mult_result}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/mult_op1}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/mult_op2}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/adder_result}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/subtractor_result}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/simd_result}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/arith_op1}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/arith_op2}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/is_shift}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/shift_operand}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/shift_amount}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/comp_result}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/comp_op_1}
add wave -noupdate -group lane_32b {/tb_vpu_top/i_vpu/simd_controller_i/gen_lanes[3]/i_VAU_lane/i_lane_32b/comp_op_2}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {140 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 352
configure wave -valuecolwidth 224
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {8162 ns} {8302 ns}
