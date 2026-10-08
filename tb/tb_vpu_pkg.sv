// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

// vpu_tb_pkg :
//   * RVV instruction encoders (vsetvli/vsetivli, unit-stride/strided/indexed ld/st)
//   * LMUL / EMUL / VLMAX arithmetic and legality rules
//
// Conventions (chosen so that tests read like the RVV spec):
//   sew, eew  : element width in BITS            (8, 16, 32, 64)
//   lmul_log2 : log2(LMUL)                       (-3..3  ==>  1/8 .. 8)
//   *_x8      : a LMUL/EMUL value multiplied by 8 (1/8 -> 1, 1 -> 8, 8 -> 64),
//               so fractional values stay integers.
// -----------------------------------------------------------------------------

package tb_vpu_pkg;
    import vpu_pkg::*;

    localparam logic [1:0] MOP_UNIT      = 2'b00;
    localparam logic [1:0] MOP_IDX_UNORD = 2'b01;
    localparam logic [1:0] MOP_STRIDED   = 2'b10;
    localparam logic [1:0] MOP_IDX_ORD   = 2'b11;

    // OP-V funct6, integer (OPI*) group
    localparam logic [5:0] F6_VADD   = 6'b000000;
    localparam logic [5:0] F6_VSUB   = 6'b000010;
    localparam logic [5:0] F6_VRSUB  = 6'b000011;
    localparam logic [5:0] F6_VMINU  = 6'b000100;
    localparam logic [5:0] F6_VMIN   = 6'b000101;
    localparam logic [5:0] F6_VMAXU  = 6'b000110;
    localparam logic [5:0] F6_VMAX   = 6'b000111;
    localparam logic [5:0] F6_VAND   = 6'b001001;
    localparam logic [5:0] F6_VOR    = 6'b001010;
    localparam logic [5:0] F6_VXOR   = 6'b001011;
    localparam logic [5:0] F6_VMERGE = 6'b010111;   // vmerge (vm=0) / vmv.v.* (vm=1, vs2=0)
    localparam logic [5:0] F6_VWXUNARY0 = 6'b010000;   // vmv.x.s (OPMVV, vs1=0)
    localparam logic [5:0] F6_VRXUNARY0 = 6'b010000;   // vmv.s.x (OPMVX, vs2=0)
    localparam logic [5:0] F6_VSLL   = 6'b100101;
    localparam logic [5:0] F6_VSRL   = 6'b101000;
    localparam logic [5:0] F6_VSRA   = 6'b101001;

    // One load/store test point
    typedef struct {
        int sew;        // SEW  programmed with vsetvli (bits)
        int lmul_log2;  // LMUL programmed with vsetvli
        int eew;        // EEW  encoded in the load/store (bits)
        int vd;         // destination / data register
        int avl;        // requested application vector length
    } vtb_lsu_case_t;

    // ---------------------------------------------------------------------------
    // Field encodings
    // ---------------------------------------------------------------------------
    function automatic logic [2:0] vtb_sew_enc(input int sew);
        case (sew)
        8:  return 3'b000;
        16: return 3'b001;
        32: return 3'b010;
        default: $fatal(1, "vtb_sew_enc: bad SEW %0d", sew);
        endcase
    endfunction

    function automatic logic [2:0] vtb_lmul_enc(input int lmul_log2);
        case (lmul_log2)
        0: return 3'b000;
        1: return 3'b001;
        2: return 3'b010;
        3: return 3'b011;
        -1: return 3'b111;
        -2: return 3'b110;
        -3: return 3'b101;
        default: $fatal(1, "vtb_lmul_enc: bad log2(LMUL) %0d", lmul_log2);
        endcase 
    endfunction

    // 'width' field of vector loads/stores (EEW)
    function automatic logic [2:0] vtb_width_enc(input int eew);
        case (eew)
        8:  return 3'b000;
        16: return 3'b101;
        32: return 3'b110;
        default: $fatal(1, "vtb_width_enc: bad EEW %0d", eew);
        endcase
    endfunction

    // ---------------------------------------------------------------------------
    // LMUL / EMUL / VLMAX arithmetic
    // ---------------------------------------------------------------------------
    function automatic int vtb_lmul_x8(input int lmul_log2);
        return (lmul_log2 >= 0) ? (8 << lmul_log2) : (8 >> (-lmul_log2));
    endfunction

    // vtype legal for this implementation?  (SEW <= LMUL*ELEN)
    function automatic bit vtb_vtype_legal(input int sew, input int lmul_log2, input int elen);
        return (sew <= elen) && (sew * 8 <= elen * vtb_lmul_x8(lmul_log2));
    endfunction

    // EMUL = (EEW/SEW)*LMUL. Legal only if it is an exact value in [1/8, 8]
    function automatic bit vtb_emul_legal(input int sew, input int lmul_log2, input int eew);
        int num;
        num = vtb_lmul_x8(lmul_log2) * eew;
        if (num % sew) return 1'b0;
        return (num / sew >= 1) && (num / sew <= 64);
    endfunction

    function automatic int vtb_emul_x8(input int sew, input int lmul_log2, input int eew);
        return (vtb_lmul_x8(lmul_log2) * eew) / sew;
    endfunction

    // Number of vector registers occupied by a group with this EMUL
    function automatic int vtb_emul_regs(input int emul_x8);
        return (emul_x8 < 8) ? 1 : (emul_x8 / 8);
    endfunction

    // Register group must be aligned to its size
    function automatic bit vtb_vreg_aligned(input int vreg, input int emul_x8);
        return (vreg % vtb_emul_regs(emul_x8)) == 0;
    endfunction

    function automatic int vtb_vlmax(input int vlen, input int sew, input int lmul_log2);
        return (vlen * vtb_lmul_x8(lmul_log2)) / (8 * sew);
    endfunction

    // ---------------------------------------------------------------------------
    // Expected-value helpers
    // ---------------------------------------------------------------------------
 
    // Keep the lower 'bits' bits
    function automatic logic [31:0] vtb_trunc(input logic [31:0] v, input int bits);
        return (bits >= 32) ? v : (v & ((32'd1 << bits) - 31'd1));
    endfunction
 
    // Element written by vmv.v.x / vadd.vx ...: XLEN=32 scalar, sign-extended
    // if SEW > XLEN, truncated to SEW bits if SEW < XLEN
    function automatic logic [31:0] vtb_elem_from_x(input logic [31:0] rs1, input int sew);
        return vtb_trunc({{32{rs1[31]}}, rs1}, sew);
    endfunction
 
    // Element written by vmv.v.i / vadd.vi ...: simm5 sign-extended to SEW bits
    function automatic logic [31:0] vtb_elem_from_simm5(input logic [4:0] simm5, input int sew);
        return vtb_trunc({{27{simm5[4]}}, simm5}, sew);
    endfunction
 
    // Value written to the scalar register by vmv.x.s: element 0 of vs2, sign-extended
    // to XLEN=32 when SEW < XLEN (truncated if SEW > XLEN)
    function automatic logic [31:0] vtb_x_from_elem(input logic [31:0] elem, input int sew);
        logic signed [31:0] e;
        if (sew >= 32) return elem[31:0];
        e = 32'(vtb_trunc(elem, sew)) << (32 - sew);   // sign bit of the element -> bit 31
        return e >>> (32 - sew);                       // arithmetic shift back: sign extension
    endfunction

    // ---------------------------------------------------------------------------
    // Instruction encoders
    // ---------------------------------------------------------------------------

    ///////////////////
    // CONFIGURATION //
    ///////////////////

    function automatic logic [10:0] vtb_vtype(input int sew, input int lmul_log2,
                                                input bit vta, input bit vma);
        logic [10:0] v;
        v        = '0;
        v[2:0]   = vtb_lmul_enc(lmul_log2);
        v[5:3]   = vtb_sew_enc(sew);
        v[6]     = vta;
        v[7]     = vma;
        return v;
    endfunction

    // vsetvli rd, rs1, vtype      (AVL taken from register rs1)
    function automatic logic [31:0] vtb_vsetvli(input logic [4:0] rd, input logic [4:0] rs1,
                                                input logic [10:0] vtype);
        return {1'b0, vtype, rs1, 3'b111, rd, OPCODE_OP_V};
    endfunction

    // vsetivli rd, uimm, vtype    (AVL is a 5-bit immediate)
    function automatic logic [31:0] vtb_vsetivli(input logic [4:0] rd, input logic [4:0] uimm,
                                                input logic [10:0] vtype);
        return {2'b11, vtype[9:0], uimm, 3'b111, rd, OPCODE_OP_V};
    endfunction

    ////////////////
    // LOAD/STORE //
    ////////////////

    // Generic vector load/store encoder
    //   [31:29] nf  [28] mew  [27:26] mop  [25] vm  [24:20] lumop/sumop/rs2/vs2
    //   [19:15] rs1 [14:12] width  [11:7] vd/vs3  [6:0] opcode
    function automatic logic [31:0] vtb_vmem(
        input logic [2:0] nf,
        input logic       mew,
        input logic [1:0] mop,
        input logic       vm,           // 1 = unmasked
        input logic [4:0] f_24_20,
        input logic [4:0] rs1,
        input int         eew,
        input logic [4:0] vd_vs3,
        input logic [6:0] opcode
    );
        return {nf, mew, mop, vm, f_24_20, rs1, vtb_width_enc(eew), vd_vs3, opcode};
    endfunction

    // Unit-stride
    function automatic logic [31:0] vtb_vle(input int eew, input logic [4:0] vd,
                                            input logic [4:0] rs1, input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, MOP_UNIT, vm, 5'b00000, rs1, eew, vd, OPCODE_LOAD);
    endfunction

    function automatic logic [31:0] vtb_vse(input int eew, input logic [4:0] vs3,
                                            input logic [4:0] rs1, input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, MOP_UNIT, vm, 5'b00000, rs1, eew, vs3, OPCODE_STORE);
    endfunction

    // Strided (stride in scalar register rs2)
    function automatic logic [31:0] vtb_vlse(input int eew, input logic [4:0] vd,
                                            input logic [4:0] rs1, input logic [4:0] rs2,
                                            input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, MOP_STRIDED, vm, rs2, rs1, eew, vd, OPCODE_LOAD);
    endfunction

    function automatic logic [31:0] vtb_vsse(input int eew, input logic [4:0] vs3,
                                            input logic [4:0] rs1, input logic [4:0] rs2,
                                            input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, MOP_STRIDED, vm, rs2, rs1, eew, vs3, OPCODE_STORE);
    endfunction

    // Indexed (eew = INDEX element width; index vector in vs2)
    function automatic logic [31:0] vtb_vlxei(input bit ordered, input int eew,
                                                input logic [4:0] vd, input logic [4:0] rs1,
                                                input logic [4:0] vs2, input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, ordered ? MOP_IDX_ORD : MOP_IDX_UNORD,
                        vm, vs2, rs1, eew, vd, OPCODE_LOAD);
    endfunction

    function automatic logic [31:0] vtb_vsxei(input bit ordered, input int eew,
                                                input logic [4:0] vs3, input logic [4:0] rs1,
                                                input logic [4:0] vs2, input logic vm = 1'b1);
        return vtb_vmem(3'd0, 1'b0, ordered ? MOP_IDX_ORD : MOP_IDX_UNORD,
                        vm, vs2, rs1, eew, vs3, OPCODE_STORE);
    endfunction

    ////////////////
    // ARITHMETIC //
    ////////////////
 
    // Generic OP-V encoder
    //   [31:26] funct6 [25] vm [24:20] vs2 [19:15] vs1/rs1/simm5 [14:12] funct3
    //   [11:7] vd/rd   [6:0] opcode
    function automatic logic [31:0] vtb_opv(
        input logic [5:0] funct6,
        input logic       vm,           // 1 = unmasked
        input logic [4:0] vs2,
        input logic [4:0] op1,          // vs1 / rs1 / simm5 depending on funct3
        input vec_funct3_e funct3,
        input logic [4:0] vd
    );
        return {funct6, vm, vs2, op1, funct3, vd, OPCODE_OP_V};
    endfunction
 
    // vmv.v.v vd, vs1  /  vmv.v.x vd, rs1  /  vmv.v.i vd, simm5
    // (vmerge encoding with vm=1 and vs2=v0 field = 0)
    function automatic logic [31:0] vtb_vmv_vv(input logic [4:0] vd, input logic [4:0] vs1);
        return vtb_opv(F6_VMERGE, 1'b1, 5'd0, vs1, FMT_OPIVV, vd);
    endfunction
 
    function automatic logic [31:0] vtb_vmv_vx(input logic [4:0] vd, input logic [4:0] rs1);
        return vtb_opv(F6_VMERGE, 1'b1, 5'd0, rs1, FMT_OPIVX, vd);
    endfunction
 
    function automatic logic [31:0] vtb_vmv_vi(input logic [4:0] vd, input logic [4:0] simm5);
        return vtb_opv(F6_VMERGE, 1'b1, 5'd0, simm5, FMT_OPIVI_CSRRC, vd);
    endfunction
 
    // Encoder driven by the instruction enum (rvv_instr_pkg::vec_instr_e), for the
    // OPI* integer subset. 'op1' is vs1, rs1 or simm5 according to the _VV/_VX/_VI suffix.
    // vmv.* ignore vs2/vm (forced to 0/1); vmerge.* ignore vm (forced to 0).
    function automatic logic [31:0] vtb_enc_opi(
        input rvv_instr_pkg::vec_instr_e instr,
        input logic [4:0] vd,
        input logic [4:0] vs2,
        input logic [4:0] op1,
        input logic       vm = 1'b1
    );
        import rvv_instr_pkg::*;
        logic [5:0] f6;
        vec_funct3_e f3;
        logic [4:0] s2;
        logic       m;
 
        s2 = vs2;
        m  = vm;
 
        case (instr)
            VADD_VV,   VADD_VX,   VADD_VI:                 f6 = F6_VADD;
            VSUB_VV,   VSUB_VX:                            f6 = F6_VSUB;
            VRSUB_VX,  VRSUB_VI:                           f6 = F6_VRSUB;
            VMINU_VV,  VMINU_VX:                           f6 = F6_VMINU;
            VMIN_VV,   VMIN_VX:                            f6 = F6_VMIN;
            VMAXU_VV,  VMAXU_VX:                           f6 = F6_VMAXU;
            VMAX_VV,   VMAX_VX:                            f6 = F6_VMAX;
            VAND_VV,   VAND_VX,   VAND_VI:                 f6 = F6_VAND;
            VOR_VV,    VOR_VX,    VOR_VI:                  f6 = F6_VOR;
            VXOR_VV,   VXOR_VX,   VXOR_VI:                 f6 = F6_VXOR;
            VSLL_VV,   VSLL_VX,   VSLL_VI:                 f6 = F6_VSLL;
            VSRL_VV,   VSRL_VX,   VSRL_VI:                 f6 = F6_VSRL;
            VSRA_VV,   VSRA_VX,   VSRA_VI:                 f6 = F6_VSRA;
            VMV_VV,    VMV_VX,    VMV_VI: begin f6 = F6_VMERGE; s2 = 5'd0; m = 1'b1; end
            VMERGE_VVM, VMERGE_VXM, VMERGE_VIM: begin f6 = F6_VMERGE; m = 1'b0; end
            default: $fatal(1, "vtb_enc_opi: instruction %s not supported", instr.name());
        endcase
 
        case (instr)
            VADD_VV, VSUB_VV, VMINU_VV, VMIN_VV, VMAXU_VV, VMAX_VV, VAND_VV, VOR_VV,
            VXOR_VV, VSLL_VV, VSRL_VV, VSRA_VV, VMV_VV, VMERGE_VVM:
                f3 = FMT_OPIVV;
            VADD_VX, VSUB_VX, VRSUB_VX, VMINU_VX, VMIN_VX, VMAXU_VX, VMAX_VX, VAND_VX,
            VOR_VX, VXOR_VX, VSLL_VX, VSRL_VX, VSRA_VX, VMV_VX, VMERGE_VXM:
                f3 = FMT_OPIVX;
            default: // the remaining supported ones are the _VI forms
                f3 = FMT_OPIVI_CSRRC;
        endcase
 
        return vtb_opv(f6, m, s2, op1, f3, vd);
    endfunction
 
    // vmv.x.s rd, vs2   (OPMVV, funct6=VWXUNARY0, vs1=0)  : x[rd] = sext(vs2[0])
    function automatic logic [31:0] vtb_vmv_xs(input logic [4:0] rd, input logic [4:0] vs2);
        return vtb_opv(F6_VWXUNARY0, 1'b1, vs2, 5'b00000, FMT_OPMVV_CSRRS, rd);
    endfunction
 
    // vmv.s.x vd, rs1   (OPMVX, funct6=VRXUNARY0, vs2=0)  : vd[0] = x[rs1]
    function automatic logic [31:0] vtb_vmv_sx(input logic [4:0] vd, input logic [4:0] rs1);
        return vtb_opv(F6_VRXUNARY0, 1'b1, 5'd0, rs1, FMT_OPMVX_CSRRSI, vd);
    endfunction
 
    // Enum-driven version: 'dst' is rd (VMV_XS) or vd (VMV_SX), 'src' is vs2 or rs1
    function automatic logic [31:0] vtb_enc_scalar_move(
        input rvv_instr_pkg::vec_instr_e instr,
        input logic [4:0] dst,
        input logic [4:0] src
    );
        case (instr)
            rvv_instr_pkg::VMV_XS: return vtb_vmv_xs(dst, src);
            rvv_instr_pkg::VMV_SX: return vtb_vmv_sx(dst, src);
            default: $fatal(1, "vtb_enc_scalar_move: instruction %s not supported", instr.name());
        endcase
    endfunction

endpackage