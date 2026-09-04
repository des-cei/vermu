// Copyright 2026 CEIMM-UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Ane Corral (ane.corral@upm.es)
//
// Test application to check control unit's functionality when including CSRs
#include <stdio.h>
#include <stdint.h>

volatile uint8_t  mem8[64]  = {0};

// int main(void)
// {

//     asm volatile("vsetivli t0, 8, e16, m1, ta, ma");

//     asm volatile("vadd.vi v1, v0, 1" ::: "v1");
    
//     asm volatile("vadd.vv v10, v1, v1");

//     asm volatile ("vle16.v  v0, (%0)" :: "r"(mem8));

//     asm volatile("vxor.vv v19, v0, v2");

//     asm volatile("vmaxu.vv v29, v5, v2");

//     asm volatile("vsetivli t0, 4, e16, m1, ta, ma");

//     return 0;
// }


/*
 * ZVE32X Vector CSR test
 *
 * Tests:
 *   - vsetvli
 *   - vsetivli
 *   - vsetvl
 *   - vl
 *   - vtype
 *   - vlenb
 *
 * Expected implementation:
 *   ELEN = 32
 *   SEW  = {8,16,32}
 *   LMUL = 1
 */

/* ------------------------------------------------------------
 * CSR read helpers
 * ------------------------------------------------------------ */

static inline uint32_t read_vl(void)
{
    uint32_t value;

    asm volatile (
        "csrr %0, vl"
        : "=r"(value)
        :
        : "memory"
    );

    return value;
}

static inline uint32_t read_vtype(void)
{
    uint32_t value;

    asm volatile (
        "csrr %0, vtype"
        : "=r"(value)
        :
        : "memory"
    );

    return value;
}

static inline uint32_t read_vlenb(void)
{
    uint32_t value;

    asm volatile (
        "csrr %0, vlenb"
        : "=r"(value)
        :
        : "memory"
    );

    return value;
}

// ------------------------------------------------------------
// vsetvli
//
// rd = returned vl
// AVL comes from a general-purpose register.
// ------------------------------------------------------------ 

static inline uint32_t test_vsetvli(uint32_t avl)
{
    uint32_t new_vl;

    asm volatile (
        "vsetvli %0, %1, e8, m1, ta, ma"
        : "=r"(new_vl)
        : "r"(avl)
        : "memory"
    );

    return new_vl;
}

static inline uint32_t test_vsetvli_e16(uint32_t avl)
{
    uint32_t new_vl;

    asm volatile (
        "vsetvli %0, %1, e16, m1, ta, ma"
        : "=r"(new_vl)
        : "r"(avl)
        : "memory"
    );

    return new_vl;
}

static inline uint32_t test_vsetvli_e32(uint32_t avl)
{
    uint32_t new_vl;

    asm volatile (
        "vsetvli %0, %1, e32, m1, ta, ma"
        : "=r"(new_vl)
        : "r"(avl)
        : "memory"
    );

    return new_vl;
}

// ------------------------------------------------------------
// vsetivli
// 
// AVL is a 5-bit immediate: 0..31
// ------------------------------------------------------------ 

static inline uint32_t test_vsetivli(uint32_t *new_vl)
{
    asm volatile (
        "vsetivli %0, 8, e16, m1, ta, ma"
        : "=r"(*new_vl)
        :
        : "memory"
    );

    return *new_vl;
}

/* ------------------------------------------------------------
 * vsetvl
 *
 * rs1 = AVL
 * rs2 = vtype value
 *
 * For RV32:
 *
 *   bit 7     vma
 *   bit 6     vta
 *   bits 5:3  vsew
 *   bits 2:0  vlmul
 *
 * e8  m1 ta ma = 0b11000000 = 0xC0
 * e16 m1 ta ma = 0b11001000 = 0xC8
 * e32 m1 ta ma = 0b11010000 = 0xD0
 * ------------------------------------------------------------ */

static inline uint32_t test_vsetvl(uint32_t avl, uint32_t vtype)
{
    uint32_t new_vl;

    asm volatile (
        "vsetvl %0, %1, %2"
        : "=r"(new_vl)
        : "r"(avl), "r"(vtype)
        : "memory"
    );

    return new_vl;
}

/* ------------------------------------------------------------
 * Print vector CSR state
 * ------------------------------------------------------------ */

static void print_vector_state(const char *name)
{
    uint32_t vl    = read_vl();
    uint32_t vtype = read_vtype();
    uint32_t vlenb = read_vlenb();

    printf("\n%s\n", name);
    printf("  vl    = %u (0x%08x)\n", vl, vl);
    printf("  vtype = 0x%08x\n", vtype);
    printf("  vlenb = %u\n", vlenb);

    printf("  vill  = %u\n", (vtype >> 31) & 1);
    printf("  vma   = %u\n", (vtype >> 7) & 1);
    printf("  vta   = %u\n", (vtype >> 6) & 1);
    printf("  vsew  = %u\n", (vtype >> 3) & 0x7);
    printf("  vlmul = %u\n", vtype & 0x7);
}

