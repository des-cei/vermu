#include "csr.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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
  uint16_t idx = 0; 
  for (int i = 0; i < n; ++i) { 
    a[i] = b[i] + idx * c[i]; 
    idx++;
  }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden8(uint8_t *a, uint8_t *b, uint8_t *c, int n) {
  uint8_t idx = 0; 
  for (int i = 0; i < n; ++i) { 
    a[i] = b[i] + idx * c[i];
    idx++;
  }

}

// -------------------------------------------------------------------------
// 3. Vector Functions (Auto-Vectorization) 
// -------------------------------------------------------------------------
__attribute__((optimize("O3")))
void index_vec32(uint32_t *__restrict a, uint32_t *__restrict b, uint32_t *c, int n) {
  for (int i = 0; i < n; ++i) { a[i] = b[i] + i * c[i]; }
}

__attribute__((optimize("O3")))
void index_vec16(uint16_t *__restrict a, uint16_t *__restrict b, uint16_t *c, int n) {
  uint16_t idx = 0; 
  for (int i = 0; i < n; ++i) {
      a[i] = b[i] + idx * c[i];
      idx++;
  }
}

__attribute__((optimize("O3")))
void index_vec8(uint8_t *__restrict a, uint8_t *__restrict b, uint8_t *c, int n) {
  uint8_t idx = 0; 
  for (int i = 0; i < n; ++i) { 
    a[i] = b[i] + idx * c[i];
    idx++;
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
    /* Verify Loop - CONST_N ensures strict scalar code (no vlenb) */ \
    int pass = 1; \
    for (int i = 0; i < CONST_N; i++) { \
        if (golden[i] != actual[i]) { pass = 0; break; } \
    } \
    \
    int speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0; \
    printf("vec" #NAME_SUFFIX " (N=%4d): %s | Golden: %d, Vector: %d | Speedup: %d.%02dx\r\n", \
            CONST_N, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup / 100, speedup % 100); \
  } while(0)

#define DEFINE_TEST_SUITE(CONST_N) \
__attribute__((optimize("O1"))) \
void run_tests_##CONST_N(void) { \
    printf("--- Testing Size: %d ---\r\n", CONST_N); \
    TEST_BODY(uint32_t, 32, index_golden32, index_vec32, CONST_N); \
    TEST_BODY(uint16_t, 16, index_golden16, index_vec16, CONST_N); \
    TEST_BODY(uint8_t,   8, index_golden8,  index_vec8,  CONST_N); \
    printf("\r\n"); \
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
  printf("Starting Vector Index Tests (Auto-Vectorization - Fixed N)...\r\n");
  printf("Format: [Golden Cycles], [HW Cycles]\r\n\n");

  srand(0xdeadbeef);

  // Call the specialized functions
  run_tests_64();
  run_tests_128();
  run_tests_256();
  run_tests_512();
  run_tests_1024();

  printf("All tests completed.\r\n");
  return 0;
}