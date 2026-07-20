// common.h

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void gen_rand_2d_int32(int32_t **ar, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            ar[i][j] = (int32_t)(rand() % 1000);
}

void gen_rand_2d_int16(int16_t **ar, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            ar[i][j] = (int16_t)rand() / (int16_t)RAND_MAX + (int16_t)(rand() % 1000);
}

void gen_rand_2d_int8(int8_t **ar, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            ar[i][j] = (int8_t)rand() / (int8_t)RAND_MAX + (int8_t)(rand() % 1000);
}

bool compare_2d_int32(int32_t **golden, int32_t **actual, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            if (golden[i][j] != actual[i][j])
                return false;
    return true;
}

bool compare_2d_int16(int16_t **golden, int16_t **actual, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            if (golden[i][j] != actual[i][j])
                return false;
    return true;
}

bool compare_2d_int8(int8_t **golden, int8_t **actual, int n, int m)
{
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < m; ++j)
            if (golden[i][j] != actual[i][j])
                return false;
    return true;
}

int32_t **alloc_array_2d_int32(int n, int m)
{
    int32_t **ret = (int32_t **)malloc(sizeof(int32_t *) * n);
    for (int i = 0; i < n; ++i)
    {
        ret[i] = (int32_t *)malloc(sizeof(int32_t) * m);
    }
    return ret;
}

int16_t **alloc_array_2d_int16(int n, int m)
{
    int16_t **ret = (int16_t **)malloc(sizeof(int16_t *) * n);
    for (int i = 0; i < n; ++i)
    {
        ret[i] = (int16_t *)malloc(sizeof(int16_t) * m);
    }
    return ret;
}

int8_t **alloc_array_2d_int8(int n, int m)
{
    int8_t **ret = (int8_t **)malloc(sizeof(int8_t *) * n);
    for (int i = 0; i < n; ++i)
    {
        ret[i] = (int8_t *)malloc(sizeof(int8_t) * m);
    }
    return ret;
}
