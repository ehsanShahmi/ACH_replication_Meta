#!/bin/bash

# master_test.sh

# Define variables for clarity
Summarizer="./scripts/summarizer.py"
ISSUE_DIR="./security_issues_test"
INCLUDE_DIR="./includes"
OUTPUT_DIR="./outputs"
Mutator="./scripts/mutator.py"
eqChecker="./scripts/eqChecker.py"
sec_test_gen="./scripts/sec_test_gen.py"

current_code="./current_code_repo/my_functions.c" 
existing_test_cases="./current_code_repo/testcases/test_my_functions.c"

echo "Whole script process..."
echo "-------------------------------------"

# Loop through all .txt files in the target directory
for issue_file in "$ISSUE_DIR"/*.txt; do
    if [ -f "$issue_file" ]; then
        echo "Processing file for summary: $issue_file"
        summary=$(python3 "$Summarizer" "$issue_file")
        echo "(LLM1) Generating a mutant for current repo and existing testcases: $current_code and $existing_test_cases:"
        mutant_file=$(python3 "$Mutator" "$summary" "$current_code" "$existing_test_cases")
        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed or returned an empty filename."
            continue
        else
            echo "Mutant generated successfully in $mutant_file. SUCCESS !"
            echo
            echo
        fi

        echo "<---STAGE 1 VALIDATION: whether mutant is buildable and whether mutant is passed with existing testcase:--->"
        echo "--------------------------------------------------------------------"
        # --- STEP 1: ATTEMPT TO COMPILE BOTH FILES ---
        TEST_RUNNER_EXEC="$OUTPUT_DIR/test_runner"
        echo "Check 1: Attempting to BUILD mutant code: $mutant_file and existing test_cases: $existing_test_cases"
        gcc -I"$INCLUDE_DIR" "$mutant_file" "$existing_test_cases" -o "$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
            echo "COMPILATION FAILED: Aborting iteration for this issue since new mutant is not buildable."
            continue # ABORT ITERATION
        fi
        echo "Mutant is buildable. SUCCESS !"
        echo
        echo

        # --- STEP 2: RUN THE GENERATED TEST EXECUTABLE ---
        echo "Check 2: Checking to see if mutant passes with the existing test cases..."
        ./"$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
            echo "TESTS FAILED: Mutant did not pass existing test cases. Aborting iteration. DISCARD THIS MUTANT."
            continue # ABORT ITERATION
        else
            echo "TESTS PASSED: Mutant passed existing test cases. SUCCESS !"
            echo
            echo
            # If tests pass, it means the mutant *might* be equivalent. We proceed to eqChecker.
        fi
        echo "--------------------------------------------------------------------"
        echo
        # --- STEP 3: RUN THE EQUIVALENCY CHECKER (ONLY REACHED IF TESTS PASSED) ---
        echo "(LLM2) Equivalency Checker initiated..."
        equi_ans=$(python3 "$eqChecker" "$mutant_file" "$current_code")

        # Check the answer from eqChecker script
        if [[ "$equi_ans" == "{no}"* ]]; then
            echo
            echo
            echo "Equivalency test returned "{no}". SUCCESS !"
            echo "(LLM3) New Test Case Generation initiated..."
            # Proceed to the 3rd new_test_case generation script
            new_test_case_file=$(python3 "$sec_test_gen" "$current_code" "$mutant_file" "$existing_test_cases")
            # Check the exit status of the test gen script
            if [ $? -ne 0 ]; then
                echo "ERROR: sec_test_gen script failed."
                break
            fi
            echo "New test case generated in: $new_test_case_file. SUCCESS !"
            echo
            echo

            # ----------------------------------------------------------------------
            ## NOW PERFORM THE FINAL 3 CHECKS using the new_test_case_file
            # ----------------------------------------------------------------------

            echo "<---STAGE 2 VALIDATION: whether new test cases are buildable, then if they are passed with original code and then if they are killed using mutant--->"
            echo "--------------------------------------------------------------------"
            # 1. Check if the new test cases are buildable with the *original* code. We need YES (i.e., exit code 0)
            ORIGINAL_RUN_EXEC="$OUTPUT_DIR/original_test_run"
            echo "Check 1: Building original repo with new test cases..."
            gcc -I"$INCLUDE_DIR" "$current_code" "$new_test_case_file" -o "$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: The original code failed to compile with the new test cases. Aborting iteration."
                continue
            else
                echo "Generated New test cases are successfully buildable. SUCCESS !"
                echo
                echo
            fi

            # 2. Now we check if the new test cases *pass* on the *original* file. We need YES (i.e., exit code 0)
            echo "Check 2: Running new test cases on original code..."
            ./"$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: New test cases failed on original code. SO NEW TEST CASES ARE INCORRECTLY MADE. Aborting iteration."
                continue
            fi
            echo "PASS: New test cases pass on original code/repo. SUCCESS !"
            echo
            echo

            # 3. Finally we check if the new test cases pass or fail on the *mutant* file. We need FAIL (i.e., exit code non-zero)
            MUTANT_NEW_RUN_EXEC="$OUTPUT_DIR/mutant_new_test_run"
            echo "Check 3: Running new test cases on mutant code..."
            # We already compiled the mutant with the *original* test cases earlier (TEST_RUNNER_EXEC), we need a new binary:
            gcc -I"$INCLUDE_DIR" "$mutant_file" "$new_test_case_file" -o "$MUTANT_NEW_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: Mutant code failed to compile with new test cases. Aborting iteration. MUTANT AND NEW TEST CASE ARE DISCARDED."
                continue
            fi

            ./"$MUTANT_NEW_RUN_EXEC"
            if [ $? -eq 0 ]; then
                # If exit code is 0, the test passed, which is the wrong outcome for a successful mutation.
                echo "FAIL: Mutant passed the new security test case. No valid vulnerability found for this issue. SO THIS MUTANT AND NEW TEST CASES ARE DISCARDED."
                echo "--------------------------------------------------------------------"
                continue
            else
                # If exit code is non-zero, the test failed, which is the desired outcome (mutant is caught)
                echo "Mutant failed the new security test case. Valid mutant found! MUTANT KILLED. SUCCESS !"
                echo "--------------------------------------------------------------------"
                # Proceed with final logging or move the found mutant file to a specific location
            fi

        else
            # If the checker says it IS equivalent (which matches our test results)
            echo "EQUIVALENT MUTANT confirmed by LLM2 eqChecker (Answer was: $equi_ans). Aborting repo. DISCARD THIS MUTANT !"
            continue
        fi

    fi
done
echo
echo "Process finished."
echo