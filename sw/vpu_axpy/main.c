#include "csr.h"
#include "common.h"
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

#define N 32
#define M 23
#define O 41

#define SCALAR_A_INT32 4
#define SCALAR_A_INT16 3
#define SCALAR_A_INT8 6

/* Input vectors */
static const int32_t input_int32[N] = {
    0xDEADBEEF, 0xCAFEBABE, 0xBAADF00D, 0xFEEDFACE,
    0x12345678, 0x87654321, 0x0F0F0F0F, 0xF0F0F0F0,
    0xAAAAAAAA, 0x55555555, 0x01010101, 0x10101010,
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x00000000, 0x00000001, 0xFFFFFFFF, 0x7FFFFFFF,
    0x80000000, 0x80000001, 0x7FFFFFFE, 0x0000FFFF,
    0xFFFF0000, 0x00FF00FF, 0xFF00FF00, 0x13579BDF,
    0x2468ACE0, 0xAAAAAAAA, 0x55555555, 0x00000002};

static const int16_t input_int16[M] = {
    0xDEAD, 0xBEEF, 0xCAFE, 0xBABE, 0xF00D, 0xFACE,
    0x1234, 0x8765, 0xAAAA, 0x5555, 0x0F0F, 0xF0F0,
    0x0000, 0x0001, 0xFFFF, 0x7FFF, 0x8000, 0x8001,
    0x7FFE, 0x00FF, 0xFF00, 0x1357, 0x2468};

static const int8_t input_int8[O] = {
    0xAD, 0xDE, 0xEF, 0xBE, 0xFE, 0xCA, 0xBE, 0xBA,
    0xAD, 0xBA, 0x0D, 0xF0, 0xED, 0xFE, 0xCE, 0xFA,
    0x34, 0x12, 0x78, 0x56, 0xBC, 0x9A, 0xF0, 0xDE,
    0x55, 0xAA, 0x0F, 0xF0, 0x01, 0x00, 0x7F, 0xFF,
    0x81, 0x80, 0x13, 0x7E, 0x9B, 0x57, 0x24, 0xDF,
    0x42};

/* Output vectors */
static int32_t output_golden_int32[N];
static int32_t output_vector_int32[N];
static int16_t output_golden_int16[M];
static int16_t output_vector_int16[M];
static int8_t output_golden_int8[O];
static int8_t output_vector_int8[O];

/* Golden functions */
__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void saxpy_golden_int32(size_t n, int32_t a, const int32_t *x, int32_t *y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void saxpy_golden_int16(size_t n, int16_t a, const int16_t *x, int16_t *y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) void saxpy_golden_int8(size_t n, int8_t a, const int8_t *x, int8_t *y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

/* Hardware/autovec functions */
__attribute__((optimize("O3"))) void saxpy_vec_int32(size_t n, int32_t a, const int32_t *__restrict x, int32_t *__restrict y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3"))) void saxpy_vec_int16(size_t n, int16_t a, const int16_t *__restrict x, int16_t *__restrict y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3"))) void saxpy_vec_int8(size_t n, int8_t a, const int8_t *__restrict x, int8_t *__restrict y)
{
    for (size_t i = 0; i < n; i++)
    {
        y[i] = a * x[i] + y[i];
    }
}

int main(void)
{
    unsigned int cycles_golden, cycles_vec;
    int speedup;

#define INIT_OUTPUTS(size, input_buf, gold_buf, vec_buf) \
    do                                                   \
    {                                                    \
        for (int i = 0; i < (size); i++)                 \
        {                                                \
            (gold_buf)[i] = (input_buf)[i];              \
            (vec_buf)[i] = (input_buf)[i];               \
        }                                                \
    } while (0)

#define RUN_TEST_SAXPY(test_num, size, scalar_a, golden_fn, vec_fn, input_buf, gold_buf, vec_buf, verify_fn) \
    do                                                                                                       \
    {                                                                                                        \
        CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                                          \
        CSR_WRITE(CSR_REG_MCYCLE, 0);                                                                        \
        golden_fn((size), (scalar_a), (input_buf), (gold_buf));                                              \
        CSR_READ(CSR_REG_MCYCLE, &cycles_golden);                                                            \
        CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);                                                          \
        CSR_WRITE(CSR_REG_MCYCLE, 0);                                                                        \
        vec_fn((size), (scalar_a), (input_buf), (vec_buf));                                                  \
        CSR_READ(CSR_REG_MCYCLE, &cycles_vec);                                                               \
        int pass = (verify_fn((size), (gold_buf), (vec_buf)) == 0);                                          \
        speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0;                       \
        printf("Test %-2d (N=%3d): %s | Gold: %5u, Vec: %5u | Speedup: %2d.%02dx\r\n",                       \
               (test_num), (size), pass ? "PASS" : "FAIL",                                                   \
               cycles_golden, cycles_vec, speedup / 100, speedup % 100);                                     \
    } while (0)

    printf("Starting vpu_saxpy Performance Tests:\r\n");

    INIT_OUTPUTS(N, input_int32, output_golden_int32, output_vector_int32);
    RUN_TEST_SAXPY(1, N, SCALAR_A_INT32, saxpy_golden_int32, saxpy_vec_int32,
                   input_int32, output_golden_int32, output_vector_int32,
                   verify_results_int32);

    INIT_OUTPUTS(M, input_int16, output_golden_int16, output_vector_int16);
    RUN_TEST_SAXPY(2, M, SCALAR_A_INT16, saxpy_golden_int16, saxpy_vec_int16,
                   input_int16, output_golden_int16, output_vector_int16,
                   verify_results_int16);

    INIT_OUTPUTS(O, input_int8, output_golden_int8, output_vector_int8);
    RUN_TEST_SAXPY(3, O, SCALAR_A_INT8, saxpy_golden_int8, saxpy_vec_int8,
                   input_int8, output_golden_int8, output_vector_int8,
                   verify_results_int8);

    return 0;
}
