// test_my_functions.c
#include <stdio.h> // For printing test results
#include "../my_functions.h" // Include the header of the file under test

// Simple assertion macro for demonstration
#define ASSERT_EQUAL(expected, actual, message) \
    if ((expected) != (actual)) { \
        printf("FAIL: %s - Expected %d, Got %d\n", message, expected, actual); \
    } else { \
        printf("PASS: %s\n", message); \
    }

void test_add() {
    ASSERT_EQUAL(5, add(2, 3), "add(2, 3) should be 5");
    ASSERT_EQUAL(0, add(-1, 1), "add(-1, 1) should be 0");
    ASSERT_EQUAL(10, add(5, 5), "add(5, 5) should be 10");
    // This new test is designed to fail on the use-after-free mutant in add().
    // After `free(result)`, dereferencing `result` is undefined behavior.
    // It is highly unlikely to return the correct value, causing this assertion to fail.
    // On the correct code, it will pass.
    ASSERT_EQUAL(-20, add(-15, -5), "add(-15, -5) to detect use-after-free");
}

void test_subtract() {
    ASSERT_EQUAL(1, subtract(3, 2), "subtract(3, 2) should be 1");
    ASSERT_EQUAL(-2, subtract(1, 3), "subtract(1, 3) should be -2");
    ASSERT_EQUAL(0, subtract(5, 5), "subtract(5, 5) should be 0");
    // These new tests are designed to fail on the buffer overflow mutant in subtract().
    // The mutant writes the result to a 4-byte buffer. These test cases produce
    // results ("1000" and "-100") that require 5 bytes for their string
    // representation (including the null terminator), causing a stack buffer
    // overflow, which will lead to a crash (test failure).
    // They will pass on the correct code.
    ASSERT_EQUAL(1000, subtract(1000, 0), "subtract(1000, 0) to trigger buffer overflow");
    ASSERT_EQUAL(-100, subtract(0, 100), "subtract(0, 100) to trigger buffer overflow with negative number");
}

int main() {
    printf("Running tests for my_functions.c:\n");
    test_add();
    test_subtract();
    return 0;
}