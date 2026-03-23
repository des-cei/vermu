#include "csr.h"
#include <riscv_vector.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h> 

#define MAX_N 1024

// -------------------------------------------------------------------------
// 1. Shared Global Memory 
// -------------------------------------------------------------------------
__attribute__((aligned(16))) uint32_t g_B[MAX_N];
__attribute__((aligned(16))) uint32_t g_C[MAX_N];
__attribute__((aligned(16))) uint32_t g_golden[MAX_N];
__attribute__((aligned(16))) uint32_t g_actual[MAX_N];

// -------------------------------------------------------------------------
// 2. Golden Functions 
// -------------------------------------------------------------------------
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden32(uint32_t *a, uint32_t *b, uint32_t *c, int n) {
  for (int i = 0; i < n; ++i) { a[i] = b[i] + i * c[i]; }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden16(uint16_t *a, uint16_t *b, uint16_t *c, int n) {
  for (int i = 0; i < n; ++i) { a[i] = b[i] + i * c[i]; }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden8(uint8_t *a, uint8_t *b, uint8_t *c, int n) {
  for (int i = 0; i < n; ++i) { a[i] = b[i] + i * c[i]; }
}

// -------------------------------------------------------------------------
// 3. Vector Functions (RVV Intrinsics) 
// -------------------------------------------------------------------------
void index_vec32(uint32_t *a, uint32_t *b, uint32_t *c, int n) {
  size_t vlmax = __riscv_vsetvlmax_e32m1();
  vuint32m1_t vec_i = __riscv_vid_v_u32m1(vlmax);
  
  for (size_t vl; n > 0; n -= vl, a += vl, b += vl, c += vl) {
    vl = __riscv_vsetvl_e32m1(n);
    vuint32m1_t vec_b = __riscv_vle32_v_u32m1(b, vl);
    vuint32m1_t vec_c = __riscv_vle32_v_u32m1(c, vl);
    vuint32m1_t vec_a = __riscv_vmacc_vv_u32m1(vec_b, vec_c, vec_i, vl);
    __riscv_vse32_v_u32m1(a, vec_a, vl);
    vec_i = __riscv_vadd_vx_u32m1(vec_i, vl, vl);
  }
}

void index_vec16(uint16_t *a, uint16_t *b, uint16_t *c, int n) {
  size_t vlmax = __riscv_vsetvlmax_e16m1();
  vuint16m1_t vec_i = __riscv_vid_v_u16m1(vlmax);
  
  for (size_t vl; n > 0; n -= vl, a += vl, b += vl, c += vl) {
    vl = __riscv_vsetvl_e16m1(n);
    vuint16m1_t vec_b = __riscv_vle16_v_u16m1(b, vl);
    vuint16m1_t vec_c = __riscv_vle16_v_u16m1(c, vl);
    vuint16m1_t vec_a = __riscv_vmacc_vv_u16m1(vec_b, vec_c, vec_i, vl);
    __riscv_vse16_v_u16m1(a, vec_a, vl);
    vec_i = __riscv_vadd_vx_u16m1(vec_i, vl, vl);
  }
}

void index_vec8(uint8_t *a, uint8_t *b, uint8_t *c, int n) {
  size_t vlmax = __riscv_vsetvlmax_e8m1();
  vuint8m1_t vec_i = __riscv_vid_v_u8m1(vlmax);

  for (size_t vl; n > 0; n -= vl, a += vl, b += vl, c += vl) {
    vl = __riscv_vsetvl_e8m1(n);
    vuint8m1_t vec_b = __riscv_vle8_v_u8m1(b, vl);
    vuint8m1_t vec_c = __riscv_vle8_v_u8m1(c, vl);
    vuint8m1_t vec_a = __riscv_vmacc_vv_u8m1(vec_b, vec_c, vec_i, vl);
    __riscv_vse8_v_u8m1(a, vec_a, vl);
    vec_i = __riscv_vadd_vx_u8m1(vec_i, vl, vl);
  }
}

// -------------------------------------------------------------------------
// 4. Test Generators (Macros)
// -------------------------------------------------------------------------

#define TEST_BODY(TYPE, NAME_SUFFIX, GOLDEN_FUNC, VEC_FUNC, CONST_N) \
  do { \
    /* Map local pointers to the global shared buffers */ \
    TYPE *B = (TYPE*)g_B; \
    TYPE *C = (TYPE*)g_C; \
    TYPE *golden = (TYPE*)g_golden; \
    TYPE *actual = (TYPE*)g_actual; \
    unsigned int cycles_golden, cycles_vec; \
    \
    /* Initialize Data (only up to CONST_N) */ \
    for (int i = 0; i < CONST_N; i++) { B[i] = (TYPE)rand(); C[i] = (TYPE)rand(); } \
    \
    /* Golden Run */ \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
    CSR_WRITE(CSR_REG_MCYCLE, 0); \
    GOLDEN_FUNC(golden, B, C, CONST_N); \
    CSR_READ(CSR_REG_MCYCLE, &cycles_golden); \
    \
    /* Vector Run */ \
    CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
    CSR_WRITE(CSR_REG_MCYCLE, 0); \
    VEC_FUNC(actual, B, C, CONST_N); \
    CSR_READ(CSR_REG_MCYCLE, &cycles_vec); \
    \
    /* Verify Loop - CONST_N ensures no vlenb generation */ \
    int pass = 1; \
    for (int i = 0; i < CONST_N; i++) { \
        if (golden[i] != actual[i]) { pass = 0; break; } \
    } \
    \
    float speedup = (float)cycles_golden / (float)(cycles_vec > 0 ? cycles_vec : 1); \
    printf("vec" #NAME_SUFFIX " (N=%4d): %s | Golden: %d, Vector: %d | Speedup: %.2fx\r\n", \
            CONST_N, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup); \
  } while(0)


/* * Function Generator: Attributes set to O1 to prevent loop versioning
 */
#define DEFINE_TEST_SUITE(CONST_N) \
__attribute__((optimize("O1"))) \
void run_tests_##CONST_N(void) { \
    TEST_BODY(uint32_t, 32, index_golden32, index_vec32, CONST_N); \
    TEST_BODY(uint16_t, 16, index_golden16, index_vec16, CONST_N); \
    TEST_BODY(uint8_t,   8, index_golden8,  index_vec8,  CONST_N); \
    printf("----------------------------------------------------------\r\n"); \
}

// -------------------------------------------------------------------------
// 5. Instantiate Tests
// -------------------------------------------------------------------------

DEFINE_TEST_SUITE(64)
DEFINE_TEST_SUITE(128)
DEFINE_TEST_SUITE(256)
DEFINE_TEST_SUITE(512)
DEFINE_TEST_SUITE(1024)

// -------------------------------------------------------------------------
// 6. Main
// -------------------------------------------------------------------------

int main() {
  printf("Starting RVV Index Tests (Shared RAM - Fixed N)...\r\n\n");
  srand(0xdeadbeef);

  run_tests_64();
  run_tests_128();
  run_tests_256();
  run_tests_512();
  run_tests_1024();

  printf("All tests completed.\r\n");
  return 0;
}