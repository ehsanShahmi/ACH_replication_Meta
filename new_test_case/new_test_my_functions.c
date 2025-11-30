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

// Forward declarations for functions introduced in the mutant version.
// These are needed for the new test cases to compile. In a real project,
// they would be in "my_functions.h".
void set_global_context_name(const char *name);
void invalidate_global_context_name();


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

// Extra test cases to detect memory management bugs in the mutant version.
// These tests are designed to cause a crash (e.g., double-free) on the
// vulnerable mutant code, which constitutes a test failure. They will pass
// on the original, correct version of the code.

void test_add_then_subtract_causes_double_free() {
    // This test exposes the Use-After-Free vulnerability introduced by `add`.
    // 1. A global resource is set up.
    // 2. `add()` is called, which in the mutant version has a side effect of
    //    prematurely freeing the resource.
    // 3. `subtract()` is called, which in the mutant version will attempt to
    //    free the already-freed resource, causing a double-free crash.
    printf("Running test_add_then_subtract_causes_double_free...\n");
    set_global_context_name("device_context_1");
    add(10, 20); // Prematurely frees the context in the mutant.
    subtract(5, 3); // Attempts to free the same context again.
    // On the original code, this test passes. On a vulnerable mutant, it crashes.
    printf("PASS: Context not prematurely freed by add()\n");
}

void test_subtract_twice_causes_double_free() {
    // This test exposes the double-free vulnerability within `subtract` itself.
    // 1. A global resource is set up.
    // 2. The first call to `subtract()` in the mutant version frees the resource.
    // 3. A second call to `subtract()` will attempt to free the same resource
    //    again, leading to a double-free crash.
    printf("Running test_subtract_twice_causes_double_free...\n");
    set_global_context_name("device_context_2");
    subtract(100, 10); // Frees the context in the mutant.
    subtract(50, 25); // Attempts to free the same context again.
    // On the original code, this test passes. On a vulnerable mutant, it crashes.
    printf("PASS: subtract() does not cause double-free on repeated calls\n");
}

void test_bug_persists_after_reinitialization() {
    // This test simulates a more complex lifecycle scenario where a resource is
    // prematurely freed, then re-initialized, but the faulty logic still leads to a crash.
    // 1. A resource is initialized.
    // 2. `add()` prematurely frees it.
    // 3. The resource is re-initialized with a new value.
    // 4. `subtract()` is called, which correctly frees the new resource.
    // 5. Another call to `subtract()` then causes a double-free on the new resource.
    // This shows the fundamental flaw in `subtract`'s resource management.
    printf("Running test_bug_persists_after_reinitialization...\n");
    set_global_context_name("context_v1");
    add(7, 7); // Prematurely frees context_v1 in the mutant.
    set_global_context_name("context_v2"); // Re-initialize context.
    subtract(20, 10); // Frees context_v2 in the mutant.
    subtract(15, 5); // Attempts to free context_v2 again, causing a crash.
    printf("PASS: Resource lifecycle is correctly managed across re-initialization\n");
}


int main() {
    printf("Running tests for my_functions.c:\n");
    test_add();
    test_subtract();

    printf("\nRunning security tests for mutant detection:\n");
    test_add_then_subtract_causes_double_free();
    test_subtract_twice_causes_double_free();
    test_bug_persists_after_reinitialization();
    return 0;
}