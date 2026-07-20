#include "csr.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "common.h"
#include <riscv_vector.h>

// matrix multiplication (B is expected in transposed form)
// A[n][o], B[m][o] --> C[n][m];
void matmul_golden32(int32_t **a, int32_t **b_t, int32_t **c, int n, int m, int o)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
        {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
        }
}

void matmul_golden16(int16_t **a, int16_t **b_t, int16_t **c, int n, int m, int o)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
        {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
        }
}

void matmul_golden8(int8_t **a, int8_t **b_t, int8_t **c, int n, int m, int o)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
        {
            c[i][j] = 0;
            for (int k = 0; k < o; ++k)
                c[i][j] += a[i][k] * b_t[j][k];
        }
}

void matmul32(int32_t **a, int32_t **b_t, int32_t **c, int n, int m, int o)
{
    size_t vlmax = __riscv_vsetvlmax_e32m1();
    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < m; ++j)
        {
            int32_t *ptr_a = &a[i][0];
            int32_t *ptr_b = &b_t[j][0];
            int k = o;
            vint32m1_t vec_s = __riscv_vmv_v_x_i32m1(0, vlmax);
            vint32m1_t vec_zero = __riscv_vmv_v_x_i32m1(0, vlmax);

            for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl)
            {
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

void matmul16(int16_t **a, int16_t **b_t, int16_t **c, int n, int m, int o)
{
    size_t vlmax = __riscv_vsetvlmax_e16m1();
    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < m; ++j)
        {
            int16_t *ptr_a = &a[i][0];
            int16_t *ptr_b = &b_t[j][0];
            int k = o;
            vint16m1_t vec_s = __riscv_vmv_v_x_i16m1(0, vlmax);
            vint16m1_t vec_zero = __riscv_vmv_v_x_i16m1(0, vlmax);

            for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl)
            {
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

void matmul8(int8_t **a, int8_t **b_t, int8_t **c, int n, int m, int o)
{
    size_t vlmax = __riscv_vsetvlmax_e8m1();
    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < m; ++j)
        {
            int8_t *ptr_a = &a[i][0];
            int8_t *ptr_b = &b_t[j][0];
            int k = o;
            vint8m1_t vec_s = __riscv_vmv_v_x_i8m1(0, vlmax);
            vint8m1_t vec_zero = __riscv_vmv_v_x_i8m1(0, vlmax);

            for (size_t vl; k > 0; k -= vl, ptr_a += vl, ptr_b += vl)
            {
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

int main()
{
    const int N = 8;
    const int M = 8;
    const int O = 7;

    unsigned int cycles_golden, cycles_vec;
    int speedup;
    int pass;

#define RUN_TEST_MATMUL(test_num, size_n, size_m, size_o, golden_fn, vec_fn, type_name, A_mat, B_mat, gold_mat, actual_mat) \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                                                             \
    CSR_WRITE(CSR_REG_MCYCLE, 0);                                                                                           \
    golden_fn(A_mat, B_mat, gold_mat, size_n, size_m, size_o);                                                              \
    CSR_READ(CSR_REG_MCYCLE, &cycles_golden);                                                                               \
                                                                                                                            \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                                                             \
    CSR_WRITE(CSR_REG_MCYCLE, 0);                                                                                           \
    vec_fn(A_mat, B_mat, actual_mat, size_n, size_m, size_o);                                                               \
    CSR_READ(CSR_REG_MCYCLE, &cycles_vec);                                                                                  \
                                                                                                                            \
    pass = compare_2d_##type_name(gold_mat, actual_mat, size_n, size_m);                                                    \
    speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0;                                          \
                                                                                                                            \
    printf("Test %-2d (N=%d,M=%d,O=%d): %s | Gold: %5u, Vec: %5u | Speedup: %2d.%02dx\r\n",                                 \
           test_num, size_n, size_m, size_o, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup / 100, speedup % 100);

    printf("Starting rvv_matmul Performance Tests:\r\n");

    // TEST 1: int32
    srand(0xdeadbeef);
    int32_t **A = alloc_array_2d_int32(N, O);
    int32_t **B = alloc_array_2d_int32(M, O);
    gen_rand_2d_int32(A, N, O);
    gen_rand_2d_int32(B, M, O);
    int32_t **golden32 = alloc_array_2d_int32(N, M);
    int32_t **actual32 = alloc_array_2d_int32(N, M);
    RUN_TEST_MATMUL(1, N, M, O, matmul_golden32, matmul32, int32, A, B, golden32, actual32);

    // TEST 2: int16
    srand(0xbeef);
    int16_t **C = alloc_array_2d_int16(N, O);
    int16_t **D = alloc_array_2d_int16(M, O);
    gen_rand_2d_int16(C, N, O);
    gen_rand_2d_int16(D, M, O);
    int16_t **golden16 = alloc_array_2d_int16(N, M);
    int16_t **actual16 = alloc_array_2d_int16(N, M);
    RUN_TEST_MATMUL(2, N, M, O, matmul_golden16, matmul16, int16, C, D, golden16, actual16);

    // TEST 3: int8
    srand(0xde);
    int8_t **E = alloc_array_2d_int8(N, O);
    int8_t **F = alloc_array_2d_int8(M, O);
    gen_rand_2d_int8(E, N, O);
    gen_rand_2d_int8(F, M, O);
    int8_t **golden8 = alloc_array_2d_int8(N, M);
    int8_t **actual8 = alloc_array_2d_int8(N, M);
    RUN_TEST_MATMUL(3, N, M, O, matmul_golden8, matmul8, int8, E, F, golden8, actual8);

    return 0;
}
