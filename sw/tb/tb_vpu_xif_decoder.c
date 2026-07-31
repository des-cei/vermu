// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)
//
// Purpose: exercise every instruction family decoded by vpu_xif_decoder.
// Compile with a RISC-V toolchain that supports RVV (Zve32x):
// Then disassemble.  
// Feed the dump into gen_stimulus.py

#include <stdint.h>

// Dummy arrays in memory so load/store addresses are valid
volatile uint8_t  mem8[64]  = {0};
volatile uint16_t mem16[32] = {0};
volatile uint32_t mem32[16] = {0};

void main(void) {

    // 0. Vector configuration (OPCFG / FMT_OPCFG_CSRRCI)                 
    uint32_t vl;

    // vsetvli  t0, a0, e32, m1, ta, ma
    asm volatile ("vsetvli %0, a0, e32, m1, ta, ma" : "=r"(vl));

    // vsetivli t0, 4, e32, m1, ta, ma  (uimm5 = 4)
    asm volatile ("vsetivli %0, 4, e32, m1, ta, ma" : "=r"(vl));

    // vsetvl   t0, a0, a1
    asm volatile ("vsetvl %0, a0, a1" : "=r"(vl));

    // 1. Unit-stride loads (OPCODE_LOAD / mop=00)                        
    asm volatile ("vle8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vle16.v v2, (%0)" :: "r"(mem16));
    asm volatile ("vle32.v v4, (%0)" :: "r"(mem32));

    // 2. Strided loads (OPCODE_LOAD / mop=10)                           
    register int stride asm("a1") = 4;
    asm volatile ("vlse8.v  v6, (%0), %1" :: "r"(mem8),  "r"(stride));
    asm volatile ("vlse16.v v8, (%0), %1" :: "r"(mem16), "r"(stride));
    asm volatile ("vlse32.v v10, (%0), %1" :: "r"(mem32), "r"(stride));

    // 3. Unit-stride stores (OPCODE_STORE / mop=00)                      
    asm volatile ("vse8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vse16.v v2, (%0)" :: "r"(mem16));
    asm volatile ("vse32.v v4, (%0)" :: "r"(mem32));

    // 4. Integer VV (FMT_OPIVV)                                          

    asm volatile ("vadd.vv  v0, v2, v4");
    asm volatile ("vsub.vv  v0, v2, v4");
    asm volatile ("vminu.vv v0, v2, v4");
    asm volatile ("vmin.vv  v0, v2, v4");
    asm volatile ("vmaxu.vv v0, v2, v4");
    asm volatile ("vmax.vv  v0, v2, v4");
    asm volatile ("vand.vv  v0, v2, v4");
    asm volatile ("vor.vv   v0, v2, v4");
    asm volatile ("vxor.vv  v0, v2, v4");

    asm volatile ("vmseq.vv   v0, v2, v4");
    asm volatile ("vmsne.vv   v0, v2, v4");
    asm volatile ("vmsleu.vv  v0, v2, v4");
    asm volatile ("vmsle.vv   v0, v2, v4");
    asm volatile ("vsaddu.vv  v0, v2, v4");
    asm volatile ("vsadd.vv   v0, v2, v4");
    asm volatile ("vsll.vv    v0, v2, v4");
    asm volatile ("vsmul.vv   v0, v2, v4");
    asm volatile ("vsrl.vv    v0, v2, v4");
    asm volatile ("vsra.vv    v0, v2, v4");
    asm volatile ("vssrl.vv   v0, v2, v4");
    asm volatile ("vssra.vv   v0, v2, v4");


    // 5. Integer VX (FMT_OPIVX)                                          
    register int rs1 asm("a0") = 5;

    asm volatile ("vadd.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsub.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vrsub.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vminu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmin.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmaxu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmax.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vand.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vor.vx     v0, v2, %0" :: "r"(rs1));
    asm volatile ("vxor.vx    v0, v2, %0" :: "r"(rs1));

    asm volatile ("vadc.vxm   v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmadc.vxm  v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vsbc.vxm   v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmsbc.vxm  v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmerge.vxm v0, v2, %0, v0" :: "r"(rs1));

    asm volatile ("vmseq.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsne.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsltu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmslt.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsleu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsle.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsgtu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsgt.vx   v0, v2, %0" :: "r"(rs1));

    asm volatile ("vsaddu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsadd.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssubu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssub.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsll.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsmul.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsrl.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsra.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssrl.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssra.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vnsrl.wx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vnsra.wx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vnclipu.wx v0, v2, %0" :: "r"(rs1));
    asm volatile ("vnclip.wx  v0, v2, %0" :: "r"(rs1));

    // 6. Integer VI (FMT_OPIVI_CSRRC)                                 
    asm volatile ("vadd.vi    v0, v2, 3");
    asm volatile ("vrsub.vi   v0, v2, 3");
    asm volatile ("vand.vi    v0, v2, 3");
    asm volatile ("vor.vi     v0, v2, 3");
    asm volatile ("vxor.vi    v0, v2, 3");
    asm volatile ("vmadc.vim  v0, v2, 3, v0");
    asm volatile ("vmerge.vim v0, v2, 3, v0");
    asm volatile ("vmseq.vi   v0, v2, 3");
    asm volatile ("vmsne.vi   v0, v2, 3");
    asm volatile ("vmsleu.vi  v0, v2, 3");
    asm volatile ("vmsle.vi   v0, v2, 3");
    asm volatile ("vmsgtu.vi  v0, v2, 3");
    asm volatile ("vmsgt.vi   v0, v2, 3");
    asm volatile ("vsaddu.vi  v0, v2, 3");
    asm volatile ("vsadd.vi   v0, v2, 3");
    asm volatile ("vsll.vi    v0, v2, 3");
    asm volatile ("vsrl.vi    v0, v2, 3");
    asm volatile ("vsra.vi    v0, v2, 3");
    asm volatile ("vssrl.vi   v0, v2, 3");
    asm volatile ("vssra.vi   v0, v2, 3");
    asm volatile ("vnsrl.wi   v0, v2, 3");
    asm volatile ("vnsra.wi   v0, v2, 3");
    asm volatile ("vnclipu.wi v0, v2, 3");
    asm volatile ("vnclip.wi  v0, v2, 3");

    // 7. OPMVV – multiply/macc/reductions/VWXUNARY0/VMUNARY0           
    asm volatile ("vredsum.vs  v0, v2, v4");
    asm volatile ("vmulhu.vv   v0, v2, v4");
    asm volatile ("vmul.vv     v0, v2, v4");
    asm volatile ("vmulh.vv    v0, v2, v4");
    asm volatile ("vmacc.vv    v0, v2, v4");
    asm volatile ("vnmsac.vv   v0, v2, v4");

    // VWXUNARY0 (funct6=010000, OPMVV): vs1 field selects operation
    asm volatile ("vmv.x.s %0, v2" : "=r"(vl));   // VMV_XS : vs1=00000
    asm volatile ("vcpop.m %0, v2" : "=r"(vl));   // VCPOP_M: vs1=10000
    asm volatile ("vfirst.m %0, v2" : "=r"(vl));  // VFIRST_M: vs1=10001

    // VMUNARY0 (funct6=010100, OPMVV): vs1 field selects operation
    asm volatile ("vmsbf.m  v0, v2");
    asm volatile ("vmsof.m  v0, v2");
    asm volatile ("vmsif.m  v0, v2");
    asm volatile ("viota.m  v0, v2");
    asm volatile ("vid.v    v0");

    // Additional OPMVV instructions
    asm volatile ("vredand.vs  v0, v2, v4");
    asm volatile ("vredor.vs   v0, v2, v4");
    asm volatile ("vredxor.vs  v0, v2, v4");
    asm volatile ("vredminu.vs v0, v2, v4");
    asm volatile ("vredmin.vs  v0, v2, v4");
    asm volatile ("vredmaxu.vs v0, v2, v4");
    asm volatile ("vredmax.vs  v0, v2, v4");
    asm volatile ("vaaddu.vv   v0, v2, v4");
    asm volatile ("vaadd.vv    v0, v2, v4");
    asm volatile ("vasubu.vv   v0, v2, v4");
    asm volatile ("vasub.vv    v0, v2, v4");
    asm volatile ("vdivu.vv    v0, v2, v4");
    asm volatile ("vdiv.vv     v0, v2, v4");
    asm volatile ("vremu.vv    v0, v2, v4");
    asm volatile ("vrem.vv     v0, v2, v4");
    asm volatile ("vmulhu.vv   v0, v2, v4");
    asm volatile ("vmulhsu.vv  v0, v2, v4");
    asm volatile ("vmadd.vv    v0, v2, v4");
    asm volatile ("vnmsub.vv   v0, v2, v4");
    asm volatile ("vwaddu.vv   v0, v2, v4");
    asm volatile ("vwadd.vv    v0, v2, v4");
    asm volatile ("vwsubu.vv   v0, v2, v4");
    asm volatile ("vwsub.vv    v0, v2, v4");
    asm volatile ("vwaddu.wv   v0, v2, v4");
    asm volatile ("vwadd.wv    v0, v2, v4");
    asm volatile ("vwsubu.wv   v0, v2, v4");
    asm volatile ("vwsub.wv    v0, v2, v4");
    asm volatile ("vwmulu.vv   v0, v2, v4");
    asm volatile ("vwmulsu.vv  v0, v2, v4");
    asm volatile ("vwmul.vv    v0, v2, v4");
    asm volatile ("vwmaccu.vv  v0, v2, v4");
    asm volatile ("vwmacc.vv   v0, v2, v4");
    asm volatile ("vwmaccsu.vv v0, v2, v4");

    // Mask-logical operations
    asm volatile ("vmandnot.mm v0, v2, v4");
    asm volatile ("vmand.mm    v0, v2, v4");
    asm volatile ("vmor.mm     v0, v2, v4");
    asm volatile ("vmxor.mm    v0, v2, v4");
    asm volatile ("vmornot.mm  v0, v2, v4");
    asm volatile ("vmnand.mm   v0, v2, v4");
    asm volatile ("vmnor.mm    v0, v2, v4");
    asm volatile ("vmxnor.mm   v0, v2, v4");
    asm volatile ("vcompress.vm v0, v2, v0");

    // 8. OPMVX – multiply/macc/div/shift scalar operations
    asm volatile ("vaaddu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vaadd.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vasubu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vasub.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vslide1up.vx v0, v2, %0" :: "r"(rs1));
    asm volatile ("vslide1down.vx v0, v2, %0" :: "r"(rs1));
    asm volatile ("vdivu.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vdiv.vx     v0, v2, %0" :: "r"(rs1));
    asm volatile ("vremu.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vrem.vx     v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmulhu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmulhsu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmadd.vx    v0, %0, v2" :: "r"(rs1));
    asm volatile ("vnmsub.vx   v0, %0, v2" :: "r"(rs1));
    asm volatile ("vwaddu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwadd.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwsubu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwsub.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwaddu.wx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwadd.wx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwsubu.wx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwsub.wx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwmulu.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwmulsu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwmul.vx    v0, v2, %0" :: "r"(rs1));
    asm volatile ("vwmaccu.vx  v0, %0, v2" :: "r"(rs1));
    asm volatile ("vwmacc.vx   v0, %0, v2" :: "r"(rs1));
    asm volatile ("vwmaccus.vx v0, %0, v2" :: "r"(rs1));
    asm volatile ("vwmaccsu.vx v0, %0, v2" :: "r"(rs1));

    // VRXUNARY0 (funct6=010000, OPMVX): vs2 field selects op
    asm volatile ("vmv.s.x v0, %0" :: "r"(rs1));  // VMV_SX

    // VXUNARY0 (funct6=010010, OPMVX): vs1 field selects op
    asm volatile ("vzext.vf8 v0, v2");   // VZEXT_VF8 (vs1=00010)
    asm volatile ("vsext.vf8 v0, v2");   // VSEXT_VF8 (vs1=00011)
    asm volatile ("vzext.vf4 v0, v2");   // VZEXT_VF4 (vs1=00100)
    asm volatile ("vsext.vf4 v0, v2");   // VSEXT_VF4 (vs1=00101)
    asm volatile ("vzext.vf2 v0, v2");   // VZEXT_VF2 (vs1=00110)
    asm volatile ("vsext.vf2 v0, v2");   // VSEXT_VF2 (vs1=00111)

    // 9. Additional VV operations (narrow/shift/gather)
    asm volatile ("vrgather.vv  v0, v2, v4");
    asm volatile ("vrgather.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vrgather.vi  v0, v2, 3");
    asm volatile ("vrgatherei16.vv v0, v2, v4");
    asm volatile ("vslideup.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vslidedown.vx v0, v2, %0" :: "r"(rs1));
    asm volatile ("vslideup.vi   v0, v2, 3");
    asm volatile ("vslidedown.vi v0, v2, 3");

    // 10. Narrowing shift and clip operations (VV/VX/VI)
    asm volatile ("vnsrl.wv     v0, v2, v4");
    asm volatile ("vnsra.wv     v0, v2, v4");
    asm volatile ("vnclipu.wv   v0, v2, v4");
    asm volatile ("vnclip.wv    v0, v2, v4");

    // 11. Wide reductions
    asm volatile ("vwredsumu.vs v0, v2, v4");
    asm volatile ("vwredsum.vs  v0, v2, v4");

    // 12. Whole register load/store operations
    asm volatile ("vl1re8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vl1re16.v v0, (%0)" :: "r"(mem16));
    asm volatile ("vl1re32.v v0, (%0)" :: "r"(mem32));
    asm volatile ("vl2re8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vl2re16.v v0, (%0)" :: "r"(mem16));
    asm volatile ("vl2re32.v v0, (%0)" :: "r"(mem32));
    asm volatile ("vl4re8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vl4re16.v v0, (%0)" :: "r"(mem16));
    asm volatile ("vl4re32.v v0, (%0)" :: "r"(mem32));
    asm volatile ("vl8re8.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vl8re16.v v0, (%0)" :: "r"(mem16));
    asm volatile ("vl8re32.v v0, (%0)" :: "r"(mem32));

    asm volatile ("vs1r.v v0, (%0)" :: "r"(mem8));
    asm volatile ("vs2r.v v0, (%0)" :: "r"(mem8));
    asm volatile ("vs4r.v v0, (%0)" :: "r"(mem8));
    asm volatile ("vs8r.v v0, (%0)" :: "r"(mem8));

    // 13. Mask load/store
    asm volatile ("vlm.v v0, (%0)" :: "r"(mem8));
    asm volatile ("vsm.v v0, (%0)" :: "r"(mem8));

    // 14. Fault-only-first loads
    asm volatile ("vle8ff.v  v0, (%0)" :: "r"(mem8));
    asm volatile ("vle16ff.v v0, (%0)" :: "r"(mem16));
    asm volatile ("vle32ff.v v0, (%0)" :: "r"(mem32));

    // 15. Indexed loads (unordered and ordered)
    asm volatile ("vluxei8.v  v0, (%0), v2" :: "r"(mem8));
    asm volatile ("vluxei16.v v0, (%0), v2" :: "r"(mem16));
    asm volatile ("vluxei32.v v0, (%0), v2" :: "r"(mem32));
    asm volatile ("vloxei8.v  v0, (%0), v2" :: "r"(mem8));
    asm volatile ("vloxei16.v v0, (%0), v2" :: "r"(mem16));
    asm volatile ("vloxei32.v v0, (%0), v2" :: "r"(mem32));

    // 16. Indexed stores (unordered and ordered)
    asm volatile ("vsuxei8.v  v0, (%0), v2" :: "r"(mem8));
    asm volatile ("vsuxei16.v v0, (%0), v2" :: "r"(mem16));
    asm volatile ("vsuxei32.v v0, (%0), v2" :: "r"(mem32));
    asm volatile ("vsoxei8.v  v0, (%0), v2" :: "r"(mem8));
    asm volatile ("vsoxei16.v v0, (%0), v2" :: "r"(mem16));
    asm volatile ("vsoxei32.v v0, (%0), v2" :: "r"(mem32));

    // 17. Strided stores
    asm volatile ("vsse8.v  v0, (%0), %1" :: "r"(mem8),  "r"(stride));
    asm volatile ("vsse16.v v0, (%0), %1" :: "r"(mem16), "r"(stride));
    asm volatile ("vsse32.v v0, (%0), %1" :: "r"(mem32), "r"(stride));

    // 18. Additional arithmetic (gather and other variants)
    asm volatile ("vadc.vvm   v0, v2, v4, v0");
    asm volatile ("vmadc.vvm  v0, v2, v4, v0");
    asm volatile ("vmadc.vv   v0, v2, v4");
    asm volatile ("vsbc.vvm   v0, v2, v4, v0");
    asm volatile ("vmsbc.vvm  v0, v2, v4, v0");
    asm volatile ("vmsbc.vv   v0, v2, v4");
    asm volatile ("vmerge.vvm v0, v2, v4, v0");

    // 19. Additional comparison operations (VV)
    asm volatile ("vmsgtu.vv  v0, v2, v4");
    asm volatile ("vmsgt.vv   v0, v2, v4");

    // 20. Additional saturating arithmetic (VV)
    asm volatile ("vssubu.vv  v0, v2, v4");
    asm volatile ("vssub.vv   v0, v2, v4");

    // 21. Additional immediate-form instructions
    asm volatile ("vadc.vim   v0, v2, 3, v0");
    asm volatile ("vmadc.vim  v0, v2, 3, v0");
    asm volatile ("vmadc.vi   v0, v2, 3");
    asm volatile ("vmerge.vim v0, v2, 3, v0");
    asm volatile ("vsaddu.vi  v0, v2, 3");
    asm volatile ("vsadd.vi   v0, v2, 3");
    asm volatile ("vsll.vi    v0, v2, 3");
    asm volatile ("vsrl.vi    v0, v2, 3");
    asm volatile ("vsra.vi    v0, v2, 3");
    asm volatile ("vssrl.vi   v0, v2, 3");
    asm volatile ("vssra.vi   v0, v2, 3");
    asm volatile ("vnsrl.wi   v0, v2, 3");
    asm volatile ("vnsra.wi   v0, v2, 3");
    asm volatile ("vnclipu.wi v0, v2, 3");
    asm volatile ("vnclip.wi  v0, v2, 3");

    // 22. Additional VX immediate operations
    asm volatile ("vadc.vxm   v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmadc.vxm  v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmadc.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vsbc.vxm   v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmsbc.vxm  v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmsbc.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmerge.vxm v0, v2, %0, v0" :: "r"(rs1));
    asm volatile ("vmsgtu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vmsgt.vx   v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssubu.vx  v0, v2, %0" :: "r"(rs1));
    asm volatile ("vssub.vx   v0, v2, %0" :: "r"(rs1));

    // 23. Additional VI comparison operations
    asm volatile ("vmsltu.vi  v0, v2, 3");
    asm volatile ("vmslt.vi   v0, v2, 3");

    // 25. vmv<nr>r.v – whole-register moves (VMVNRR_V, nr=2/4/8)
    asm volatile ("vmv1r.v    v0, v2");   
    asm volatile ("vmv2r.v    v0, v2");
    asm volatile ("vmv4r.v    v0, v4");
    asm volatile ("vmv8r.v    v0, v8");

}