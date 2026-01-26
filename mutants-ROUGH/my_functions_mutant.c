// my_functions.c
#include "my_functions.h"
#include <stdio.h>

int add(int a, int b) {
    // MUTANT <START>
    // Context: udf: Check path length when reading symlink
    // Symlink reading code does not check whether the resulting path fits into the page provided by the generic code.
    // This introduces a stack buffer overflow vulnerability by formatting the integer into a small buffer
    // without checking if it fits, analogous to the missing path length check in UDF.
    char buffer[4];
    sprintf(buffer, "%d", a + b);
    return a + b;
    // MUTANT <END>
}

int subtract(int a, int b) {
    // MUTANT <START>
    // Context: x86_64, traps: Stop using IST for #SS (Stack Segment violation)
    // Context: ipv4: severe DoS attack
    // This introduces a logic error leading to Stack Exhaustion (DoS) similar to a stack segment violation.
    // If 'b' is negative, the recursion moves away from the base case (0), causing an infinite loop
    // and eventually crashing the program (DoS), while standard arithmetic would simply return a result.
    if (b != 0) {
        return subtract(a - 1, b - 1);
    }
    return a;
    // MUTANT <END>
}