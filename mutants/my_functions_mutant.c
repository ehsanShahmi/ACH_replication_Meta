    // my_functions.c
    #include "my_functions.h"

    int add(int a, int b) {
        // MUTANT <START>
        // This large array simulates the "on-stack copy of the USB device structure"
        // that would cause a stack frame size warning, as per the context.
        char dummy_large_buffer[4096]; // A large buffer on the stack.

        // Introduce an integer overflow vulnerability that leads to a buffer overflow.
        // The sum 'a + b' might overflow if 'a' and 'b' are large.
        // If this sum is then used as an index into a stack-allocated buffer
        // without proper bounds checking, it can lead to an out-of-bounds write.
        // For example, if `a + b` overflows to a negative number, and then is implicitly
        // converted to an unsigned index, it becomes a very large positive number,
        // causing an out-of-bounds write.

        char vulnerable_buffer[64]; // A smaller buffer on the stack for demonstration.
        int offset = a + b; // Potential integer overflow here.

        // SECURITY VIOLATION: Lack of proper bounds checking.
        // If `offset` overflows to a negative number (e.g., `INT_MAX + 1` -> `INT_MIN`),
        // or is a large positive number beyond the buffer's size,
        // `vulnerable_buffer[offset]` will result in an out-of-bounds write.
        vulnerable_buffer[offset] = (char)(a % 256); 

        // The original arithmetic return value is preserved to allow existing tests to pass
        // for the function's primary purpose, while the side-effect vulnerability is present.
        return a + b;
        // MUTANT <END>
    }

    int subtract(int a, int b) {
        // MUTANT <START>
        // Another large on-stack allocation to simulate the context's "stack frame size warning".
        char another_large_buffer[4096];

        // Introduce an integer underflow/overflow vulnerability.
        // The difference 'a - b' might underflow if 'a' is small and 'b' is large.
        // If this result is then used as an index for a stack-allocated buffer
        // without proper bounds checking, it can lead to an out-of-bounds write.
        char scratchpad_buffer[32]; // A small buffer on the stack.

        int difference = a - b; // Potential integer underflow (e.g., `0 - INT_MAX` -> `-INT_MAX`).

        // SECURITY VIOLATION: Lack of proper bounds checking.
        // If `difference` underflows to a negative number (e.g., `-INT_MAX`),
        // or is a large positive number beyond the buffer's size,
        // `scratchpad_buffer[difference]` will result in an out-of-bounds write.
        scratchpad_buffer[difference] = (char)(b % 256);

        // The original arithmetic return value is preserved.
        return a - b;
        // MUTANT <END>
    }