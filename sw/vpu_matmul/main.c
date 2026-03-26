#include "csr.h"
#include "common.h"

    int32_t A[64] = {
        0xDEADBEEF, 0xCAFEBABE, 0xFEEDFACE, 0xBAADF00D, 
        0xDEADC0DE, 0x00C0FFEE, 0x8BADF00D, 0xD15EA5E5,
        // Row 1
        0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555, 
        0xCCCCCCCC, 0x33333333, 0xF0F0F0F0, 0x0F0F0F0F,
        // Row 2: 
        0xACCE55ED, 0xBAAAAAAD, 0xFEE1DEAD, 0xDEFEC8ED, 
        0xB01DFACE, 0xCA11AB1E, 0x0FF1C1A1, 0x1CEB00DA, 
        // Row 3: 
        0x00000001, 0x00000002, 0x00000004, 0x00000008, 
        0x00000010, 0x00000020, 0x00000040, 0x00000080,
        // Row 4: 
        0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210, 
        0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF,
        // Row 5: 
        0x0000BEEF, 0x0000CAFE, 0x0000F00D, 0x0000C0CE, 
        0xBADCAFFE, 0xC000C00A, 0xBAD00000, 0xFEED0000,
        // Row 6: 
        0xDEAD0001, 0xDEAD0002, 0xDEAD0003, 0xDEAD0004, 
        0xDEAD0005, 0xDEAD0006, 0xDEAD0007, 0xDEAD0008,
        // Row 7: 
        0xBEEF0001, 0xBEEF0002, 0xBEEF0003, 0xBEEF0004, 
        0xBEEF0005, 0xBEEF0006, 0xBEEF0007, 0xBEEF9999 
    };


    int32_t B[64] = {
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1,
      1,1,1,1,1,1,1,1
    };

    int16_t G[56] = {
        
        0xBEEF, 0xDEAD, 0xBABE, 0xCAFE,
        0xFACE, 0xFEED, 0xF00D, 0xBAAD, 

        0xC0DE, 0xDEAD, 0xFFEE, 0x00C0F, 
        0xF00D, 0x8BAD,  0xA5E5,0xD15E,
        
        // Row 1: Alternating Bit Patterns
        0x0000, 0xFFFF, 0xAAAA, 0x5555, 
        0xCCCC, 0x3333, 0xF0F0, 0x0F0F,
        
        // Row 2: Leetspeak (truncated)
        0x55ED, 0xAAAD, 0xDEAD, 0xC8ED, 
        0xFACE, 0xAB1E, 0xC1A1, 0x00DA, 
        
        // Row 3: Powers of 2
        0x0001, 0x0002, 0x0004, 0x0008, 
        0x0010, 0x0020, 0x0040, 0x0080,
        
        // Row 4: Sequences
        0x4567, 0xCDEF, 0xBA98, 0x3210, 
        0x2233, 0x6677, 0xAABB, 0xEEFF,
        
        // Row 5: Sparse Data
        0xBEEF, 0xCAFE, 0xF00D, 0xC0CE, 
        0xAFFE, 0xC00A, 0x0000, 0x0000,
        
        // Row 6: Counters
        0x0001, 0x0002, 0x0003, 0x0004, 
        0x0005, 0x0006, 0x0007, 0x0008
    };

    int16_t H[56] = {
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1
    };

    int8_t C[64] = {
        0xEF, 0xBE, 0xAD, 0xDE, 0xBE, 0xBA, 0xFE, 0xCA, 
        0x55, 0xAA, 0xFF, 0x00, 0x0F, 0xF0, 0x33, 0xCC, 
        0xAD, 0xBE, 0xD0, 0xFA, 0xBA, 0xFE, 0x0F, 0x1D,  
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,  
        0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,  
        0x0D, 0xF0, 0xDE, 0xC0, 0xBE, 0xBA, 0xDA, 0xDA, 
        0x7F, 0x80, 0xFF, 0x00, 0x01, 0x7E, 0x81, 0x42,       
        0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7 
    };


    int8_t D[64] = {
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1
    };

    int8_t E[56] = {
        0xEF, 0xBE, 0xAD, 0xDE, 0xBE, 0xBA, 0xFE, 
        0x55, 0xAA, 0xFF, 0x00, 0x0F, 0xF0, 0x33, 
        0xAD, 0xBE, 0xD0, 0xFA, 0xBA, 0xFE, 0x0F, 
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 
        0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 
        0x0D, 0xF0, 0xDE, 0xC0, 0xBE, 0xBA, 0xDA, 
        0x7F, 0x80, 0xFF, 0x00, 0x01, 0x7E, 0x81,
        0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7
    };

    int8_t F[56] = {
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1
    };

