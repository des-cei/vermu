#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "common.h"
#include <riscv_vector.h>

  static inline uint32_t get_cycles(void) {
      uint32_t cycles;
      asm volatile ("csrr %0, mcycle" : "=r"(cycles));
      return cycles;
  }

// matrix multiplication (B is expected in transposed form)
// A[n][o], B[m][o] --> C[n][m];
void matmul_golden32(int32_t **a, int32_t **b_t, int32_t **c, int n, int m, int o) {
  for (int i = 0; i < n; ++i)
    for (int j = 0; j < m; ++j) {
      c[i][j] = 0;
      for (int k = 0; k < o; ++k)
        c[i][j] += a[i][k] * b_t[j][k];
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

int main() {
  const int N = 8;
  const int M = 8;
  const int O = 7;

  // Timer variables
  uint32_t start_cycles, end_cycles;
  printf("Golden, HW:\r\n");

  //T1 : sew 32
  uint32_t seed32 = 0xdeadbeef;
  srand(seed32);

  //data gen
  int32_t **A = alloc_array_2d_int32(N, O);
  int32_t **B = alloc_array_2d_int32(M, O); 
  gen_rand_2d_int32(A, N, O);
  gen_rand_2d_int32(B, M, O);


  // compute
  int32_t **golden32 = alloc_array_2d_int32(N, M);
  int32_t **actual32 = alloc_array_2d_int32(N, M);
  
  start_cycles = get_cycles();
  matmul_golden32(A, B, golden32, N, M, O);
  end_cycles = get_cycles();
  printf("%u, ", end_cycles - start_cycles);
  
  start_cycles = get_cycles();
  matmul32(A, B, actual32, N, M, O);
  end_cycles = get_cycles();
  printf("%u \r\n", end_cycles - start_cycles);

  puts(compare_2d_int32(golden32, actual32, N, M) ? "pass" : " T1 fail");

  //T2 : sew 16
  uint16_t seed16 = 0xbeef;
  srand(seed16);

  //data gen
  int16_t **C = alloc_array_2d_int16(N, O);
  int16_t **D = alloc_array_2d_int16(M, O); 
  gen_rand_2d_int16(C, N, O);
  gen_rand_2d_int16(D, M, O);


  // compute
  int16_t **golden16 = alloc_array_2d_int16(N, M);
  int16_t **actual16 = alloc_array_2d_int16(N, M);
 
  start_cycles = get_cycles();
  matmul_golden16(C, D, golden16, N, M, O);
  end_cycles = get_cycles();
  printf("%u, ", end_cycles - start_cycles);

  start_cycles = get_cycles();
  matmul16(C, D, actual16, N, M, O);
  end_cycles = get_cycles();
  printf("%u \r\n", end_cycles - start_cycles);

  // compare
  puts(compare_2d_int16(golden16, actual16, N, M) ? "pass" : " T2 fail");

  //T3 : sew 8
  uint8_t seed8 = 0xde;
  srand(seed8);

  //data gen
  int8_t **E = alloc_array_2d_int8(N, O);
  int8_t **F = alloc_array_2d_int8(M, O); 
  gen_rand_2d_int8(E, N, O);
  gen_rand_2d_int8(F, M, O);


  // compute
  int8_t **golden8 = alloc_array_2d_int8(N, M);
  int8_t **actual8 = alloc_array_2d_int8(N, M);

  start_cycles = get_cycles();
  matmul_golden8(E, F, golden8, N, M, O);
  end_cycles = get_cycles();
  printf("%u, ", end_cycles - start_cycles);

  start_cycles = get_cycles();
  matmul8(E, F, actual8, N, M, O);
  end_cycles = get_cycles();
  printf("%u \r\n", end_cycles - start_cycles);

  // compare
  puts(compare_2d_int8(golden8, actual8, N, M) ? "pass" : " T3 fail");
}
