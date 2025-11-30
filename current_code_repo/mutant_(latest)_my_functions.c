#include "my_functions.h"
#include <stdlib.h>
#include <stdio.h>

int add(int a, int b) {
// MUTANT <START>
    int *result = (int *)malloc(sizeof(int));
    *result = a + b;
    free(result);
    // Using the pointer after it has been freed leads to a
    // use-after-free vulnerability, potentially causing a crash or
    // returning garbage data.
    return *result;
// MUTANT <END>
}

int subtract(int a, int b) {
// MUTANT <START>
    char temp_buffer[4];
    // A stack buffer overflow occurs if the string representation of the result
    // (a - b) plus the null terminator is larger than 4 bytes.
    // This can corrupt the stack, similar to an overly large stack frame.
    sprintf(temp_buffer, "%d", a - b);
    return a - b;
// MUTANT <END>
}