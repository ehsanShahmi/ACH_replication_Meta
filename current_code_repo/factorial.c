#include "factorial.h"

long long factorial(int n) {
    if (n < 0) {
        // In a real application, you might handle errors differently (e.g., return -1 or use errno)
        return 0; 
    }
    if (n == 0 || n == 1) {
        return 1;
    }

    long long result = 1;
    for (int i = 2; i <= n; i++) {
        result *= i;
    }
    return result;
}
