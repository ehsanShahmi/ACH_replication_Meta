// test_my_functions_extended.c
#include <stdio.h> // For printing test results
#include <limits.h> // For INT_MAX, INT_MIN
#include "my_functions.h" // Include the header of the file under test

// Custom assertion macro that returns 1 on failure
#define TEST_FAIL_FLAG 1
#define TEST_PASS_FLAG 0

// Modified ASSERT_EQUAL to return a failure code
// The __FILE__ and __LINE__ provide better context for where the failure occurs.
#define ASSERT_EQUAL(expected, actual, message) \
    do { \
        if ((expected) != (actual)) { \
            printf("FAIL: %s (File: %s, Line: %d) - Expected %d, Got %d\n", message, __FILE__, __LINE__, expected, actual); \
            return TEST_FAIL_FLAG; \
        } \
        printf("PASS: %s\n", message); \
    } while(0)

// Original test functions (from the provided test suite)
int test_add() {
    ASSERT_EQUAL(5, add(2, 3), "add(2, 3) should be 5");
    ASSERT_EQUAL(0, add(-1, 1), "add(-1, 1) should be 0");
    ASSERT_EQUAL(10, add(5, 5), "add(5, 5) should be 10");
    return TEST_PASS_FLAG;
}

int test_subtract() {
    ASSERT_EQUAL(1, subtract(3, 2), "subtract(3, 2) should be 1");
    ASSERT_EQUAL(-2, subtract(1, 3), "subtract(1, 3) should be -2");
    ASSERT_EQUAL(0, subtract(5, 5), "subtract(5, 5) should be 0");
    return TEST_PASS_FLAG;
}

// --- NEW TEST CASES TO KILL MUTANTS ---

// These new test cases are designed to trigger the out-of-bounds (OOB) write vulnerabilities
// present in the mutant version of my_functions.c.
//
// The mutants preserve the original function's return value, meaning standard ASSERT_EQUAL
// checks on the return value alone will not detect the bug. Instead, these tests aim to
// cause an OOB write that leads to undefined behavior, which often manifests as a program crash
// (e.g., a segmentation fault). A crash is typically interpreted as a test failure by a test runner.

int test_add_mutant_trigger_simple_oob() {
    // For `add` function's mutant: `char vulnerable_buffer[64];`
    // This test triggers an out-of-bounds write by making `a + b` result in an index
    // that is >= 64, without necessarily causing an integer overflow of `a + b` itself.
    // The index 64 accesses memory immediately after the allocated buffer.
    int a = 32;
    int b = 32;
    int expected = a + b; // Expected result from both original and mutant (64)
    int actual = add(a, b);
    ASSERT_EQUAL(expected, actual, "add(32, 32) should be 64 (triggers simple OOB in mutant's add)");
    return TEST_PASS_FLAG;
}

int test_add_mutant_trigger_int_overflow_oob() {
    // For `add` function's mutant: `char vulnerable_buffer[64];`
    // This test triggers an integer overflow in the calculation `a + b`.
    // If `a + b` overflows (e.g., `INT_MAX + 1` becomes `INT_MIN`), the resulting
    // negative or very large positive index will cause an extreme out-of-bounds write
    // to `vulnerable_buffer`, highly likely to result in a crash.
    int a = INT_MAX - 100; // A large positive number close to INT_MAX
    int b = 200;           // A positive number that will cause `a + b` to overflow
    
    // The C standard defines integer overflow for signed types as undefined behavior,
    // but common implementations wrap around (e.g., INT_MAX + 1 -> INT_MIN).
    // The expected result checked by ASSERT_EQUAL will be the wrapped value, which
    // is consistent for both the original and mutant function's return.
    int expected = a + b; 
    int actual = add(a, b);
    ASSERT_EQUAL(expected, actual, "add(INT_MAX - 100, 200) should wrap (triggers int overflow OOB in mutant's add)");
    return TEST_PASS_FLAG;
}

