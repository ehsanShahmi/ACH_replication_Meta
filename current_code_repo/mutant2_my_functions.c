// my_functions.c
#include "my_functions.h"
#include <stdlib.h> // Required for strdup/free
#include <string.h> // Required for strdup

// MUTANT <START>
// Global variables to simulate a shared resource (like a device name)
// that can be prematurely freed or incorrectly managed, leading to use-after-free.
static char *global_context_name = NULL;
static int context_name_valid = 0; // 0 = invalid, 1 = valid

// Helper functions that might exist in a real driver for managing a resource's lifecycle.
// Their misuse or unexpected interaction with other functions (like add/subtract here)
// leads to the security vulnerability.
void set_global_context_name(const char *name) {
    if (global_context_name) {
        free(global_context_name);
    }
    if (name) {
        global_context_name = strdup(name);
        context_name_valid = 1;
    } else {
        global_context_name = NULL;
        context_name_valid = 0;
    }
}

void invalidate_global_context_name() {
    if (global_context_name) {
        free(global_context_name);
        global_context_name = NULL;
    }
    context_name_valid = 0;
}
// MUTANT <END>

int add(int a, int b) {
    // MUTANT <START>
    // Security bug: Premature resource release (Use-After-Free scenario).
    // This simulates a function having an unexpected side effect of freeing a shared resource
    // that is still referenced elsewhere. This is analogous to the context's bug where
    // a device name is freed too early, leading to a UAF when `dev_info()` tries to print it.
    if (context_name_valid) {
        // In a complex driver, `add` might internally call a subsystem that
        // mistakenly thinks it's done with `global_context_name` and frees it,
        // while other parts of the driver still hold a pointer to it.
        invalidate_global_context_name();
    }
    // MUTANT <END>
    return a + b;
}

int subtract(int a, int b) {
    // MUTANT <START>
    // Security bug: Double-free or another form of premature resource release.
    // If `add` (or another function) already freed `global_context_name`,
    // this function attempting to free it again results in a double-free,
    // a critical security vulnerability.
    // Even if `add` didn't free it, if `subtract` frees it while other parts
    // of the system still rely on it, it's a Use-After-Free for those parts.
    if (global_context_name) {
        // This function might mistakenly assume it's responsible for the resource's lifecycle,
        // or a guard condition that should prevent a redundant free is missing.
        free(global_context_name);
        global_context_name = NULL; // Prevent immediate further double-frees within this function call.
        context_name_valid = 0;
    }
    // MUTANT <END>
    return a - b;
}