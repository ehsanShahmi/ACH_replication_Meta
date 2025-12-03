#include <stdio.h>
#include "factorial.h" // Include our function header

// Macro for simple pass/fail reporting
#define ASSERT_EQUAL(actual, expected, test_name) \
    if (actual == expected) { \
        printf("[PASS] %s: factorial(%d) == %lld\n", test_name, n_val, expected); \
    } else { \
        printf("[FAIL] %s: Expected %lld but got %lld for factorial(%d)\n", test_name, expected, actual, n_val); \
        failures++; \
    }

int main(void) {
    int failures = 0;
    long long result;
    int n_val;

    printf("--- Running Factorial Tests ---\n");

    // Test Case 1: Base case 0!
    n_val = 0;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 1LL, "Test 0!");

    // Test Case 2: Base case 1!
    n_val = 1;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 1LL, "Test 1!");

    // Test Case 3: Standard case 5! (5*4*3*2*1 = 120)
    n_val = 5;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 120LL, "Test 5!");

    // Test Case 4: Standard case 10! (3,628,800)
    n_val = 10;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 3628800LL, "Test 10!");
    
    // Test Case 5: Large case 20! (2,432,902,008,176,640,000)
    // Note: long long is required to hold this value.
    n_val = 20;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 2432902008176640000LL, "Test 20!");

    // Test Case 6: Negative input (Our function returns 0 for negative input)
    n_val = -5;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 0LL, "Test Negative Input");


    printf("\n--- Tests Finished: %d Failures ---\n", failures);

    return failures > 0 ? 1 : 0; // Return non-zero if any tests failed
}
