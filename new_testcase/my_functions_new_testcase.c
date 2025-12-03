// test_my_functions.c
#include <stdio.h> // For printing test results
#include "my_functions.h" // Include the header of the file under test

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
}

void test_subtract() {
    ASSERT_EQUAL(1, subtract(3, 2), "subtract(3, 2) should be 1");
    ASSERT_EQUAL(-2, subtract(1, 3), "subtract(1, 3) should be -2");
    ASSERT_EQUAL(0, subtract(5, 5), "subtract(5, 5) should be 0");
}

// This test is designed to cause a buffer overflow in the mutated 'add' function.
// The string "add 100000000 100000000" is 23 characters long (plus null terminator),
// which will overflow the 16-byte buffer in the mutant, causing a program crash.
// The original function will pass this test as it only performs the addition.
void test_add_for_buffer_overflow() {
    int a = 100000000;
    int b = 100000000;
    int expected = 200000000;
    ASSERT_EQUAL(expected, add(a, b), "add with large numbers to trigger buffer overflow");
}

// This test is designed to cause a buffer overflow in the mutated 'subtract' function.
// The string "subtract 10000 from 10000" is 25 characters long (plus null terminator),
// which will overflow the 20-byte buffer in the mutant, causing a program crash.
// The original function will pass this test as it only performs the subtraction.
void test_subtract_for_buffer_overflow() {
    int a = 10000;
    int b = 10000;
    int expected = 0;
    ASSERT_EQUAL(expected, subtract(a, b), "subtract with large numbers to trigger buffer overflow");
}

int main() {
    printf("Running tests for my_functions.c:\n");
    test_add();
    test_subtract();

    printf("\nRunning extended tests to detect mutants:\n");
    test_add_for_buffer_overflow();
    test_subtract_for_buffer_overflow();
    
    return 0;
}