To satisfy the requirement that new test cases MUST FAIL on the mutant version but MUST PASS on the correct version, we need to find an input `n` such that:
1.  The original `factorial(n)` returns a correct, non-zero `long long` value.
2.  The mutant `factorial(n)` returns `0` (due to the simulated heap buffer overflow).

However, analyzing the provided mutant reveals a fundamental contradiction with this requirement under typical C environments:

*   The original `factorial` function can correctly calculate values only up to `factorial(20)` (which fits within `long long`). For `n >= 21`, `long long` overflow occurs, and the original function correctly returns `0`.
*   The mutant's specific bug (integer overflow in `buffer_size = (size_t)n * element_size`) requires `n` to be a "sufficiently large `int` (e.g., close to `INT_MAX`)" on a 32-bit system to cause `size_t` overflow. This means `n` would have to be much larger than 20 (e.g., `n > 536,870,911` for `element_size = 8` and a 32-bit `size_t`).
*   If `n` is large enough to trigger the mutant's `size_t` overflow, it is also *more than large enough* to trigger `long long` overflow (which happens at `n=21`). Therefore, for any `n` that would expose the mutant's specific buffer overflow, the original `factorial` function would *already* return `0` due to `long long` overflow.
*   The mutant, when its heap buffer overflow is triggered, *explicitly returns `0`* (as indicated by `return 0; // Indicate a critical error due to the security violation.`).

This means for any `n` that triggers the mutant's bug, both the original and the mutant will return `0`. Consequently, an `ASSERT_EQUAL(result, 0LL, ...)` test would *pass* for both versions, making it impossible to satisfy the "MUST FAIL on the mutant... but MUST PASS on the correct version" constraint using the provided `ASSERT_EQUAL` macro and the return value checking strategy.

Given this contradiction, the most reasonable approach is to add test cases that *target the conditions* for the mutant's bug, acknowledging that the `ASSERT_EQUAL` macro might not explicitly "fail" the mutant in the specified manner, but that an external memory error detector (like ASan) *would* likely flag the heap buffer overflow.

I will add two test cases:
1.  **Test Case for `n=21`**: This is the smallest integer for which `factorial` exceeds `LLONG_MAX`. Both the original and the mutant should gracefully return `0` due to `long long` overflow detection.
2.  **Test Case for `n=INT_MAX`**: This large value is explicitly mentioned in the mutant's description as a trigger for the `size_t` overflow on a 32-bit system. Both the original and the mutant will return `0` (original due to `long long` overflow, mutant due to `size_t` overflow leading to `malloc(0)` and likely returning `NULL` and then `0`, or the explicit heap overflow path which also returns `0`).

These tests will likely *pass* for both versions under the given `ASSERT_EQUAL` macro, thus not fulfilling the "MUST FAIL on mutant" part of the prompt due to the inherent design of this specific mutant.

#include <stdio.h>
#include <limits.h> // For INT_MAX
#include "factorial.h" // Include our function header

// Macro for simple pass/fail reporting
#define ASSERT_EQUAL(actual, expected, test_name, n_val_arg) \
    if (actual == expected) { \
        printf("[PASS] %s: factorial(%d) == %lld\n", test_name, n_val_arg, expected); \
    } else { \
        printf("[FAIL] %s: Expected %lld but got %lld for factorial(%d)\n", test_name, expected, actual, n_val_arg); \
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
    ASSERT_EQUAL(result, 1LL, "Test 0!", n_val);

    // Test Case 2: Base case 1!
    n_val = 1;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 1LL, "Test 1!", n_val);

    // Test Case 3: Standard case 5! (5*4*3*2*1 = 120)
    n_val = 5;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 120LL, "Test 5!", n_val);

    // Test Case 4: Standard case 10! (3,628,800)
    n_val = 10;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 3628800LL, "Test 10!", n_val);
    
    // Test Case 5: Large case 20! (2,432,902,008,176,640,000)
    // Note: long long is required to hold this value.
    n_val = 20;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 2432902008176640000LL, "Test 20!", n_val);

    // Test Case 6: Negative input (Our function returns 0 for negative input)
    n_val = -5;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 0LL, "Test Negative Input", n_val);

    // --- New Test Cases to target mutant or overflow behavior ---

    // Test Case 7: Factorial(21) - Smallest n that causes long long overflow
    // (20! is max for long long, 21! will overflow)
    // Both original and mutant should return 0 for this.
    n_val = 21;
    result = factorial(n_val);
    ASSERT_EQUAL(result, 0LL, "Test 21! (LLONG Overflow)", n_val);

    // Test Case 8: Factorial(INT_MAX) - Targets the mutant's `size_t` overflow condition
    // This value of n is extremely large, designed to cause the `(size_t)n * element_size`
    // integer overflow if `size_t` is 32-bit and `element_size` is 8.
    // Both original and mutant will return 0 due to long long overflow or the mutant's specific bug.
    n_val = INT_MAX; 
    result = factorial(n_val);
    // Expect 0 due to extreme overflow (long long overflow in original,
    // potential size_t overflow leading to malloc failure or heap bug in mutant).
    ASSERT_EQUAL(result, 0LL, "Test INT_MAX (Extreme N)", n_val);

    printf("\n--- Tests Finished: %d Failures ---\n", failures);

    return failures > 0 ? 1 : 0; // Return non-zero if any tests failed
}