#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include "csr.h"
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

// Reads the RISC-V cycle counter (mcycle CSR)
static inline uint32_t get_cycles(void) {
    uint32_t cycles;
    asm volatile ("csrr %0, mcycle" : "=r"(cycles));
    return cycles;
}

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

void saxpy_vec_int8(size_t n, const int8_t a, const int8_t *x, int8_t *y)
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

int main() {

    uint32_t start_cycles, end_cycles;
    int total_errors = 0;
    
   printf("Golden, HW:\r\n");
    // Test 1: int 32
    int32_t a = 4;

    for (int i = 0; i < N; i++) {
        output_golden_int32_A[i] = input_int32_A[i];
        output_int32_A[i] = input_int32_A[i];
    }


    start_cycles = get_cycles();
    saxpy_golden_int32(N, a, input_int32_A, output_golden_int32_A);
    end_cycles = get_cycles();
    printf("%u, ", end_cycles - start_cycles);


    start_cycles = get_cycles();
    saxpy_vec_int32(N, a, input_int32_A, output_int32_A);
    end_cycles = get_cycles();
    printf("%u \r\n", end_cycles - start_cycles);

    int fails_t1 = 0;
    for (int i = 0; i < N; i++) {
        if (output_golden_int32_A[i] != output_int32_A[i]) {
            printf("FAIL at A %d : golden=%d, vec=%d\r\n",
                   i, output_golden_int32_A[i], output_int32_A[i]);
            fails_t1++;
        }
    }


    if (fails_t1 == 0) printf("PASS 1\r\n");
    else printf("\r\n  T1 F %d er\r\n", fails_t1);
    total_errors += fails_t1;

    //Test 2: int 16
    for (int i = 0; i < M; i++) {
        output_golden_int16[i] = input_int16[i];
        output_int16[i] = input_int16[i];
    }

    start_cycles = get_cycles();
    saxpy_golden_int16(M, a, input_int16, output_golden_int16);
    end_cycles = get_cycles();
    printf("%u, ", end_cycles - start_cycles);

    start_cycles = get_cycles();
    saxpy_vec_int16(M, a, input_int16, output_int16);
    end_cycles = get_cycles();
    printf("%u\r\n", end_cycles - start_cycles);

    int fails_t2 = 0;
    for (int i = 0; i < M; i++) {
        if (output_golden_int16[i] != output_int16[i]) {
            printf("\r\n  FAIL at idx %d : golden=%d, vec=%d",
                   i, output_golden_int16[i], output_int16[i]);
            fails_t2++;
        }
    }

    if (fails_t2 == 0) printf("PASS 2\r\n");
    else printf("\r\n  T2 %d errors\r\n", fails_t2);
    total_errors += fails_t2;


    // Test 3: int 8 
    for (int i = 0; i < O; i++) {
        output_golden_int8[i] = input_int8[i];
        output_int8[i] = input_int8[i];
    }

    start_cycles = get_cycles();
    saxpy_golden_int8(O, a, input_int8, output_golden_int8);
    end_cycles = get_cycles();
    printf("%u, ", end_cycles - start_cycles);

    start_cycles = get_cycles();
    saxpy_vec_int8(O, a, input_int8, output_int8);
    end_cycles = get_cycles();
    printf("%u \r\n", end_cycles - start_cycles);

    int fails_t3 = 0;
    for (int i = 0; i < O; i++) {
        if (output_golden_int8[i] != output_int8[i]) {
            printf("\r\n  FAIL at idx %d : golden=%d (0x%02X), vec=%d (0x%02X)",
                   i, output_golden_int8[i], (uint8_t)output_golden_int8[i], 
                      output_int8[i], (uint8_t)output_int8[i]);
            fails_t3++;
        }
    }

    if (fails_t3 == 0) printf("PASS 3\r\n");
    else printf("\r\n  T3 FAILED %d err\r\n", fails_t3);
    total_errors += fails_t3;

    // Final report
    if (total_errors == 0) {
        printf("\r\nALL PASSED.\r\n");
        return 0;
    } else {
        printf("\r\nFAILURES: %d\r\n", total_errors);
        return 1;
    }
}

