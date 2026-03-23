// -- Checking --
int verify_results_int32(int n, int32_t *golden, int32_t *vector) {
    int errors = 0;
    for (int i = 0; i < n; i++) {
        if (golden[i] != vector[i]) {
            errors++;
        }
    }
    return errors;
}

int verify_results_int16(int n, int16_t *golden, int16_t *vector) {
    int errors = 0;
    for (int i = 0; i < n; i++) {
        if (golden[i] != vector[i]) {
            errors++;
        }
    }
    return errors;
}

int verify_results_int8(int n, int8_t *golden, int8_t *vector) {
    int errors = 0;
    for (int i = 0; i < n; i++) {
        if (golden[i] != vector[i]) {
            errors++;
        }
    }
    return errors;
}
