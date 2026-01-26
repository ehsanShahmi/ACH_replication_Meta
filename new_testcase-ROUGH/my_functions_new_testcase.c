// test_my_functions.c
#include <stdio.h>
#include <stdlib.h>
#include "my_functions.h"

// Assertion macro that exits on failure as requested
#define ASSERT_EQUAL(expected, actual, message) \
    do { \
        int exp = (expected); \
        int act = (actual); \
        if (exp != act) { \
            printf("FAIL: %s - Expected %d, Got %d\n", message, exp, act); \
            exit(1); \
        } else { \
            printf("PASS: %s\n", message); \
        } \
    } while(0)

void test_add() {
    ASSERT_EQUAL(5, add(2, 3), "add(2, 3) should be 5");
    ASSERT_EQUAL(0, add(-1, 1), "add(-1, 1) should be 0");
    ASSERT_EQUAL(10, add(5, 5), "add(5, 5) should be 10");
}

void test_add_buffer_overflow() {
    // This test case targets the buffer overflow vulnerability in the mutant.
    // The mutant uses a char buffer[4] to store the string representation of the result.
    // 5000 + 5000 = 10000. The string "10000" requires 5 characters + 1 null terminator = 6 bytes.
    // This will overflow the buffer, likely corrupting the stack/return address and causing a crash.
    ASSERT_EQUAL(10000, add(5000, 5000), "add(5000, 5000) should be 10000");
}

void test_subtract() {
    ASSERT_EQUAL(1, subtract(3, 2), "subtract(3, 2) should be 1");
    ASSERT_EQUAL(-2, subtract(1, 3), "subtract(1, 3) should be -2");
    ASSERT_EQUAL(0, subtract(5, 5), "subtract(5, 5) should be 0");
}

void test_subtract_infinite_recursion() {
    // This test case targets the logic error in the mutant leading to stack exhaustion.
    // The mutant subtracts by recursively decrementing b until it equals 0.
    // If b is negative (e.g., -5), the condition b != 0 is always true as b decreases further (-6, -7...),
    // causing an infinite loop and eventually a stack overflow crash.
    // The correct implementation simply performs arithmetic subtraction: 0 - (-5) = 5.
    ASSERT_EQUAL(5, subtract(0, -5), "subtract(0, -5) should be 5");
}

int main() {
    printf("Running tests for my_functions.c:\n");
    
    // Existing tests
    test_add();
    test_subtract();

    // New tests to kill mutants
    test_add_buffer_overflow();
    test_subtract_infinite_recursion();

    printf("All tests passed.\n");
    return 0;
}