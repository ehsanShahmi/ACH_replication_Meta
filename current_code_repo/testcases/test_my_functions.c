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
    }

    void test_subtract() {
        ASSERT_EQUAL(1, subtract(3, 2), "subtract(3, 2) should be 1");
        ASSERT_EQUAL(-2, subtract(1, 3), "subtract(1, 3) should be -2");
        ASSERT_EQUAL(0, subtract(5, 5), "subtract(5, 5) should be 0");
    }

    int main() {
        printf("Running tests for my_functions.c:\n");
        test_add();
        test_subtract();
        return 0;
    }