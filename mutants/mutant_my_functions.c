// my_functions.c
#include "my_functions.h"

// MUTANT <START>
int add(int a, int b) {
    // This introduces a large on-stack buffer. In a real kernel context,
    // a structure copy this size led to a `-Werror=frame-larger-than=` warning,
    // indicating a potential stack overflow vulnerability or excessive stack usage.
    // While `add` itself is simple, this bug simulates the stack frame size issue
    // mentioned in the context directly.
    char large_stack_buffer[2048]; // This causes a large stack frame size.
    (void)large_stack_buffer;       // Suppress potential unused variable warning.

    return a + b;
}
// MUTANT <END>

// MUTANT <START>
// This static variable simulates a global resource or a dynamically allocated
// buffer whose contents can be prematurely invalidated or "freed".
static int shared_data_resource;

int subtract(int a, int b) {
    int current_calculation_result = a - b;

    // Simulate the initial step from the context: "we have only copied a pointer to the name earlier"
    // Here, we store the *intended* result in a shared resource.
    // This is analogous to copying a pointer or a simple value expecting it to remain valid.
    shared_data_resource = current_calculation_result;

    // Simulate the problematic step from the context: "the actual name has been freed by the time it gets printed."
    // Here, we prematurely "free" or invalidate the data in `shared_data_resource`
    // by overwriting it with an arbitrary, often invalid, value (e.g., `0xDEADBEEF`).
    // This means any subsequent use of `shared_data_resource` will access "freed" or stale data.
    shared_data_resource = 0xDEADBEEF; // Conceptual "freeing" or invalidation of data

    // Simulate the final step from the context: "the dev_info() call will print the name of the device later"
    // Here, the function attempts to return the value that *should* be the result,
    // but due to the premature invalidation, it's now returning garbage data from
    // what is conceptually "freed" memory. This is a use-after-free analogy,
    // leading to incorrect program behavior or potential security exploits
    // if the caller relies on the correct value.
    return shared_data_resource; // Using the "freed" (invalidated) data
}
// MUTANT <END>