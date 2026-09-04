// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)

`timescale 1ns/1ps

module tb_xif_decoder;
import vpu_pkg::*;
import rvv_instr_pkg::*;
import cvxif_types_pkg::readregflags_t;

    logic [31:0]   instr;
    logic          issue_valid, accept, writeback;
    readregflags_t register_read;
    vec_instr_e    vec_instr;

    // DUT
    vpu_xif_decoder #(
        .readregflags_t  (readregflags_t)
    ) dut (
        .issue_valid_i  (issue_valid),
        .instr_i        (instr),
        .accept_o       (accept),
        .writeback_o    (writeback),  
        .register_read_o(register_read),  
        .vec_instr_o    (vec_instr)
    );

    // Stimulus file variables
    integer  file_handle;
    integer  scan_result;
    string   stimulus_file;
    
    // Per-line data from the stimulus file
    logic [31:0] curr_instr;
    logic [31:0] curr_rs1;     // not driven (no data-path in DUT) but read
    logic [31:0] curr_rs2;     // idem
    string       curr_mnemonic;

    // Counters / scoreboard
    int unsigned total_instr;
    int unsigned accepted_instr;
    int unsigned illegal_instr;
    int unsigned mismatch_instr;

    int verbose;

    function automatic string decode_fields(input logic [31:0] ins);
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [5:0] funct6;
        logic [4:0] rd, rs1_f, rs2_f;
        opcode = ins[6:0];
        funct3 = ins[14:12];
        funct6 = ins[31:26];
        rd     = ins[11:7];
        rs1_f  = ins[19:15];
        rs2_f  = ins[24:20];
        return $sformatf(
            "op=0x%02h f3=%03b f6=%06b rd=v%0d rs1=v%0d rs2=v%0d vm=%0b",
            opcode, funct3, funct6, rd, rs1_f, rs2_f, ins[25]
        );
    endfunction

  //  NOTE: only the instructions that are *accepted* by the current decoder
  //        are mapped. Anything not listed here is left as INSTR_ILLEGAL so
  //        mismatches are only flagged when the decoder claims acceptance but
  //        cannot be verified, or vice-versa.

    function automatic vec_instr_e mnemonic_to_enum(input string mn);
        case (mn)
            /////////////////
            // OPCODE_OP_V //
            /////////////////
            
            // FMT_OPIVV – integer vector-vector
            "vadd.vv"        : return VADD_VV;
            "vsub.vv"        : return VSUB_VV;
            "vminu.vv"       : return VMINU_VV;
            "vmin.vv"        : return VMIN_VV;
            "vmaxu.vv"       : return VMAXU_VV;
            "vmax.vv"        : return VMAX_VV;
            "vand.vv"        : return VAND_VV;
            "vor.vv"         : return VOR_VV;
            "vxor.vv"        : return VXOR_VV;
            "vrgather.vv"    : return VRGATHER_VV;
            "vrgatherei16.vv": return VRGATHEREI16_VV;
            "vadc.vvm"       : return VADC_VVM;
            "vmadc.vvm"      : return VMADC_VVM;
            "vmadc.vv"       : return VMADC_VV;
            "vsbc.vvm"       : return VSBC_VVM;
            "vmsbc.vvm"      : return VMSBC_VVM;
            "vmsbc.vv"       : return VMSBC_VV;
            "vmerge.vvm"     : return VMERGE_VVM;
            "vmseq.vv"       : return VMSEQ_VV;
            "vmsne.vv"       : return VMSNE_VV;
            "vmsltu.vv"      : return VMSLTU_VV;
            "vmslt.vv"       : return VMSLT_VV;
            "vmsleu.vv"      : return VMSLEU_VV;
            "vmsle.vv"       : return VMSLE_VV;
            "vsaddu.vv"      : return VSADDU_VV;
            "vsadd.vv"       : return VSADD_VV;
            "vssubu.vv"      : return VSSUBU_VV;
            "vssub.vv"       : return VSSUB_VV;
            "vsll.vv"        : return VSLL_VV;
            "vsmul.vv"       : return VSMUL_VV;
            "vsrl.vv"        : return VSRL_VV;
            "vsra.vv"        : return VSRA_VV;
            "vssrl.vv"       : return VSSRL_VV;
            "vssra.vv"       : return VSSRA_VV;
            "vnsrl.wv"       : return VNSRL_WV;
            "vnsra.wv"       : return VNSRA_WV;
            "vnclipu.wv"     : return VNCLIPU_WV;
            "vnclip.wv"      : return VNCLIP_WV;
            "vwredsumu.vs"   : return VWREDSUMU_VS;
            "vwredsum.vs"    : return VWREDSUM_VS;

            // FMT_OPIVX  – integer vector-scalar
            "vadd.vx"        : return VADD_VX;
            "vsub.vx"        : return VSUB_VX;
            "vrsub.vx"       : return VRSUB_VX;
            "vminu.vx"       : return VMINU_VX;
            "vmin.vx"        : return VMIN_VX;
            "vmaxu.vx"       : return VMAXU_VX;
            "vmax.vx"        : return VMAX_VX;
            "vand.vx"        : return VAND_VX;
            "vor.vx"         : return VOR_VX;
            "vxor.vx"        : return VXOR_VX;
            "vrgather.vx"    : return VRGATHER_VX;
            "vslideup.vx"    : return VSLIDEUP_VX;
            "vslidedown.vx"  : return VSLIDEDOWN_VX;
            "vadc.vxm"       : return VADC_VXM;
            "vmadc.vxm"      : return VMADC_VXM;
            "vmadc.vx"       : return VMADC_VX;
            "vsbc.vxm"       : return VSBC_VXM;
            "vmsbc.vxm"      : return VMSBC_VXM;
            "vmsbc.vx"       : return VMSBC_VX;
            "vmerge.vxm"     : return VMERGE_VXM;
            "vmseq.vx"       : return VMSEQ_VX;
            "vmsne.vx"       : return VMSNE_VX;
            "vmsltu.vx"      : return VMSLTU_VX;
            "vmslt.vx"       : return VMSLT_VX;
            "vmsleu.vx"      : return VMSLEU_VX;
            "vmsle.vx"       : return VMSLE_VX;
            "vmsgtu.vx"      : return VMSGTU_VX;
            "vmsgt.vx"       : return VMSGT_VX;
            "vsaddu.vx"      : return VSADDU_VX;
            "vsadd.vx"       : return VSADD_VX;
            "vssubu.vx"      : return VSSUBU_VX;
            "vssub.vx"       : return VSSUB_VX;
            "vsll.vx"        : return VSLL_VX;
            "vsmul.vx"       : return VSMUL_VX;
            "vsrl.vx"        : return VSRL_VX;
            "vsra.vx"        : return VSRA_VX;
            "vssrl.vx"       : return VSSRL_VX;
            "vssra.vx"       : return VSSRA_VX;
            "vnsrl.wx"       : return VNSRL_WX;
            "vnsra.wx"       : return VNSRA_WX;
            "vnclipu.wx"     : return VNCLIPU_WX;
            "vnclip.wx"      : return VNCLIP_WX;

            // FMT_OPIVI – integer vector-immediate
            "vadd.vi"        : return VADD_VI;
            "vrsub.vi"       : return VRSUB_VI;
            "vand.vi"        : return VAND_VI;
            "vor.vi"         : return VOR_VI;
            "vxor.vi"        : return VXOR_VI;
            "vrgather.vi"    : return VRGATHER_VI;
            "vslideup.vi"    : return VSLIDEUP_VI;
            "vslidedown.vi"  : return VSLIDEDOWN_VI;
            "vadc.vim"       : return VADC_VIM;
            "vmadc.vim"      : return VMADC_VIM;
            "vmadc.vi"       : return VMADC_VI;
            "vmerge.vim"     : return VMERGE_VIM;
            "vmseq.vi"       : return VMSEQ_VI;
            "vmsne.vi"       : return VMSNE_VI;
            "vmsleu.vi"      : return VMSLEU_VI;
            "vmsle.vi"       : return VMSLE_VI;
            "vmsgtu.vi"      : return VMSGTU_VI;
            "vmsgt.vi"       : return VMSGT_VI;
            "vsaddu.vi"      : return VSADDU_VI;
            "vsadd.vi"       : return VSADD_VI;
            "vsll.vi"        : return VSLL_VI;
            "vsrl.vi"        : return VSRL_VI;
            "vsra.vi"        : return VSRA_VI;
            "vssrl.vi"       : return VSSRL_VI;
            "vssra.vi"       : return VSSRA_VI;
            "vnsrl.wi"       : return VNSRL_WI;
            "vnsra.wi"       : return VNSRA_WI;
            "vnclipu.wi"     : return VNCLIPU_WI;
            "vnclip.wi"      : return VNCLIP_WI;
            "vmv1r.v",
            "vmv2r.v",
            "vmv4r.v",
            "vmv8r.v"        : return VMVNRR_V;

            // FMT_OPMVV – mask/multiply vector-vector
            "vredsum.vs"     : return VREDSUM_VS;
            "vredand.vs"     : return VREDAND_VS;
            "vredor.vs"      : return VREDOR_VS;
            "vredxor.vs"     : return VREDXOR_VS;
            "vredminu.vs"    : return VREDMINU_VS;
            "vredmin.vs"     : return VREDMIN_VS;
            "vredmaxu.vs"    : return VREDMAXU_VS;
            "vredmax.vs"     : return VREDMAX_VS;
            "vaaddu.vv"      : return VAADDU_VV;
            "vaadd.vv"       : return VAADD_VV;
            "vasubu.vv"      : return VASUBU_VV;
            "vasub.vv"       : return VASUB_VV;
            "vcompress.vm"   : return VCOMPRESS_VM;
            "vmandnot.mm",
            "vmandn.mm"      : return VMANDNOT_MM;
            "vmand.mm"       : return VMAND_MM;
            "vmor.mm"        : return VMOR_MM;
            "vmxor.mm"       : return VMXOR_MM;
            "vmornot.mm",
            "vmorn.mm"       : return VMORNOT_MM;
            "vmnand.mm"      : return VMNAND_MM;
            "vmnor.mm"       : return VMNOR_MM;
            "vmxnor.mm"      : return VMXNOR_MM;
            "vdivu.vv"       : return VDIVU_VV;
            "vdiv.vv"        : return VDIV_VV;
            "vremu.vv"       : return VREMU_VV;
            "vrem.vv"        : return VREM_VV;
            "vmulhu.vv"      : return VMULHU_VV;
            "vmul.vv"        : return VMUL_VV;
            "vmulhsu.vv"     : return VMULHSU_VV;
            "vmulh.vv"       : return VMULH_VV;
            "vmadd.vv"       : return VMADD_VV;
            "vnmsub.vv"      : return VNMSUB_VV;
            "vmacc.vv"       : return VMACC_VV;
            "vnmsac.vv"      : return VNMSAC_VV;
            "vwaddu.vv"      : return VWADDU_VV;
            "vwadd.vv"       : return VWADD_VV;
            "vwsubu.vv"      : return VWSUBU_VV;
            "vwsub.vv"       : return VWSUB_VV;
            "vwaddu.wv"      : return VWADDU_WV;
            "vwadd.wv"       : return VWADD_WV;
            "vwsubu.wv"      : return VWSUBU_WV;
            "vwsub.wv"       : return VWSUB_WV;
            "vwmulu.vv"      : return VWMULU_VV;
            "vwmulsu.vv"     : return VWMULSU_VV;
            "vwmul.vv"       : return VWMUL_VV;
            "vwmaccu.vv"     : return VWMACCU_VV;
            "vwmacc.vv"      : return VWMACC_VV;
            "vwmaccsu.vv"    : return VWMACCSU_VV;
            // VWXUNARY0: vs1 selects op
            "vmv.x.s"        : return VMV_XS;
            "vcpop.m"        : return VCPOP_M;
            "vfirst.m"       : return VFIRST_M;
            // VXUNARY0: vs1 selects op
            "vzext.vf8"      : return VZEXT_VF8;
            "vsext.vf8"      : return VSEXT_VF8;
            "vzext.vf4"      : return VZEXT_VF4;
            "vsext.vf4"      : return VSEXT_VF4;
            "vzext.vf2"      : return VZEXT_VF2;
            "vsext.vf2"      : return VSEXT_VF2;
            // VMUNARY0: vs1 selects op
            "vmsbf.m"        : return VMSBF_M;
            "vmsof.m"        : return VMSOF_M;
            "vmsif.m"        : return VMSIF_M;
            "viota.m"        : return VIOTA_M;
            "vid.v"          : return VID_V;

            // FMT_OPMVX – mask/multiply vector-scalar
            "vaaddu.vx"      : return VAADDU_VX;
            "vaadd.vx"       : return VAADD_VX;
            "vasubu.vx"      : return VASUBU_VX;
            "vasub.vx"       : return VASUB_VX;
            "vslide1up.vx"   : return VSLIDE1UP_VX;
            "vslide1down.vx" : return VSLIDE1DOWN_VX;
            "vdivu.vx"       : return VDIVU_VX;
            "vdiv.vx"        : return VDIV_VX;
            "vremu.vx"       : return VREMU_VX;
            "vrem.vx"        : return VREM_VX;
            "vmulhu.vx"      : return VMULHU_VX;
            "vmul.vx"        : return VMUL_VX;
            "vmulhsu.vx"     : return VMULHSU_VX;
            "vmulh.vx"       : return VMULH_VX;
            "vmadd.vx"       : return VMADD_VX;
            "vnmsub.vx"      : return VNMSUB_VX;
            "vmacc.vx"       : return VMACC_VX;
            "vnmsac.vx"      : return VNMSAC_VX;
            "vwaddu.vx"      : return VWADDU_VX;
            "vwadd.vx"       : return VWADD_VX;
            "vwsubu.vx"      : return VWSUBU_VX;
            "vwsub.vx"       : return VWSUB_VX;
            "vwaddu.wx"      : return VWADDU_WX;
            "vwadd.wx"       : return VWADD_WX;
            "vwsubu.wx"      : return VWSUBU_WX;
            "vwsub.wx"       : return VWSUB_WX;
            "vwmulu.vx"      : return VWMULU_VX;
            "vwmulsu.vx"     : return VWMULSU_VX;
            "vwmul.vx"       : return VWMUL_VX;
            "vwmaccu.vx"     : return VWMACCU_VX;
            "vwmacc.vx"      : return VWMACC_VX;
            "vwmaccus.vx"    : return VWMACCUS_VX;
            "vwmaccsu.vx"    : return VWMACCSU_VX;
            // VRXUNARY0: vs2 selects op
            "vmv.s.x"        : return VMV_SX;

            // FMT_OPCFG – vector configuration
            "vsetvli"        : return VSETVLI;
            "vsetivli"       : return VSETIVLI;
            "vsetvl"         : return VSETVL;

            /////////////////
            // OPCODE_LOAD //
            /////////////////

            // unit-stride
            "vle8.v"         : return VLE8_V;
            "vle16.v"        : return VLE16_V;
            "vle32.v"        : return VLE32_V;
            // mask load
            "vlm.v"          : return VLM_V;
            // whole-register loads 
            "vl1re8.v",
            "vl1r.v"         : return VL1RE8_V;
            "vl1re16.v"      : return VL1RE16_V;
            "vl1re32.v"      : return VL1RE32_V;
            "vl2re8.v",
            "vl2r.v"         : return VL2RE8_V;
            "vl2re16.v"      : return VL2RE16_V;
            "vl2re32.v"      : return VL2RE32_V;
            "vl4re8.v",
            "vl4r.v"         : return VL4RE8_V;
            "vl4re16.v"      : return VL4RE16_V;
            "vl4re32.v"      : return VL4RE32_V;
            "vl8re8.v",
            "vl8r.v"         : return VL8RE8_V;
            "vl8re16.v"      : return VL8RE16_V;
            "vl8re32.v"      : return VL8RE32_V;
            // fault-only-first
            "vle8ff.v"       : return VLE8FF_V;
            "vle16ff.v"      : return VLE16FF_V;
            "vle32ff.v"      : return VLE32FF_V;
            // indexed-unordered
            "vluxei8.v"      : return VLUXEI8_V;
            "vluxei16.v"     : return VLUXEI16_V;
            "vluxei32.v"     : return VLUXEI32_V;
            // strided
            "vlse8.v"        : return VLSE8_V;
            "vlse16.v"       : return VLSE16_V;
            "vlse32.v"       : return VLSE32_V;
            // mop=11 – indexed-ordered
            "vloxei8.v"      : return VLOXEI8_V;
            "vloxei16.v"     : return VLOXEI16_V;
            "vloxei32.v"     : return VLOXEI32_V;

            //////////////////
            // OPCODE_STORE //
            //////////////////

            // unit-stride
            "vse8.v"         : return VSE8_V;
            "vse16.v"        : return VSE16_V;
            "vse32.v"        : return VSE32_V;
            // mask store
            "vsm.v"          : return VSM_V;
            // whole-register stores 
            "vs1r.v"         : return VS1R_V;
            "vs2r.v"         : return VS2R_V;
            "vs4r.v"         : return VS4R_V;
            "vs8r.v"         : return VS8R_V;
            // indexed-unordered
            "vsuxei8.v"      : return VSUXEI8_V;
            "vsuxei16.v"     : return VSUXEI16_V;
            "vsuxei32.v"     : return VSUXEI32_V;
            // strided
            "vsse8.v"        : return VSSE8_V;
            "vsse16.v"       : return VSSE16_V;
            "vsse32.v"       : return VSSE32_V;
            // indexed-ordered
            "vsoxei8.v"      : return VSOXEI8_V;
            "vsoxei16.v"     : return VSOXEI16_V;
            "vsoxei32.v"     : return VSOXEI32_V;
            default          : return INSTR_NONE;

        endcase
    endfunction

  // Returns the expected register_read value for a given mnemonic.
  // Encoding: {rs2_read, rs1_read}
  //   2'b00 – no scalar register
  //   2'b01 – rs1 only          
  //   2'b11 – rs1 and rs2       
  //   2'b10 – never produced by decoder
    function automatic readregflags_t expected_regread(input string mn);
        case (mn)

            // cfg: vsetvl
            "vsetvl"                                              : return 2'b11;
            "vsetvli"                                             : return 2'b01;
            "vsetivli"                                            : return 2'b00;

            // OPIVX – all read rs1
            "vadd.vx",   "vsub.vx",   "vrsub.vx",
            "vminu.vx",  "vmin.vx",   "vmaxu.vx",  "vmax.vx",
            "vand.vx",   "vor.vx",    "vxor.vx",
            "vrgather.vx",
            "vslideup.vx", "vslidedown.vx",
            "vadc.vxm",  "vmadc.vxm", "vmadc.vx",
            "vsbc.vxm",  "vmsbc.vxm", "vmsbc.vx",
            "vmerge.vxm",
            "vmseq.vx",  "vmsne.vx",  "vmsltu.vx", "vmslt.vx",
            "vmsleu.vx", "vmsle.vx",  "vmsgtu.vx", "vmsgt.vx",
            "vsaddu.vx", "vsadd.vx",  "vssubu.vx", "vssub.vx",
            "vsll.vx",   "vsmul.vx",
            "vsrl.vx",   "vsra.vx",   "vssrl.vx",  "vssra.vx",
            "vnsrl.wx",  "vnsra.wx",  "vnclipu.wx","vnclip.wx"  : return 2'b01;

            // OPMVX – all read rs1
            "vaaddu.vx",   "vaadd.vx",   "vasubu.vx",   "vasub.vx",
            "vslide1up.vx","vslide1down.vx",
            "vdivu.vx",    "vdiv.vx",    "vremu.vx",    "vrem.vx",
            "vmulhu.vx",   "vmul.vx",    "vmulhsu.vx",  "vmulh.vx",
            "vmadd.vx",    "vnmsub.vx",  "vmacc.vx",    "vnmsac.vx",
            "vwaddu.vx",   "vwadd.vx",   "vwsubu.vx",   "vwsub.vx",
            "vwaddu.wx",   "vwadd.wx",   "vwsubu.wx",   "vwsub.wx",
            "vwmulu.vx",   "vwmulsu.vx", "vwmul.vx",
            "vwmaccu.vx",  "vwmacc.vx",  "vwmaccus.vx", "vwmaccsu.vx",
            "vmv.s.x"                                            : return 2'b01;

            // Loads – rs1=base only
            "vle8.v",    "vle16.v",   "vle32.v",
            "vlm.v",
            "vl1re8.v",  "vl1r.v",   "vl1re16.v", "vl1re32.v",
            "vl2re8.v",  "vl2r.v",   "vl2re16.v", "vl2re32.v",
            "vl4re8.v",  "vl4r.v",   "vl4re16.v", "vl4re32.v",
            "vl8re8.v",  "vl8r.v",   "vl8re16.v", "vl8re32.v",
            "vle8ff.v",  "vle16ff.v","vle32ff.v",
            "vluxei8.v", "vluxei16.v","vluxei32.v",
            "vloxei8.v", "vloxei16.v","vloxei32.v"              : return 2'b01;

            // Loads (strided) – rs1=base, rs2=stride
            "vlse8.v",   "vlse16.v",  "vlse32.v"                : return 2'b11;

            // Stores – rs1=base only
            "vse8.v",    "vse16.v",   "vse32.v",
            "vsm.v",
            "vs1r.v",    "vs2r.v",    "vs4r.v",    "vs8r.v",
            "vsuxei8.v", "vsuxei16.v","vsuxei32.v",
            "vsoxei8.v", "vsoxei16.v","vsoxei32.v"              : return 2'b01;

            // Stores (strided) – rs1=base, rs2=stride
            "vsse8.v",   "vsse16.v",  "vsse32.v"                : return 2'b11;
            default                                             : return 2'b00;
        endcase
    endfunction

    initial begin : stim
    
        if (!$value$plusargs("stimulus_path=%s", stimulus_file))
        stimulus_file = "stimulus.txt";
    
        if (!$value$plusargs("VERBOSE=%d", verbose))
        verbose = 0;
    
        // Open file 
        file_handle = $fopen(stimulus_file, "r");
        if (!file_handle) $fatal(1, "Cannot open stimulus file: %s", stimulus_file);
    
        $display("     ========================================================");
        $display("[TB] tb_xif_decoder  -  stimulus: %s", stimulus_file);
        $display("     ========================================================");
    
        total_instr    = 0;
        accepted_instr = 0;
        illegal_instr  = 0;
        mismatch_instr = 0;
    
        issue_valid = 1'b1; 
        instr = '0;
        #1;   
    
        // Stimulus loop: one iteration per line in the file.
        // File format (matches gen_stimulus.py output):
        //   <instr_hex32> <rs1_hex32> <rs2_hex32> <mnemonic>
        while (!$feof(file_handle)) begin
    
        scan_result = $fscanf(file_handle, "%h %h %h %s\n",
                                curr_instr, curr_rs1, curr_rs2, curr_mnemonic);
    
        // Skip malformed / blank lines
        if (scan_result != 4) continue;
    
        instr = curr_instr;
        #1; 
    
        // Scoreboard
        begin : check
            vec_instr_e expected;
            logic       expected_accept;
            readregflags_t expected_rr;

    
            expected        = mnemonic_to_enum(curr_mnemonic);
            expected_accept = (expected != INSTR_NONE);
    
            total_instr++;
            if (accept) accepted_instr++;
            else         illegal_instr++;
    
            if (verbose || (accept != expected_accept) ||
                (accept && (vec_instr !== expected))) begin
    
            $display("[TB] instr #%0d  [0x%08h]  mnemonic=%-14s",
                    total_instr, curr_instr, curr_mnemonic);
            $display("         fields : %s", decode_fields(curr_instr));
            $display("         accept=%0b  writeback=%0b  reg_read={rs2=%0b,rs1=%0b}  vec_instr=%0s",
                    accept, writeback,
                    register_read[1], register_read[0],
                    vec_instr.name());
    
            // Check 1: accept vs expected
            if (accept !== expected_accept) begin
                $display("         MISMATCH  accept got=%0b expected=%0b",
                        accept, expected_accept);
                mismatch_instr++;
            end
    
            // Check 2: decoded enum vs expected (only when accepted)
            if (accept && expected_accept && (vec_instr !== expected)) begin
                $display("         MISMATCH  vec_instr got=%-20s expected=%s",
                        vec_instr.name(), expected.name());
                mismatch_instr++;
            end
    
            // Check 3: writeback sanity – only cfg instr should set it
            if (writeback && !(curr_mnemonic inside {"vsetvli","vsetivli","vsetvl"})) begin
                $display("         WARNING   writeback=1 but mnemonic is not a cfg instr");
            end

            // Check 4: register_read flags          
            expected_rr = expected_regread(curr_mnemonic);
            if (accept && (register_read !== expected_rr)) begin
                $display("         MISMATCH  register_read got=%02b expected=%02b  (rs2=%0b rs1=%0b)",
                        register_read, expected_rr,
                        expected_rr[1], expected_rr[0]);
                mismatch_instr++;
            end
            
    
            if (verbose && accept === expected_accept &&
                (!accept || vec_instr === expected))
                $display("         OK");
    
            $display("");
            end // if verbose || mismatch
        end : check
    
        end // while
    
        $fclose(file_handle);
    
        $display("[TB] ========================================================");
        $display("[TB] SUMMARY");
        $display("[TB]   Total instructions : %0d", total_instr);
        $display("[TB]   Accepted           : %0d", accepted_instr);
        $display("[TB]   ILLEGAL            : %0d", illegal_instr);
        $display("[TB]   Mismatches         : %0d", mismatch_instr);
        if (mismatch_instr == 0)
        $display("[TB]   RESULT: PASS");
        else
        $display("[TB]   RESULT: FAIL  (%0d mismatch(es))", mismatch_instr);
        $display("[TB] ========================================================");
    
        $finish;
    end : stim

endmodule : tb_xif_decoder