// common.h
// common utilities for the test code under exmaples/

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
int compare_int32_vectors(int32_t *a, int32_t *b, size_t length)
{
    for (int i = 0; i < length; i++) {
        if (a[i] != b[i]) {
            return 0;   // mismatch
        }
    }
    return 1;           // identical
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
int compare_int16_vectors(int16_t *a, int16_t *b, size_t length)
{
    for (int i = 0; i < length; i++) {
        if (a[i] != b[i]) {
            return 0;   // mismatch
        }
    }
    return 1;           // identical
}

__attribute__((optimize("O3", "noinline", "no-tree-vectorize")))
int compare_int8_vectors(int8_t *a, int8_t *b, size_t length)
{
    for (int i = 0; i < length; i++) {
        if (a[i] != b[i]) {
            return 0;   // mismatch
        }
    }
    return 1;           // identical
}
