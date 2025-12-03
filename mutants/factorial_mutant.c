#include "factorial.h"
#include <stdlib.h> // For malloc, free
#include <limits.h> // For LLONG_MAX, INT_MAX, SIZE_MAX

// MUTANT <START>
// This mutation introduces a security vulnerability related to integer overflow
// leading to a potential heap buffer overflow. It mirrors the "id set before
// full initialization/validation" pattern described in the context.
//
// Context: "area_cache_get() set cache->id before cpp->op->area_init() and nfp_cpp_area_acquire().
// To avoid the use-after-free, set cache->id after area_init() and nfp_cpp_area_acquire()
// complete successfully."
//
// In this mutated `factorial` function:
// 1. `buffer_size` calculation (`(size_t)n * element_size`) acts as setting `cache->id`.
//    This calculation is performed *before* validating if `n` (an `int`) is too large
//    for the `size_t` type when multiplied by `element_size`.
// 2. `malloc(buffer_size)` acts as `nfp_cpp_area_acquire()`.
// 3. The loop that performs the factorial calculation, and potentially writes to the buffer,
//    acts as `cpp->op->area_init()`.
//
// The Bug: If `n` is a sufficiently large `int` (e.g., close to `INT_MAX`), and `size_t` is
// a 32-bit type (common on 32-bit systems), the multiplication `(size_t)n * element_size`
// can overflow. This causes `buffer_size` to wrap around and become a much smaller value
// than intended. `malloc()` will then allocate a small buffer.
// Subsequently, if the factorial calculation iterates up to `n`, it might attempt to write
// into `calculation_buffer` beyond its actual allocated size, leading to a heap buffer overflow.
// This is a "use-after-bad-size-allocation" scenario, where the "id" (`buffer_size`) was set
// incorrectly, leading to an invalid resource state and a security violation when used.

long long factorial(int n) {
    if (n < 0) {
        return 0; 
    }
    if (n == 0 || n == 1) {
        return 1;
    }

    // Simulate needing a buffer for calculation for "larger" numbers,
    // where `n` dictates the required size for internal representation.
    // We choose a multiplier that can cause overflow with a large `n` on 32-bit systems.
    const size_t element_size = sizeof(long long); // Example: for storing intermediate long long results

    // MUTANT: Calculate the *intended* buffer size. This acts as our "cache->id".
    // This calculation is performed *before* actual resource acquisition (malloc)
    // and *before* full validation that `n` won't cause an overflow here.
    size_t buffer_size = (size_t)n * element_size;

    // A crucial check to prevent overflow in `buffer_size` calculation would be:
    // `if (n > (int)(SIZE_MAX / element_size)) { /* handle error: n too large for buffer_size */ }`
    // This check is intentionally omitted to introduce the bug.
    // If `n` is large enough (e.g., `n = INT_MAX` on a 32-bit system where `size_t` is also 32-bit),
    // `buffer_size` will wrap around due to integer overflow, becoming a much smaller value.

    char *calculation_buffer = NULL;

    // Simulate `nfp_cpp_area_acquire()`: Allocate the buffer based on `buffer_size`.
    calculation_buffer = (char *)malloc(buffer_size);

    if (calculation_buffer == NULL && buffer_size > 0) {
        // Malloc failed (e.g., OOM), or `buffer_size` became 0 due to overflow from `n * element_size`.
        // In the context, 'id' is set (buffer_size has a value), but acquisition fails.
        // The `buffer_size` variable (our "id") still holds a potentially incorrect value.
        // This is a problematic state if not handled correctly.
        return 0; // Simulate error on failed acquisition
    }

    long long result = 1;
    for (int i = 2; i <= n; i++) {
        // Simulate `cpp->op->area_init()` - writing into the buffer for intermediate calculations.
        // If `buffer_size` overflowed, `malloc()` provided a small buffer.
        // Now, if `i` grows larger than the *actual* allocated `buffer_size`
        // (which is much smaller than the *intended* size based on `n`),
        // we'll have a heap buffer overflow.
        
        // This condition identifies when an out-of-bounds write would occur
        // if the `buffer_size` calculation had overflowed.
        if (calculation_buffer != NULL && (size_t)i * element_size > buffer_size) {
            // MUTANT: This is the security violation: a heap buffer overflow.
            // We are attempting to write one byte past the end of the *actually* allocated buffer.
            // This occurs because `buffer_size` was incorrectly calculated due to integer overflow,
            // leading `malloc` to allocate a smaller chunk than required.
            // The "id" (`buffer_size`) was set too early and was erroneous.
            calculation_buffer[buffer_size] = (char)(i % 256); // Write past the end.
                                                              // `buffer_size` is the first invalid index.
            free(calculation_buffer); // Release the corrupted resource to prevent further issues.
            return 0; // Indicate a critical error due to the security violation.
        }

        // Standard factorial calculation.
        // Also check for `long long` overflow, which is another type of security concern.
        if (result > LLONG_MAX / i) {
            if (calculation_buffer) {
                free(calculation_buffer);
            }
            return 0; // Indicate numerical overflow error
        }
        result *= i;
    }

    // Release the resource if it was successfully acquired.
    if (calculation_buffer) {
        free(calculation_buffer);
    }
    
    return result;
}
// MUTANT <END>