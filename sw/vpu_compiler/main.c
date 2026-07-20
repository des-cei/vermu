// vpu_compiler.c
// Main application for simple instruction test in tb.

#include <stdio.h>
#include <stdint.h>

int main(void)
{

    asm volatile("vsetivli t0, 8, e16, m1, ta, ma");

    asm volatile("vadd.vi v1, v0, 1" ::: "v1");
    asm volatile("vadd.vi v2, v0, 2" ::: "v2");
    asm volatile("vadd.vi v3, v0, 3" ::: "v3");
    asm volatile("vadd.vi v4, v0, 4" ::: "v4");
    asm volatile("vadd.vi v5, v0, 5" ::: "v5");
    asm volatile("vadd.vi v6, v0, 6" ::: "v6");
    asm volatile("vadd.vi v7, v0, 7" ::: "v7");
    asm volatile("vadd.vi v8, v0, 8" ::: "v8");
    asm volatile("vadd.vi v9, v0, 9" ::: "v9");

    asm volatile("vadd.vi v1, v0, 0");
    asm volatile("vadd.vi v2, v0, 1");
    asm volatile("vadd.vi v3, v0, 15");
    asm volatile("vadd.vi v4, v0, -1");
    asm volatile("vadd.vi v5, v0, -8");
    asm volatile("vadd.vi v6, v0, -16");
    asm volatile("vadd.vi v7, v0, 7");
    asm volatile("vadd.vi v8, v0, -7");
    asm volatile("vadd.vi v9, v0, 5");

    asm volatile("vadd.vv v10, v1, v1");
    asm volatile("vadd.vv v11, v2, v2");
    asm volatile("vadd.vv v12, v3, v4");
    asm volatile("vadd.vv v13, v5, v6");
    asm volatile("vadd.vv v14, v7, v7");

    asm volatile("vadd.vx v15, v1, t0");
    asm volatile("vadd.vx v16, v2, t1");
    asm volatile("vadd.vx v17, v3, t2");

    // VSUB
    asm volatile("vadd.vi v1, v0, 0");
    asm volatile("vadd.vi v2, v0, 1");
    asm volatile("vadd.vi v3, v0, 15");
    asm volatile("vadd.vi v4, v0, -1");
    asm volatile("vadd.vi v5, v0, -8");
    asm volatile("vadd.vi v6, v0, -16");
    asm volatile("vadd.vi v7, v0, 7");
    asm volatile("vadd.vi v8, v0, -7");
    asm volatile("vadd.vi v9, v0, 5");

    asm volatile("vsub.vv v10, v1, v1");
    asm volatile("vsub.vv v11, v2, v2");
    asm volatile("vsub.vv v12, v3, v4");
    asm volatile("vsub.vv v13, v5, v6");
    asm volatile("vsub.vv v14, v7, v8");
    asm volatile("vsub.vv v15, v9, v2");

    asm volatile("li t0, 1");
    asm volatile("li t1, -1");
    asm volatile("li t2, 15");
    asm volatile("li t3, -16");

    asm volatile("vsub.vx v16, v1, t0");
    asm volatile("vsub.vx v17, v2, t1");
    asm volatile("vsub.vx v13,  v3, t2");
    asm volatile("vsub.vx v14,  v4, t3");

    asm volatile("li t0, 6");
    asm volatile("vrsub.vx v15, v9, t0 ");
    asm volatile("vrsub.vi v15, v9, 10");
    asm volatile("vneg.v v15, v9");

    // AND
    asm volatile("vand.vv v11, v0, v2");
    asm volatile("vand.vx v12, v0, x1");
    asm volatile("vand.vi v13, v4, -1");
    asm volatile("vand.vi v14, v0, 0x0F");

    // OR
    asm volatile("vor.vv v15, v0, v2");
    asm volatile("vor.vx v16, v0, x2");
    asm volatile("vor.vi v17, v0, 1");
    asm volatile("vor.vi v18, v0, -16");

    // XOR
    asm volatile("vxor.vv v19, v0, v2");
    asm volatile("vxor.vx v20, v0, x3");
    asm volatile("vxor.vi v21, v0, 0xF");
    asm volatile("vxor.vi v22, v0, -8");

    // NOT
    asm volatile("vnot.v v12, v1");
    asm volatile("vnot.v v13, v2");

    // SHIFT
    asm volatile("vsll.vv v10, v2, v1");
    asm volatile("vsll.vx v11, v3, t0");
    asm volatile("vsll.vi v12, v7, 2");
    asm volatile("vsrl.vv v13, v4, v1");
    asm volatile("vsrl.vx v14, v4, t0");
    asm volatile("vsrl.vi v15, v7, 2");
    asm volatile("vsra.vv v16, v8, v1");
    asm volatile("vsra.vx v17, v8, t0");
    asm volatile("vsra.vi v18, v8, 2");

    // MIN
    asm volatile("vminu.vv v20, v3, v4");
    asm volatile("vminu.vv v21, v5, v2");
    asm volatile("vminu.vx v22, v6, x5");
    asm volatile("vminu.vx v23, v7, x4");
    asm volatile("vmin.vv v24, v3, v5");
    asm volatile("vmin.vv v25, v2, v4");
    asm volatile("vmin.vx v26, v7, x6");
    asm volatile("vmin.vx v27, v8, x0");

    // MAX
    asm volatile("vmaxu.vv v28, v3, v4");
    asm volatile("vmaxu.vv v29, v5, v2");
    asm volatile("vmaxu.vx v30, v6, x5");
    asm volatile("vmaxu.vx v31, v7, x4");
    asm volatile("vmax.vv v28, v3, v5");
    asm volatile("vmax.vv v29, v2, v4");
    asm volatile("vmax.vx v30, v7, x6");
    asm volatile("vmax.vx v31, v8, x3");

    // COMPARISON
    asm volatile("vmseq.vv v0, v3, v20");
    asm volatile("vmseq.vi v0, v2, 0");
    asm volatile("vmseq.vi v0, v3, 15");
    asm volatile("vmseq.vx v0, v4, t0");
    asm volatile("vmseq.vx v0, v7, t1");
    asm volatile("vmsne.vv v0, v3, v20");
    asm volatile("vmsne.vi v0, v2, 0");
    asm volatile("vmsne.vi v0, v3, 15");
    asm volatile("vmsne.vx v0, v4, t0");
    asm volatile("vmsne.vx v0, v7, t1");
    asm volatile("vmsltu.vv v0, v3, v2");
    asm volatile("vmsltu.vv v0, v8, v7");
    asm volatile("vmsltu.vx v0, v2, t0");
    asm volatile("vmsltu.vx v0, v3, t1");
    asm volatile("vmslt.vv v0, v4, v5");
    asm volatile("vmslt.vv v0, v6, v5");
    asm volatile("vmslt.vv v0, v7, v3");
    asm volatile("vmslt.vx v0, v5, t0");
    asm volatile("vmslt.vx v0, v7, t1");
    asm volatile("vmsgtu.vv v0, v2, v1");
    asm volatile("vmsgtu.vv v0, v1, v2");
    asm volatile("vmsgtu.vv v0, v3, v7");
    asm volatile("vmsgtu.vv v0, v8, v7");
    asm volatile("vmsgt.vv v0, v2, v1");
    asm volatile("vmsgt.vv v0, v1, v2");
    asm volatile("vmsgt.vv v0, v7, v3");
    asm volatile("vmsgt.vv v0, v5, v4");
    asm volatile("vmsgt.vv v0, v4, v5");

    // MULTIPLY
    asm volatile("vmul.vv v20, v1, v7");
    asm volatile("vmul.vv v21, v5, v7");
    asm volatile("vmul.vv v22, v4, v3");
    asm volatile("vmul.vx v23, v7, t0");
    asm volatile("vmul.vx v24, v8, t0");
    asm volatile("vmul.vx v25, v6, t0");
    asm volatile("vmulh.vv v26, v1, v7");
    asm volatile("vmulh.vv v27, v5, v7");
    asm volatile("vmulh.vv v28, v4, v4");
    asm volatile("vmulh.vx v29, v5, t0");
    asm volatile("vmulh.vx v30, v8, t0");
    asm volatile("vmulh.vx v31, v6, t0");

    asm volatile("vmulhu.vv v22, v2, v3");
    asm volatile("vmulhu.vv v23, v3, v3");
    asm volatile("vmulhu.vv v24, v4, v4");
    asm volatile("vmulhu.vx v25, v3, t0");
    asm volatile("vmulhu.vx v26, v4, t0");

    asm volatile("vmulhsu.vv v17, v5, v3");
    asm volatile("vmulhsu.vv v18, v4, v4");
    asm volatile("vmulhsu.vv v19, v7, v4");
    asm volatile("vmulhsu.vx v20, v8, t0");
    asm volatile("vmulhsu.vx v21, v4, t0");
    asm volatile("vmulhsu.vx v22, v7, t0");

    // VMACC
    asm volatile("vmacc.vx v15, t0, v7");
    asm volatile("vmacc.vv v9, v2, v7");
    asm volatile("vnmsac.vv v22, v2, v13");
    asm volatile("vnmsac.vx v9, t0, v7");

    asm volatile("vsetivli t0, 8, e32, m1, ta, ma");
    asm volatile("vsetivli t0, 4, e16, m1, ta, ma");
    asm volatile("vmacc.vx v22, t0, v19");

    // Reset values
    asm volatile("vadd.vi v1, v0, 0");
    asm volatile("vadd.vi v2, v0, 1");
    asm volatile("vadd.vi v3, v0, 15");
    asm volatile("vadd.vi v4, v0, -1");
    asm volatile("vadd.vi v5, v0, -8");
    asm volatile("vadd.vi v6, v0, -16");
    asm volatile("vadd.vi v7, v0, 7");
    asm volatile("vadd.vi v8, v0, -7");
    asm volatile("vadd.vi v9, v0, 5");

    // Move
    asm volatile("vmv.v.v v13, v3");
    asm volatile("vmv.v.v v14, v4");
    asm volatile("vmv.v.x v13, t0");
    asm volatile("vmv.v.x v14, t0");
    asm volatile("vmv.v.i v13, 15");
    asm volatile("vmv.v.i v14, 15");
    asm volatile("vmv.v.v v14, v14");

    asm volatile("vmv1r.v v16, v4");
    asm volatile("vmv2r.v v16, v9");
    asm volatile("vmv4r.v v16, v4");
    asm volatile("vmv8r.v v16, v9");

    asm volatile("vmv.x.s t0, v20");
    asm volatile("vmv.s.x v20, t0");

    // Reduction
    asm volatile("vredsum.vs v15, v9, v3");

    asm volatile("csrr t0,vlenb");

    asm volatile("vsetivli t0, 7, e8, m1, ta, ma");
    asm volatile("vredsum.vs v15, v12, v18");
    asm volatile("vsetivli t0, 3, e16, m1, ta, ma");
    asm volatile("vredsum.vs v15, v9, v24");

    asm volatile("vsetivli t0, 4, e16, m1, ta, ma");
    asm volatile("vadd.vx v18, v0, t0");
    asm volatile("vadd.vx v19, v0, t0");
    asm volatile("vredsum.vs v15, v12, v18");
    asm volatile("vredsum.vs v15, v12, v19");

    // Merge
    asm volatile("vmerge.vvm v12, v9, v18, v0");
    asm volatile("vmerge.vxm v12, v9, t0, v0");
    asm volatile("vmerge.vim v12, v9, 5, v0");

    return 0;
}
