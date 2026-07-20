#include "csr.h"
#include <riscv_vector.h>
#include <stdint.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Golden Functions
__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void index_golden32(uint32_t *a, uint32_t *b, uint32_t *c, int n)
{
    for (int i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}
__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void index_golden16(uint16_t *a, uint16_t *b, uint16_t *c, int n)
{
    for (int i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}
__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void index_golden8(uint8_t *a, uint8_t *b, uint8_t *c, int n)
{
    for (int i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}

// Vector Functions
__attribute__((optimize("O3"))) void index_vec32(uint32_t *__restrict a, uint32_t *__restrict b, uint32_t *c, int n)
{
    for (int i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}

__attribute__((optimize("O3"))) void index_vec16(uint16_t *__restrict a, uint16_t *__restrict b, uint16_t *c, uint16_t n)
{
    for (uint16_t i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}

__attribute__((optimize("O3"))) void index_vec8(uint8_t *__restrict a, uint8_t *__restrict b, uint8_t *c, uint8_t n)
{
    for (uint8_t i = 0; i < n; ++i)
    {
        a[i] = b[i] + i * c[i];
    }
}

int main()
{
    const int N = 31;
    const int M = 62;
    const int O = 93;

    unsigned int cycles_golden, cycles_vec;
    int speedup;
    int pass;

#define RUN_TEST(test_num, size, golden_fn, vec_fn, gold_arr, act_arr)             \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                    \
    CSR_WRITE(CSR_REG_MCYCLE, 0);                                                  \
    golden_fn(gold_arr, B_ptr, C_ptr, size);                                       \
    CSR_READ(CSR_REG_MCYCLE, &cycles_golden);                                      \
                                                                                   \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                    \
    CSR_WRITE(CSR_REG_MCYCLE, 0);                                                  \
    vec_fn(act_arr, B_ptr, C_ptr, size);                                           \
    CSR_READ(CSR_REG_MCYCLE, &cycles_vec);                                         \
                                                                                   \
    pass = 1;                                                                      \
    for (int i = 0; i < size; i++)                                                 \
    {                                                                              \
        if (gold_arr[i] != act_arr[i])                                             \
        {                                                                          \
            pass = 0;                                                              \
            break;                                                                 \
        }                                                                          \
    }                                                                              \
    speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0; \
                                                                                   \
    printf("Test %-2d (N=%3d): %s | Gold: %5u, Vec: %5u | Speedup: %2d.%02dx\r\n", \
           test_num, size, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup / 100, speedup % 100);

    printf("Starting vpu_index Performance Tests:\r\n");
    void *B_ptr, *C_ptr;

    srand(0xdeadbeef);
    uint32_t B[N], C[N], goldenN[N], actualN[N];
    for (int i = 0; i < N; i++)
    {
        B[i] = rand();
        C[i] = rand();
    }
    B_ptr = B;
    C_ptr = C;
    RUN_TEST(1, N, index_golden32, index_vec32, goldenN, actualN);

    srand(0xcafebabe);
    uint32_t D[M], E[M], goldenM[M], actualM[M];
    for (int i = 0; i < M; i++)
    {
        D[i] = rand();
        E[i] = rand();
    }
    B_ptr = D;
    C_ptr = E;
    RUN_TEST(2, M, index_golden32, index_vec32, goldenM, actualM);

    srand(0x1234567);
    uint32_t F[O], G[O], goldenO[O], actualO[O];
    for (int i = 0; i < O; i++)
    {
        F[i] = rand();
        G[i] = rand();
    }
    B_ptr = F;
    C_ptr = G;
    RUN_TEST(3, O, index_golden32, index_vec32, goldenO, actualO);

    srand(0xdead);
    uint16_t H[N], J[N], golden4[N], actual4[N];
    for (int i = 0; i < N; i++)
    {
        H[i] = rand();
        J[i] = rand();
    }
    B_ptr = H;
    C_ptr = J;
    RUN_TEST(4, N, index_golden16, index_vec16, golden4, actual4);

    srand(0xcafe);
    uint16_t K[M], L[M], golden5[M], actual5[M];
    for (int i = 0; i < M; i++)
    {
        K[i] = rand();
        L[i] = rand();
    }
    B_ptr = K;
    C_ptr = L;
    RUN_TEST(5, M, index_golden16, index_vec16, golden5, actual5);

    srand(0x1234);
    uint16_t AA[O], BB[O], golden6[O], actual6[O];
    for (int i = 0; i < O; i++)
    {
        AA[i] = rand();
        BB[i] = rand();
    }
    B_ptr = AA;
    C_ptr = BB;
    RUN_TEST(6, O, index_golden16, index_vec16, golden6, actual6);

    srand(0xde);
    uint8_t U[N], V[N], golden7[N], actual7[N];
    for (int i = 0; i < N; i++)
    {
        U[i] = rand();
        V[i] = rand();
    }
    B_ptr = U;
    C_ptr = V;
    RUN_TEST(7, N, index_golden8, index_vec8, golden7, actual7);

    srand(0xca);
    uint8_t W[M], X[M], golden8[M], actual8[M];
    for (int i = 0; i < M; i++)
    {
        W[i] = rand();
        X[i] = rand();
    }
    B_ptr = W;
    C_ptr = X;
    RUN_TEST(8, M, index_golden8, index_vec8, golden8, actual8);

    srand(0x12);
    uint8_t Y[O], Z[O], golden9[O], actual9[O];
    for (int i = 0; i < O; i++)
    {
        Y[i] = rand();
        Z[i] = rand();
    }
    B_ptr = Y;
    C_ptr = Z;
    RUN_TEST(9, O, index_golden8, index_vec8, golden9, actual9);

    return 0;
}