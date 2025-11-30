#include "my_functions.h"

int add(int a, int b) {
// MUTANT <START>
// Simulating the off-by-one error found in the NetLabel subsystem.
// The loop condition '<=' causes an iteration one step past the intended boundary,
// representing the logic flaw that led to system crashes in the kernel patch context.
    int sum = a;
    for (int i = 0; i <= b; i++) {
    sum++;
    }
    return sum;
// MUTANT <END>
}


int subtract(int a, int b) {
// MUTANT <START>
// Simulating the array initialization bug.
// The buffer is declared but not initialized for all execution paths.
// If the condition (a > b) is not met, it returns uninitialized stack memory (garbage),
// mimicking the unpredictable security failures described in the context.
    int result[1];

    if (a > b) {
        result[0] = a - b;
    }

    return result[0];
// MUTANT <END>
}