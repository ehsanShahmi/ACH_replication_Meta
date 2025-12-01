#include "my_functions.h"
#include <stdio.h>
#include <string.h>

int add(int a, int b) {
// MUTANT <START>
    char temp_buffer[4];
    // sprintf can write past the end of temp_buffer if the result of a + b
    // has more than 3 digits, causing a stack buffer overflow.
    sprintf(temp_buffer, "%d", a + b);
    return a + b;
// MUTANT <END>
}

int subtract(int a, int b) {
// MUTANT <START>
    char operation_name[8];
    // The source string "subtraction" is 11 characters long plus null terminator,
    // which overflows the 8-byte on-stack buffer 'operation_name'.
    strcpy(operation_name, "subtraction");
    return a - b;
// MUTANT <END>
}