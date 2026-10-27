#include "csr.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "common.h"
#include <riscv_vector.h>

/*
 * VERMU benchmark: MATMUL  C[N][M] = A[N][O] * B_t[M][O]^T
 *
 * Selected at COMPILE TIME via COMPILER_FLAGS, e.g.:
 *   COMPILER_FLAGS += -DSEW=32 -DN=8 -DM=8 -DO=7 -DDIAG=1
 */

#ifndef SEW
#define SEW 32
#endif
#ifndef N
#define N 8
#endif
#ifndef M
#define M 8
#endif
#ifndef O
#define O 7
#endif
#ifndef DIAG
#define DIAG 0
#endif
#ifndef INCR_DATA
#define INCR_DATA 0
#endif

#if (SEW != 8) && (SEW != 16) && (SEW != 32)
#error "SEW must be 8, 16 or 32 (pass -DSEW=8/16/32 in COMPILER_FLAGS)"
#endif
#if (N < 1) || (M < 1) || (O < 1)
#error "N, M and O must be >= 1"
#endif

/* -------------------------------- */
/* SEW -> function type selection   */
/* -------------------------------- */
#if SEW == 32
    #define I_T          int32_t
    #define GOLDEN_FN    matmul_golden32
    #define VEC_FN       matmul32
    // #define ALLOC_2D     alloc_array_2d_int32
    #define GEN_RAND_2D  gen_rand_2d_int32
    #define COMPARE_2D   compare_2d_int32
    #define SEED         0xdeadbeef
#elif SEW == 16
    #define I_T          int16_t
    #define GOLDEN_FN    matmul_golden16
    #define VEC_FN       matmul16
    // #define ALLOC_2D     alloc_array_2d_int16
    #define GEN_RAND_2D  gen_rand_2d_int16
    #define COMPARE_2D   compare_2d_int16
    #define SEED         0xbeef
#else /* SEW == 8 */
    #define I_T          int8_t
    #define GOLDEN_FN    matmul_golden8
    #define VEC_FN       matmul8
    // #define ALLOC_2D     alloc_array_2d_int8
    #define GEN_RAND_2D  gen_rand_2d_int8
    #define COMPARE_2D   compare_2d_int8
    #define SEED         0xde
#endif

// #if INCR_DATA
// // Constant incremental data (1,2,3,... row-major) for debugging.
// // A and B both read from this table: row i starts at incr_data[i*O]
// #if (N * O > 64) || (M * O > 64)
// #error "INCR_DATA table holds 64 values: need N*O <= 64 and M*O <= 64"
// #endif
// static I_T incr_data[64] = {
//      1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16,
//     17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
//     33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
//     49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64
// };
// static I_T *A_rows[N];
// static I_T *B_rows[M];
// #endif


#if !INCR_DATA
static I_T A_buf[N][O];
static I_T B_buf[M][O];
#endif
static I_T golden_buf[N][M];
static I_T actual_buf[N][M];

static I_T *A_rows[N];
static I_T *B_rows[M];
static I_T *golden_rows[N];
static I_T *actual_rows[N];

#define BIND_ROWS(rows, buf, n)                 \
    for (int _r = 0; _r < (n); ++_r)            \
        (rows)[_r] = (buf)[_r]

#if DIAG

static long expected_elem(I_T **A, I_T **B_t, int i, int j)
{
    long s = 0;
    for (int k = 0; k < O; ++k)
        s += (long)A[i][k] * (long)B_t[j][k];
    return (long)(I_T)s;   
}

#define DIAG_ELEM(i, j)                                                   \
    printf("DIAG golden[%d][%d]=%ld vector[%d][%d]=%ld (expect %ld)\r\n",   \
            (i), (j), (long)((volatile I_T *)golden[i])[j],                  \
            (i), (j), (long)((volatile I_T *)actual[i])[j],                  \
            expected_elem(A, B, (i), (j)))
#endif

/* ------------------------- */
/* matmul golden functions   */
/* ------------------------- */
void matmul_golden32(int32_t **a, int32_t **b_t, int32_t **c, int n, int m, int o) {
    for (int i = 0; i < n; ++i){
        for (int j = 0; j < m; ++j) {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
        }
    }
}

void matmul_golden16(int16_t **a, int16_t **b_t, int16_t **c, int n, int m, int o) {
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j) {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
            }
}

void matmul_golden8(int8_t **a, int8_t **b_t, int8_t **c, int n, int m, int o) {
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j) {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
            }
    }

/* ------------------------- */
/* matmul vector functions   */
/* ------------------------- */

void matmul32(int32_t **a, int32_t **b_t, int32_t **c, int n, int m, int o) {
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    for (int i = 0; i < n; ++i) {
            for (int j = 0; j < m; ++j) {
                int32_t *ptr_a = &a[i][0];
                int32_t *ptr_b = &b_t[j][0];
                int k = o;
                vint32m1_t vec_s    = __riscv_vmv_v_x_i32m1(0, vlmax);
                vint32m1_t vec_zero = __riscv_vmv_v_x_i32m1(0, vlmax);

                for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl) {
                    vl = __riscv_vsetvl_e32m1(k);
                    
                    vint32m1_t vec_a = __riscv_vle32_v_i32m1(ptr_a, vl);
                    vint32m1_t vec_b = __riscv_vle32_v_i32m1(ptr_b, vl);

                    vec_s = __riscv_vmacc_vv_i32m1_tu(vec_s, vec_a, vec_b, vl);
                }

                vint32m1_t vec_sum = __riscv_vredsum_vs_i32m1_i32m1(vec_s, vec_zero, vlmax);

                int32_t sum = __riscv_vmv_x_s_i32m1_i32(vec_sum);
                c[i][j] = sum;
            }
    }
}

