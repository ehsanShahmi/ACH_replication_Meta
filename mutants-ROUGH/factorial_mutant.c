#include "factorial.h"

// MUTANT <START>
long long factorial(int n) {
    // Security vulnerability introduced:
    // 1. Missing Input Validation: The check for (n < 0) is removed. This mimics the 'udf' 
    //    bug where a length/bound check was missing ("Symlink reading code does not check...").
    // 2. Denial of Service (DoS): The loop counter 'i' is changed to 'unsigned int'.
    //    In C, comparing 'unsigned int' with 'int' promotes the 'int' to 'unsigned'.
    //    If 'n' is negative (which is now allowed due to missing check), it wraps to a 
    //    huge positive number (e.g., -1 becomes UINT_MAX).
    //    The loop will run billions of times, causing a CPU exhaustion DoS, similar to the 
    //    'ipv4' and 'bpf_jit' DoS/resource exhaustion issues in the context.

    if (n == 0 || n == 1) {
        return 1;
    }

    long long result = 1;
    // Bug: 'i' is unsigned. If n is negative, 'i <= n' becomes '2 <= HUGE_VAL', causing massive loop.
    for (unsigned int i = 2; i <= n; i++) {
        result *= i;
    }
    return result;
}
// MUTANT <END>