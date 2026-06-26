#include "csr.h"
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include <riscv_vector.h>

#define N 32
#define M 23
#define O 41



int32_t input_int32_A[N] = {
    1, -2, 3, -4, 5, -6, 7, -8,
    9, -10, 11, -12, 13, -14, 15, -16,
    17, -18, 19, -20, 21, -22, 23, -24,
    25, -26, 27, -28, 29, -30, 31, -32
};


int32_t input_int32_B[M] = {
    0xDEADBEEF, 0xCAFEBABE, 0xBAADF00D, 0xFEEDFACE,
    0x12345678, 0x87654321, 0x0F0F0F0F, 0xF0F0F0F0,
    0xAAAAAAAA, 0x55555555, 0x01010101, 0x10101010,
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x00000000, 0x00000001, 0xFFFFFFFF, 0x7FFFFFFF,
    0x80000000, 0x80000001, 0x7FFFFFFE
};

int16_t input_int16[M] = {
    0xDEAD, 0xBEEF,
    0xCAFE, 0xBABE,    
    0xF00D, 0xFACE,     
    0x1234, 0x8765, 

    0xAAAA, 0x5555,     
    0x0F0F, 0xF0F0,     
    0x0000, 0x0001,     
    0xFFFF, 0x7FFF,

    0x8000, 0x8001,     
    0x7FFE, 0x00FF,    
    0xFF00, 0x1357,  
    0x2468      
};


int8_t input_int8[O] = {
    0xAD, 0xDE, 0xEF, 0xBE, 0xFE, 0xCA, 0xBE, 0xBA,
    0xAD, 0xBA, 0x0D, 0xF0, 0xED, 0xFE, 0xCE, 0xFA,
    0x34, 0x12, 0x78, 0x56, 0xBC, 0x9A, 0xDE, 0xF0,
    0x55, 0xAA, 0x0F, 0xF0, 0x01, 0x00, 0x7F, 0xFF,
    0x81, 0x80, 0x13, 0x7E, 0x9B, 0x57, 0x24, 0xDF,
    0x42
};


// --- Output Buffers ---
int32_t output_golden_int32_A[N];
int32_t output_int32_A[N];

int32_t output_golden_int32_B[M];
int32_t output_int32_B[M];

int16_t output_golden_int16[M];
int16_t output_int16[M];

int8_t output_golden_int8[O];
int8_t output_int8[O];



