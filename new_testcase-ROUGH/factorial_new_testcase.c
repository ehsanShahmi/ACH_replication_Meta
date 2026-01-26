#include <stdio.h>
#include "factorial.h"

int main(void) {
    long long result;
    int n_val;

    printf("--- Running Extended Factorial Tests ---\n");

    // --- Existing Test Cases ---

    // Test Case 1: Base case 0!
    n_val = 0;
    result = factorial(n_val);
    if (result != 1LL) {
        printf("[FAIL] Test 0!: factorial(%d) expected 1 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test 0!\n");

    // Test Case 2: Base case 1!
    n_val = 1;
    result = factorial(n_val);
    if (result != 1LL) {
        printf("[FAIL] Test 1!: factorial(%d) expected 1 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test 1!\n");

    // Test Case 3: Standard case 5!
    n_val = 5;
    result = factorial(n_val);
    if (result != 120LL) {
        printf("[FAIL] Test 5!: factorial(%d) expected 120 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test 5!\n");

    // Test Case 4: Standard case 10!
    n_val = 10;
    result = factorial(n_val);
    if (result != 3628800LL) {
        printf("[FAIL] Test 10!: factorial(%d) expected 3628800 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test 10!\n");

    // Test Case 5: Large case 20!
    n_val = 20;
    result = factorial(n_val);
    if (result != 2432902008176640000LL) {
        printf("[FAIL] Test 20!: factorial(%d) expected 2432902008176640000 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test 20!\n");

    // Test Case 6: Negative input (Existing)
    // Correct behavior: return 0.
    // Mutant behavior: enters infinite loop or returns garbage due to unsigned promotion.
    n_val = -5;
    result = factorial(n_val);
    if (result != 0LL) {
        printf("[FAIL] Test Negative Input: factorial(%d) expected 0 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test Negative Input (-5)\n");

    // --- Extra Test Cases ---

    // Test Case 7: Boundary Negative Input -1
    // This targets the specific lack of bounds checking in the mutant.
    // In the mutant, -1 promotes to UINT_MAX, causing the loop to run ~4 billion times.
    // If it finishes, the result will not be 0.
    n_val = -1;
    result = factorial(n_val);
    if (result != 0LL) {
        printf("[FAIL] Test Boundary Negative: factorial(%d) expected 0 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test Boundary Negative (-1)\n");

    // Test Case 8: Large Negative Input
    // Ensures consistency in handling invalid input.
    n_val = -42;
    result = factorial(n_val);
    if (result != 0LL) {
        printf("[FAIL] Test Large Negative: factorial(%d) expected 0 but got %lld\n", n_val, result);
        return 1;
    }
    printf("[PASS] Test Large Negative (-42)\n");

    printf("\n--- All Tests Passed ---\n");

    return 0; 
}