void matmul16(int16_t **a, int16_t **b_t, int16_t **c, int n, int m, int o) {
    size_t vlmax = __riscv_vsetvlmax_e16m1();
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < m; ++j) {
            int16_t *ptr_a = &a[i][0];
            int16_t *ptr_b = &b_t[j][0];
            int k = o;
            vint16m1_t vec_s    = __riscv_vmv_v_x_i16m1(0, vlmax);
            vint16m1_t vec_zero = __riscv_vmv_v_x_i16m1(0, vlmax);

            for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl) {
                vl = __riscv_vsetvl_e16m1(k);
                
                vint16m1_t vec_a = __riscv_vle16_v_i16m1(ptr_a, vl);
                vint16m1_t vec_b = __riscv_vle16_v_i16m1(ptr_b, vl);

                vec_s = __riscv_vmacc_vv_i16m1_tu(vec_s, vec_a, vec_b, vl);
            }

            vint16m1_t vec_sum = __riscv_vredsum_vs_i16m1_i16m1(vec_s, vec_zero, vlmax);

            int16_t sum = __riscv_vmv_x_s_i16m1_i16(vec_sum);
            c[i][j] = sum;
        }
    }
}

void matmul8(int8_t **a, int8_t **b_t, int8_t **c, int n, int m, int o) {
    size_t vlmax = __riscv_vsetvlmax_e8m1();
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < m; ++j) {
            int8_t *ptr_a = &a[i][0];
            int8_t *ptr_b = &b_t[j][0];
            int k = o;
            vint8m1_t vec_s    = __riscv_vmv_v_x_i8m1(0, vlmax);
            vint8m1_t vec_zero = __riscv_vmv_v_x_i8m1(0, vlmax);

            for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl) {
                vl = __riscv_vsetvl_e8m1(k);
                
                vint8m1_t vec_a = __riscv_vle8_v_i8m1(ptr_a, vl);
                vint8m1_t vec_b = __riscv_vle8_v_i8m1(ptr_b, vl);

                vec_s = __riscv_vmacc_vv_i8m1_tu(vec_s, vec_a, vec_b, vl);
            }

            vint8m1_t vec_sum = __riscv_vredsum_vs_i8m1_i8m1(vec_s, vec_zero, vlmax);

            int8_t sum = __riscv_vmv_x_s_i8m1_i8(vec_sum);
            c[i][j] = sum;
        }
    }
}

int main(void) {
    uint32_t cycles_golden, cycles_vec;


    srand(SEED);
#if INCR_DATA
    for (int i = 0; i < N; ++i) A_rows[i] = &incr_data[i * O];
    for (int j = 0; j < M; ++j) B_rows[j] = &incr_data[j * O];
    // I_T **A      = A_rows;
    // I_T **B      = B_rows;
#else
    BIND_ROWS(A_rows, A_buf, N);
    BIND_ROWS(B_rows, B_buf, M);
    const int vmax = safe_vmax(SEW, O);
    // I_T **A      = ALLOC_2D(N, O);
    // I_T **B      = ALLOC_2D(M, O);
    GEN_RAND_2D(A_rows, N, O, vmax);
    GEN_RAND_2D(B_rows, M, O, vmax);
#endif
    BIND_ROWS(golden_rows, golden_buf, N);
    BIND_ROWS(actual_rows, actual_buf, N);

    I_T **A      = A_rows;
    I_T **B      = B_rows;
    I_T **golden = golden_rows;
    I_T **actual = actual_rows;

    // I_T **golden = ALLOC_2D(N, M);
    // I_T **actual = ALLOC_2D(N, M);

    // --- Scalar (golden) ---
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
    CSR_WRITE(CSR_REG_MCYCLE, 0);
    GOLDEN_FN(A, B, golden, N, M, O);
    CSR_READ(CSR_REG_MCYCLE, &cycles_golden);

    // --- Vector ---
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
    CSR_WRITE(CSR_REG_MCYCLE, 0);
    VEC_FN(A, B, actual, N, M, O);
    CSR_READ(CSR_REG_MCYCLE, &cycles_vec);

    int pass = COMPARE_2D(golden, actual, N, M);

#if DIAG
    DIAG_ELEM(0, 0);
    DIAG_ELEM(N - 1, M - 1);
#endif

  printf("MATMUL,e%d,N=%d,M=%d,O=%d,%s,golden_cycles=%u,vector_cycles=%u\r\n",
         SEW, N, M, O, pass ? "PASS" : "FAIL",
         (unsigned)cycles_golden, (unsigned)cycles_vec);

  return 0;
}