int test_subtract_mutant_trigger_simple_oob() {
    // For `subtract` function's mutant: `char scratchpad_buffer[32];`
    // This test triggers an out-of-bounds write by making `a - b` result in an index
    // that is >= 32, without necessarily causing an integer underflow of `a - b` itself.
    // The index 40 accesses memory after the allocated buffer.
    int a = 50;
    int b = 10;
    int expected = a - b; // Expected result from both original and mutant (40)
    int actual = subtract(a, b);
    ASSERT_EQUAL(expected, actual, "subtract(50, 10) should be 40 (triggers simple OOB in mutant's subtract)");
    return TEST_PASS_FLAG;
}

int test_subtract_mutant_trigger_int_underflow_oob() {
    // For `subtract` function's mutant: `char scratchpad_buffer[32];`
    // This test triggers a large negative result for `a - b`. While `0 - INT_MAX` is
    // a valid `int` value (`-INT_MAX`), using such a large negative number as an array index
    // will almost certainly cause an out-of-bounds access and likely a crash.
    int a = 10;
    int b = INT_MAX; // A large positive number
    
    // The result `a - b` will be a large negative number (e.g., 10 - 2147483647 = -2147483637).
    // This value is within `int` range, but as an index for `scratchpad_buffer`, it is highly OOB.
    int expected = a - b;
    int actual = subtract(a, b);
    ASSERT_EQUAL(expected, actual, "subtract(10, INT_MAX) should be large negative (triggers int underflow OOB in mutant's subtract)");
    return TEST_PASS_FLAG;
}

// Array of test functions to run systematically
typedef int (*test_func_ptr)(void);
struct TestCase {
    const char* name;
    test_func_ptr func;
};

// List all test cases, including original and new ones
struct TestCase test_cases[] = {
    {"test_add", test_add},
    {"test_subtract", test_subtract},
    {"test_add_mutant_trigger_simple_oob", test_add_mutant_trigger_simple_oob},
    {"test_add_mutant_trigger_int_overflow_oob", test_add_mutant_trigger_int_overflow_oob},
    {"test_subtract_mutant_trigger_simple_oob", test_subtract_mutant_trigger_simple_oob},
    {"test_subtract_mutant_trigger_int_underflow_oob", test_subtract_mutant_trigger_int_underflow_oob}
};

int num_test_cases = sizeof(test_cases) / sizeof(test_cases[0]);

int main() {
    printf("Running tests for my_functions.c:\n");
    int overall_status = TEST_PASS_FLAG;

    for (int i = 0; i < num_test_cases; ++i) {
        printf("\n--- Running Test: %s ---\n", test_cases[i].name);
        // Execute the test function.
        // If an ASSERT_EQUAL fails, the function returns TEST_FAIL_FLAG.
        // If an out-of-bounds write in the mutant causes a crash, the program will
        // terminate abnormally at this point (before `if` condition can be evaluated),
        // which implies test failure.
        if (test_cases[i].func() != TEST_PASS_FLAG) {
            overall_status = TEST_FAIL_FLAG;
            printf("CRITICAL FAILURE: Test '%s' explicitly failed. Aborting further tests.\n", test_cases[i].name);
            break; // Stop on the first explicit failure, as per requirements
        }
    }

    if (overall_status == TEST_PASS_FLAG) {
        printf("\nAll tests passed successfully (no explicit ASSERT_EQUAL failures or immediate crashes detected by harness).\n");
        printf("Note: The mutant versions contain side-effect buffer overflows that might cause crashes "
               "detectable by the operating system (e.g., segmentation fault) even if ASSERT_EQUAL passes. "
               "Such crashes would also signify a test failure.\n");
        return 0; // Success
    } else {
        printf("\nOne or more tests failed (explicit ASSERT_EQUAL failure detected).\n");
        return 1; // Failure
    }
}