// A[n][o], B[o][m] --> C[n][m];
__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void matmul_golden_int32( int32_t *a,
                          int32_t *b,
                          int32_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int32_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;         
        }
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void matmul_golden_int16( int16_t *a,
                          int16_t *b,
                          int16_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int16_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;
        }
    }
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
void matmul_golden_int8( int8_t *a,
                         int8_t *b,
                         int8_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int8_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;
        }
    }
}

//-- Vector functions --
__attribute__((optimize("O3")))
void matmul_hw_int32( int32_t *a,
                int32_t *b,
                int32_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int32_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;
        }
    }
}

__attribute__((optimize("O3")))
void matmul_hw_int16( int16_t *a,
                int16_t *b,
                int16_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int16_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;
        }
    }
}

__attribute__((optimize("O3")))
void matmul_hw_int8( int8_t *a,
                int8_t *b,
                int8_t *c, size_t size_m, size_t size_n, size_t size_k)
{
    for (size_t m = 0; m < size_m; m++)
    {
        for (size_t n = 0; n < size_n; n++)
        {
            int8_t acc = 0;
            for (size_t k = 0; k < size_k; k++)
            {
                acc += a[m*size_k + k] * b[k*size_n + n];
            }
            c[m*size_n + n] = acc;
        }
    }
}


int32_t main() {
  size_t N = 8;
  size_t M = 8;
  size_t O = 8;

  unsigned int cycles_golden, cycles_vec;
  int speedup;
  int pass;

    #define RUN_TEST_MATMUL(test_num, a_mat, b_mat, size_n, size_m, size_o, size_output, golden_fn, vec_fn, gold_buf, vec_buf, cmp_fn) \
  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
  CSR_WRITE(CSR_REG_MCYCLE, 0); \
  golden_fn(a_mat, b_mat, gold_buf, size_n, size_m, size_o); \
  CSR_READ(CSR_REG_MCYCLE, &cycles_golden); \
  \
  CSR_CLEAR_BITS(CSR_REG_MCOUNTINHIBIT, 0x1); \
  CSR_WRITE(CSR_REG_MCYCLE, 0); \
  vec_fn(a_mat, b_mat, vec_buf, size_n, size_m, size_o); \
  CSR_READ(CSR_REG_MCYCLE, &cycles_vec); \
  pass = cmp_fn(gold_buf, vec_buf, size_output); \
  \
  speedup = (cycles_vec > 0) ? (int)((100.0f * cycles_golden) / cycles_vec) : 0; \
  printf("Test %-2d (N=%d,M=%d,O=%d): %s | Gold: %5u, Vec: %5u | Speedup: %2d.%02dx\r\n", \
      test_num, size_n, size_m, size_o, pass ? "PASS" : "FAIL", cycles_golden, cycles_vec, speedup / 100, speedup % 100);

  printf("Starting vpu_matmul Performance Tests:\r\n");

  // TEST 1: int32
  int32_t golden_int32[64];
  int32_t actual_int32[64];
    RUN_TEST_MATMUL(1, A, B, N, M, O, 64, matmul_golden_int32, matmul_hw_int32, golden_int32, actual_int32, compare_int32_vectors);

  // TEST 2: int16
  int16_t golden_int16[64];
  int16_t actual_int16[64];
    RUN_TEST_MATMUL(2, G, H, N, M, O, 64, matmul_golden_int16, matmul_hw_int16, golden_int16, actual_int16, compare_int16_vectors);

  // TEST 3: int8
  int8_t golden_int8[64];
  int8_t actual_int8[64];
    RUN_TEST_MATMUL(3, C, D, N, M, O, 64, matmul_golden_int8, matmul_hw_int8, golden_int8, actual_int8, compare_int8_vectors);

  // TEST 4: int8 with O=7
  O = 7;
    RUN_TEST_MATMUL(4, E, F, N, M, O, 64, matmul_golden_int8, matmul_hw_int8, golden_int8, actual_int8, compare_int8_vectors);

  return 0;
}
