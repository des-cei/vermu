// common.h

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

static inline int safe_vmax(int bits, int a) {
    int64_t lim = ((int64_t)1 << (bits - 1)) - 1;
    return (int)(lim / ((a < 0 ? -a : a) + 1));
}

void gen_rand_1d_int32(int32_t *ar, int n, int vmax) {
    for (int i = 0; i < n; ++i)
        ar[i] = (int32_t)(rand() % (2 * vmax + 1) - vmax);
}

void gen_rand_1d_int16(int16_t *ar, int n, int vmax) {
    for (int i = 0; i < n; ++i)
        ar[i] = (int16_t)(rand() % (2 * vmax + 1) - vmax);
}

void gen_rand_1d_int8(int8_t *ar, int n, int vmax) {
    for (int i = 0; i < n; ++i)
        ar[i] = (int8_t)(rand() % (2 * vmax + 1) - vmax);
}
