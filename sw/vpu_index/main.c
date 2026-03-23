#include "csr.h"
#include <riscv_vector.h>
#include <stdint.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Golden Functions
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden32(uint32_t *a, uint32_t *b, uint32_t *c, int n) {
  for (int i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden16(uint16_t *a, uint16_t *b, uint16_t *c, int n) {
  for (int i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void index_golden8(uint8_t *a, uint8_t *b, uint8_t *c, int n) {
  for (int i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}


// Vector Functions
__attribute__((optimize("O3")))
void index_vec32(uint32_t *__restrict a, uint32_t *__restrict b, uint32_t *c, int n) { 
  for (int i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}

__attribute__((optimize("O3")))
void index_vec16(uint16_t *__restrict a, uint16_t *__restrict b, uint16_t *c, uint16_t n) {
  for (uint16_t i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}

__attribute__((optimize("O3")))
void index_vec8(uint8_t *__restrict a, uint8_t *__restrict b, uint8_t *c, uint8_t n) { 
  for (uint8_t i = 0; i < n; ++i) {
    a[i] = b[i] + i * c[i];
  }
}


int main() {
  const int N = 31;
  const int M = 62;
  const int O = 93;

  unsigned int cycles;

  printf("Golden, HW:\r\n");
  
  // TEST 1

  const uint32_t seed = 0xdeadbeef;
  srand(seed);


  uint32_t B[N], C[N];

  for(int i=0; i<N; i++) { B[i] = rand(); C[i] = rand(); } 

  uint32_t goldenN[N], actualN[N];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden32(goldenN, B, C, N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec32(actualN, B, C, N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  int pass = 1;
  for(int i=0; i<N; i++) {
      if (goldenN[i] != actualN[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 1" : "fail 1");

  // TEST 2
  const uint32_t seed2 = 0xcafebabe;
  srand(seed2);


  uint32_t D[M], E[M];

  for(int i=0; i<M; i++) { D[i] = rand(); E[i] = rand(); } 

  uint32_t goldenM[M], actualM[M];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden32(goldenM, D, E, M);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec32(actualM, D, E, M);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for(int i=0; i<M; i++) {
      if (goldenM[i] != actualM[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 2" : "fail 2");

  // TEST 3
  const uint32_t seed3 = 0x1234567;
  srand(seed3);


  uint32_t F[O], G[O];

  for(int i=0; i<O; i++) { F[i] = rand(); G[i] = rand(); } 

  uint32_t goldenO[O], actualO[O];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden32(goldenO, F, G, O);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec32(actualO, F, G, O);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for(int i=0; i<O; i++) {
      if (goldenO[i] != actualO[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 3" : "fail 3");

  
  // TEST 4

  const uint16_t seed4 = 0xdead;
  srand(seed4);


  uint16_t H[N], J[N];

  for(int i=0; i<N; i++) { H[i] = rand(); J[i] = rand(); } 

  uint16_t golden4[N], actual4[N];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden16(golden4, H, J, N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec16(actual4, H, J, (uint16_t)N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for(int i=0; i<N; i++) {
      if (golden4[i] != actual4[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 4" : "fail 4");

  // TEST 5

  const uint16_t seed5 = 0xcafe;
  srand(seed5);


  uint16_t K[M], L[M];

  for(int i=0; i<M; i++) { K[i] = rand(); L[i] = rand(); } 

  uint16_t golden5[M], actual5[M];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden16(golden5, K, L, M);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec16(actual5, K, L, (uint16_t)M);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for(int i=0; i<M; i++) {
      if (golden5[i] != actual5[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 5" : "fail 5");

  // TEST 6

  const uint16_t seed6 = 0x1234;
  srand(seed6);


  uint16_t AA[O], BB[O];

  for(int i=0; i<O; i++) { AA[i] = rand(); BB[i] = rand(); } 

  uint16_t golden6[O], actual6[O];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden16(golden6, AA, BB, O);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec16(actual6, AA, BB, (uint16_t)O);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for(int i=0; i<O; i++) {
      if (golden6[i] != actual6[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 6" : "fail 6");

  
  // TEST 7 (uint8, N)
  
  const uint8_t seed7 = 0xde;
  srand(seed7);

  uint8_t U[N], V[N];
  for (int i = 0; i < N; i++) { U[i] = rand(); V[i] = rand(); }

  uint8_t golden7[N], actual7[N];

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_golden8(golden7, U, V, N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d, ", cycles);

  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1);
  CSR_WRITE(CSR_REG_MCYCLE, 0);
  index_vec8(actual7, U, V, (uint8_t)N);
  CSR_READ(CSR_REG_MCYCLE, &cycles);
  printf("%d \r\n", cycles);

  pass = 1;
  for (int i = 0; i < N; i++) {
    if (golden7[i] != actual7[i]) { pass = 0; break; }
  }
  puts(pass ? "pass 7" : "fail 7");

}