// my_functions.c
#include "my_functions.h"
#include <stdio.h>

int add(int a, int b) {
    // MUTANT <START>
    char buffer[16];
    // This is vulnerable to a stack-based buffer overflow if the integer
    // string representations of 'a' and 'b' are too long for the buffer.
    sprintf(buffer, "add %d %d", a, b);
    // MUTANT <END>
    return a + b;
}

int subtract(int a, int b) {
    // MUTANT <START>
    char buffer[20];
    // This is also vulnerable to a stack-based buffer overflow if the
    // resulting string is longer than the buffer.
    sprintf(buffer, "subtract %d from %d", b, a);
    // MUTANT <END>
    return a - b;
}