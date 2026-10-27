#include "csr.h"
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "common.h"
#include <riscv_vector.h>

/*
 * AXPY  (y[i] = a*x[i] + y[i])
 *
 * SEW and N are selected at COMPILE TIME, via the build's COMPILER_FLAGS,
 * e.g.:
 *   COMPILER_FLAGS += -DSEW=32 -DN=32
 */

#ifndef SEW
#define SEW 32
#endif

#ifndef N
#define N 32
#endif

#ifndef DIAG
#define DIAG 0
#endif

#if (SEW != 8) && (SEW != 16) && (SEW != 32)
#error "SEW must be 8, 16 or 32 (pass -DSEW=8/16/32 in COMPILER_FLAGS)"
#endif

#if (N < 1)
#error "N must be >= 1 (pass -DN=.. in COMPILER_FLAGS)"
#endif

 
/* ------------------------------------------------------------------ */
/* Token-pasting glue: SEW -> types / intrinsic names                 */
/* ------------------------------------------------------------------ */
#define CONCAT_(a, b) a##b
#define CONCAT(a, b)  CONCAT_(a, b)

#define I_T   CONCAT(int,  CONCAT(SEW, _t))   /* intN_t   */
#define U_T   CONCAT(uint, CONCAT(SEW, _t))   /* uintN_t  */
#define VI_T  CONCAT(vint, CONCAT(SEW, m1_t)) /* vintNm1_t */

#define VSETVL(n)        CONCAT(__riscv_vsetvl_e, CONCAT(SEW, m1))(n)
#define VLE(p, vl)        CONCAT(CONCAT(__riscv_vle, SEW), CONCAT(_v_i, CONCAT(SEW, m1)))(p, vl)
#define VMACC(vy, a, vx, vl) CONCAT(__riscv_vmacc_vx_i, CONCAT(SEW, m1))(vy, a, vx, vl)
#define VSE(p, vr, vl)    CONCAT(CONCAT(__riscv_vse, SEW), CONCAT(_v_i, CONCAT(SEW, m1)))(p, vr, vl)

/* ------------------------------------------------------------------ */
/* Input data: N random entries, generated at runtime                  */
/* ------------------------------------------------------------------ */
#if SEW == 32
    #define GEN_RAND_1D  gen_rand_1d_int32
    #define SEED         0xdeadbeef
#elif SEW == 16
    #define GEN_RAND_1D  gen_rand_1d_int16
    #define SEED         0xbeef
#else /* SEW == 8 */
    #define GEN_RAND_1D  gen_rand_1d_int8
    #define SEED         0xde
#endif

static I_T input[N];
static I_T scalar_y[N];
static I_T vector_y[N];


/* ------------------------------------------------------------------ */
/* Kernels                                                             */
/* ------------------------------------------------------------------ */
#pragma GCC push_options
#pragma GCC optimize ("O3", "no-tree-vectorize")
static void axpy_scalar(size_t n, I_T a, const I_T *x, I_T *y)
{
    for (size_t i = 0; i < n; ++i)
        y[i] = (I_T)(a * x[i] + y[i]);
}

__attribute__((noinline))
static void init_buffers(void)
{
    for (size_t i = 0; i < N; ++i) {
        scalar_y[i] = input[i];
        vector_y[i] = input[i];
    }
}
#pragma GCC pop_options

static void axpy_vector(size_t n, I_T a, const I_T *x, I_T *y)
{
    for (size_t vl; n > 0; n -= vl, x += vl, y += vl) {
        vl = VSETVL(n);
        VI_T vx = VLE(x, vl);
        VI_T vy = VLE(y, vl);
        VI_T vr = VMACC(vy, a, vx, vl);
        VSE(y, vr, vl);
    }
}

#pragma GCC push_options
#pragma GCC optimize ("O3", "no-tree-vectorize")
static int check(const I_T *gold, const I_T *got, size_t n)
{
    int ok = 1;
    for (size_t i = 0; i < n; ++i) {
        if (gold[i] != got[i]) {
            printf("Mismatch e%d at [%d]: gold = %ld (0x%08lx), "
                   "vec = %ld (0x%08lx)\r\n",
                   SEW, (int)i,
                   (long)gold[i], (unsigned long)(U_T)gold[i],
                   (long)got[i],  (unsigned long)(U_T)got[i]);
            ok = 0;
        }
    }
    return ok;
}
#pragma GCC pop_options

/* ------------------------------------------------------------------ */
/* Cycle counter helpers                                               */
/* ------------------------------------------------------------------ */
static uint32_t read_cycles(void)
{    
    uint32_t cycles;
    CSR_READ(CSR_REG_MCYCLE, &cycles);
    return cycles;
}

static void reset_cycles(void)
{
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
    CSR_WRITE(CSR_REG_MCYCLE, 0);
}

// Raw cycle counts only: speedup and CPE are computed by the host scripts
static void print_result(const char *bench, int sew, size_t n,
                          uint32_t scalar_cycles, uint32_t vector_cycles,
                          int pass)
{
    printf("%s,e%d,N=%u,%s,scalar_cycles=%u,vector_cycles=%u\r\n",
           bench, sew, (unsigned)n, pass ? "PASS" : "FAIL",
           (unsigned)scalar_cycles, (unsigned)vector_cycles);
}

int main(void)
{
    const I_T a = 4;

    srand(SEED);
    GEN_RAND_1D(input, N, safe_vmax(SEW, a));
    init_buffers();

    // --- Scalar ---
    reset_cycles();
    axpy_scalar(N, a, input, scalar_y);
    uint32_t scalar_cycles = read_cycles();

    // --- Vector --- 

    reset_cycles();
    axpy_vector(N, a, input, vector_y);
    uint32_t vector_cycles = read_cycles();    

#if DIAG
    printf("DIAG scalar_y[%d]=%ld (expect %ld)\r\n",
        (int)(N-1), (long)((volatile I_T *)scalar_y)[N-1], (long)(a * input[N-1] + input[N-1]));
    printf("DIAG vector_y[%d]=%ld (expect %ld)\r\n",
        (int)(N-1), (long)((volatile I_T *)vector_y)[N-1], (long)(a * input[N-1] + input[N-1]));
#endif

    print_result("AXPY", SEW, N, scalar_cycles, vector_cycles,
                  check(scalar_y, vector_y, N));

    return 0;
}