// --- Golden Functions ---
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void saxpy_golden_int32(size_t m, const int32_t a, const int32_t *x, int32_t *y)
{
    for (size_t i = 0; i < m; i++) {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void saxpy_golden_int16(size_t m, const int16_t a, const int16_t *x, int16_t *y)
{
    for (size_t i = 0; i < m; i++) {
        y[i] = a * x[i] + y[i];
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize"))) 
void saxpy_golden_int8(size_t m, const int8_t a, const int8_t *x, int8_t *y)
{
    for (size_t i = 0; i < m; i++) {
        y[i] = a * x[i] + y[i];
    }
}

// --- Vector Functions ---
void saxpy_vec_int32(size_t n, const int32_t a, const int32_t *x, int32_t *y)
{
    for (size_t vl; n > 0; n -= vl, x += vl, y += vl)
    {
        vl = __riscv_vsetvl_e32m1(n);

        vint32m1_t vx = __riscv_vle32_v_i32m1(x, vl);
        vint32m1_t vy = __riscv_vle32_v_i32m1(y, vl);

        // y = a * x + y
        vint32m1_t vres = __riscv_vmacc_vx_i32m1(vy, a, vx, vl); 

        __riscv_vse32_v_i32m1(y, vres, vl);
    }
}

void saxpy_vec_int16(size_t n, const int32_t a, const int16_t *x, int16_t *y)
{
    for (size_t vl; n > 0; n -= vl, x += vl, y += vl)
    {
        vl = __riscv_vsetvl_e16m1(n);

        vint16m1_t vx = __riscv_vle16_v_i16m1(x, vl);
        vint16m1_t vy = __riscv_vle16_v_i16m1(y, vl);

        // y = a * x + y
        vint16m1_t vres = __riscv_vmacc_vx_i16m1(vy, a, vx, vl); 

        __riscv_vse16_v_i16m1(y, vres, vl);
    }
}

void saxpy_vec_int8(size_t n, const int32_t a, const int8_t *x, int8_t *y)
{
    for (size_t vl; n > 0; n -= vl, x += vl, y += vl)
    {
        vl = __riscv_vsetvl_e8m1(n);

        vint8m1_t vx = __riscv_vle8_v_i8m1(x, vl);
        vint8m1_t vy = __riscv_vle8_v_i8m1(y, vl);

        // y = a * x + y
        vint8m1_t vres = __riscv_vmacc_vx_i8m1(vy, a, vx, vl); 

        __riscv_vse8_v_i8m1(y, vres, vl);
    }
}

__attribute__((optimize("O3", "no-tree-vectorize", "noinline")))
static int compare_int32_no_vec(const int32_t *gold, const int32_t *vec, int size)
{
    for (int i = 0; i < size; i++) {
        if (gold[i] != vec[i]) {
            return 0;
        }
    }
    return 1;
}

__attribute__((optimize("O3", "no-tree-vectorize", "noinline")))
static int compare_int16_no_vec(const int16_t *gold, const int16_t *vec, int size)
{
    for (int i = 0; i < size; i++) {
        if (gold[i] != vec[i]) {
            return 0;
        }
    }
    return 1;
}

__attribute__((optimize("O3", "no-tree-vectorize", "noinline")))
static int compare_int8_no_vec(const int8_t *gold, const int8_t *vec, int size)
{
    for (int i = 0; i < size; i++) {
        if (gold[i] != vec[i]) {
            return 0;
        }
    }
    return 1;
}

int main() {
  unsigned int cycles_golden, cycles_vec;
  int speedup;
  int pass;

    #define RUN_TEST_SAXPY(test_num, size, scalar_a, golden_fn, vec_fn, input_buf, gold_buf, vec_buf, cmp_fn) \
  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
  CSR_WRITE(CSR_REG_MCYCLE, 0); \
  golden_fn(size, scalar_a, input_buf, gold_buf); \
  CSR_READ(CSR_REG_MCYCLE, &cycles_golden); \
  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
  CSR_WRITE(CSR_REG_MCYCLE, 0); \
  vec_fn(size, scalar_a, input_buf, vec_buf); \
  CSR_READ(CSR_REG_MCYCLE, &cycles_vec); \
    pass = cmp_fn(gold_buf, vec_buf, size); \
  speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0; \
  printf("Test %-2d (N=%3d): %s | Gold: %5u, Vec: %5u | Speedup: %2d.%02dx\r\n", \
          test_num, size, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup / 100, speedup % 100);

  printf("Starting rvv_saxpy Performance Tests:\r\n");
  int32_t a = 4;

  // Test 1: int32
  for (int i = 0; i < N; i++) {
    output_golden_int32_A[i] = input_int32_A[i];
    output_int32_A[i] = input_int32_A[i];
  }
    RUN_TEST_SAXPY(1, N, a, saxpy_golden_int32, saxpy_vec_int32, input_int32_A, output_golden_int32_A, output_int32_A, compare_int32_no_vec);

  // Test 2: int16
  for (int i = 0; i < M; i++) {
    output_golden_int16[i] = input_int16[i];
    output_int16[i] = input_int16[i];
  }
    RUN_TEST_SAXPY(2, M, a, saxpy_golden_int16, saxpy_vec_int16, input_int16, output_golden_int16, output_int16, compare_int16_no_vec);

  // Test 3: int8
  for (int i = 0; i < O; i++) {
    output_golden_int8[i] = input_int8[i];
    output_int8[i] = input_int8[i];
  }
    RUN_TEST_SAXPY(3, O, a, saxpy_golden_int8, saxpy_vec_int8, input_int8, output_golden_int8, output_int8, compare_int8_no_vec);

  return 0;
}