//------------------------------------------------------------
// Main test
// ------------------------------------------------------------ 

int main(void)
{
    uint32_t rd_vl;

    printf("\n");
    printf("=====================================\n");
    printf("     ZVE32X Vector CSR Test\n");
    printf("=====================================\n");

    print_vector_state("Initial vector state");

    /* --------------------------------------------------------
     * Read vlenb
     *
     * For example:
     *   VLEN=128 -> vlenb=16
     *   VLEN=256 -> vlenb=32
     * -------------------------------------------------------- */

    printf("\nExpected vlenb = VLEN / 8\n");

    /* --------------------------------------------------------
     * vsetivli
     *
     * AVL = 8
     * SEW = 16
     * LMUL = 1
     * TA/MA
     * -------------------------------------------------------- */

    rd_vl = test_vsetivli(&rd_vl);

    printf("\n-------------------------------------\n");
    printf("vsetivli t0, 8, e16, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetivli");

    /*
     * rd_vl and CSR vl should contain the same value.
     */

    // if (rd_vl == read_vl())
    //     printf("PASS: rd == vl\n");
    // else
    //     printf("FAIL: rd != vl\n");


    // vsetvli with small AVL

    rd_vl = test_vsetvli(3);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 3, e8, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetvli AVL=3");

    // if (read_vl() == 3)
    //     printf("PASS: vl == 3\n");
    // else
    //     printf("FAIL: vl != 3\n");


    //  vsetvli with AVL smaller than VLMAX

    rd_vl = test_vsetvli_e16(5);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 5, e16, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetvli AVL=5");


    /* --------------------------------------------------------
     * vsetvli with AVL larger than VLMAX
     *
     * This is particularly important.
     *
     * The hardware does NOT simply set vl = AVL.
     * It computes vl according to VLMAX and the AVL rules.
     * -------------------------------------------------------- */

    rd_vl = test_vsetvli_e32(100);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 100, e32, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetvli AVL=100");


    /* --------------------------------------------------------
     * vsetivli boundary tests
     *
     * Immediate AVL can only be 0..31.
     * -------------------------------------------------------- */

    asm volatile (
        "vsetivli %0, 1, e8, m1, ta, ma"
        : "=r"(rd_vl)
        :
        : "memory"
    );

    printf("\n-------------------------------------\n");
    printf("vsetivli t0, 1, e8, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);
    print_vector_state("After vsetivli AVL=1");


    asm volatile (
        "vsetivli %0, 31, e8, m1, ta, ma"
        : "=r"(rd_vl)
        :
        : "memory"
    );

    printf("\n-------------------------------------\n");
    printf("vsetivli t0, 31, e8, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);
    print_vector_state("After vsetivli AVL=31");


    /* --------------------------------------------------------
     * vsetvl
     *
     * Explicitly construct vtype.
     *
     * e8  m1 ta ma = 0xC0
     * e16 m1 ta ma = 0xC8
     * e32 m1 ta ma = 0xD0
     * -------------------------------------------------------- */

    rd_vl = test_vsetvl(7, 0xC8);

    printf("\n-------------------------------------\n");
    printf("vsetvl t0, a0, a1\n");
    printf("AVL=7, vtype=0xC8 (e16,m1,ta,ma)\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetvl e16");


    /* --------------------------------------------------------
     * vsetvl -> e32
     * -------------------------------------------------------- */

    rd_vl = test_vsetvl(20, 0xD0);

    printf("\n-------------------------------------\n");
    printf("vsetvl t0, a0, a1\n");
    printf("AVL=20, vtype=0xD0 (e32,m1,ta,ma)\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);

    print_vector_state("After vsetvl e32");


    //--------------------------------------------------------
    // Test changing SEW with the same AVL
    //-------------------------------------------------------- 

    rd_vl = test_vsetvli(20);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 20, e8, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);
    print_vector_state("e8, AVL=20");

    rd_vl = test_vsetvli_e16(20);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 20, e16, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);
    print_vector_state("e16, AVL=20");

    rd_vl = test_vsetvli_e32(20);

    printf("\n-------------------------------------\n");
    printf("vsetvli t0, 20, e32, m1, ta, ma\n");
    printf("-------------------------------------\n");

    printf("rd = %u\n", rd_vl);
    print_vector_state("e32, AVL=20");


    printf("\n=====================================\n");
    printf("             TEST END\n");
    printf("=====================================\n");

    return 0;
}
