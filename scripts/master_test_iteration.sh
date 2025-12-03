#!/bin/bash

# master_test_iteration.sh

# Define the DIRECTORIES for clarity
ISSUE_DIR="./security_issues_test"
INCLUDE_DIR="./includes"
OUTPUT_DIR="./outputs"
# The single base directory containing all code and the 'testcases' subdirectory
REPO_BASE_DIR="./current_code_repo" 
TEST_SUBDIR="testcases" # Name of the subdirectory for tests

# Define the scripts inside
Summarizer="./scripts/summarizer.py"
Mutator="./scripts/mutator.py"
eqChecker="./scripts/eqChecker.py"
sec_test_gen="./scripts/sec_test_gen.py"

echo "Whole script process started..."
echo "-------------------------------------"


# Collect all issue files into an array, sorted alphabetically
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*.txt" | sort)
# Collect all *code* files into an array, sorted alphabetically (grep -v ignores files with 'test_' in their name)
readarray -t code_files < <(find "$REPO_BASE_DIR" -maxdepth 1 -name "*.c" | grep -v 'test_')


NUM_ISSUES=${#issue_files[@]}
NUM_CODES=${#code_files[@]}
if [ "$NUM_ISSUES" -eq 0 ] || [ "$NUM_CODES" -eq 0 ]; then
    echo "ERROR: Zero issues or code files found. Aborting script."
    exit 1
fi
MAX_ITERATIONS=$NUM_CODES
echo "Found ${NUM_ISSUES} issues and ${NUM_CODES} code files."
echo "Looping ${MAX_ITERATIONS} times, mapping 1 issue to 1 strictly named pair per iteration."
echo "-------------------------------------"


# --- Main Single Loop: Iterate using a numerical index for each issue/pair ---
for (( i=0; i<$MAX_ITERATIONS; i++ )); do
    
    # Assign the correct issue file for this specific iteration (index i)
    issue_file="${issue_files[$i]}"
    current_code="${code_files[$i]}"         


    # --- STRICT PAIRING LOGIC ---
    base_code_filename=$(basename "$current_code")
    # test_filename=$(echo "test_$base_code_filename" | sed 's/\.c$/test_&/')
    test_filename="test_$base_code_filename"
    existing_test_cases="$REPO_BASE_DIR/$TEST_SUBDIR/$test_filename"
    # Verify that the strictly named test file actually exists
    if [ ! -f "$existing_test_cases" ]; then
        echo "[ABORT] ERROR: Strict pairing failed. Expected test file '$existing_test_cases' not found for code '$current_code'."
        continue # Skip this iteration
    fi


    # Define iteration-specific output paths for binaries
    TEST_RUNNER_EXEC="$OUTPUT_DIR/test_runner_i$i"
    ORIGINAL_RUN_EXEC="$OUTPUT_DIR/original_test_run_i$i"
    MUTANT_NEW_RUN_EXEC="$OUTPUT_DIR/mutant_new_test_run_i$i"

    echo "========================================================"
    echo "STARTING ITERATION $((i+1)) / $MAX_ITERATIONS"
    echo "Issue: $issue_file"
    echo "Code: $current_code | Test: $existing_test_cases"
    echo "========================================================"



    summary=$(python3 "$Summarizer" "$issue_file")
    echo "(LLM1) Generating a mutant for current repo and existing testcases: $current_code and $existing_test_cases:"
    mutant_file=$(python3 "$Mutator" "$summary" "$current_code" "$existing_test_cases")
    
    if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
        echo "ERROR: Mutator script failed. Continuing to next iteration."
        continue
    else
        echo "Mutant generated successfully in $mutant_file. SUCCESS !!"
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
        echo "COMPILATION FAILED: Non-buildable mutant generated. Aborting iteration. DISCARD THIS MUTANT :("
        continue # ABORT ITERATION
    fi
    echo "Mutant is buildable. SUCCESS !!"
    echo
    echo

    # --- STEP 2: RUN THE GENERATED TEST EXECUTABLE ---
    echo "Check 2: Checking to see if mutant passes with the existing test cases..."
    ./"$TEST_RUNNER_EXEC"
    if [ $? -ne 0 ]; then
        echo "TESTS FAILED: Mutant did not pass existing test cases. Aborting iteration. DISCARD THIS MUTANT :("
        continue # ABORT ITERATION
    else
        echo "TESTS PASSED: Mutant passed existing test cases. SUCCESS !!"
        echo
        echo
        # If tests pass, it means the mutant *might* be equivalent. We proceed to eqChecker.
    fi
    echo "--------------------------------------------------------------------"
    echo
        
    # --- RUN THE EQUIVALENCY CHECKER (ONLY REACHED IF TESTS PASSED) ---
    echo "(LLM2) Equivalency Checker initiated..."
    equi_ans=$(python3 "$eqChecker" "$mutant_file" "$current_code")

    # Check the answer from eqChecker script
    if [[ "$equi_ans" == "{no}"* ]]; then
        echo "Equivalency test returned "{no}". SUCCESS !!"
        echo
        echo
        echo "(LLM3) New Test Case Generation initiated..."
        # Proceed to the 3rd new_test_case generation script
        new_test_case_file=$(python3 "$sec_test_gen" "$current_code" "$mutant_file" "$existing_test_cases")
        # Check the exit status of the test gen script
        if [ $? -ne 0 ]; then
            echo "ERROR: sec_test_gen script failed."
            break
        fi
        echo "New test case generated in: $new_test_case_file. SUCCESS !!"
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
            echo "FAIL: The original code failed to compile with the new test cases. Aborting iteration. DISCARD MUTANT :("
            continue
        else
            echo "Generated New test cases are successfully buildable. SUCCESS !!"
            echo
            echo
        fi

        # 2. Now we check if the new test cases *pass* on the *original* file. We need YES (i.e., exit code 0)
        echo "Check 2: Running new test cases on original code..."
        ./"$ORIGINAL_RUN_EXEC"
        if [ $? -ne 0 ]; then
            echo "FAIL: New test cases failed on original code. SO NEW TEST CASES ARE INCORRECTLY MADE. Aborting iteration. DISCARD MUTANT :("
            continue
        fi
        echo "PASS: New test cases pass on original code/repo. SUCCESS !!"
        echo
        echo

        # 3. Finally we check if the new test cases pass or fail on the *mutant* file. We need FAIL (i.e., exit code non-zero)
        MUTANT_NEW_RUN_EXEC="$OUTPUT_DIR/mutant_new_test_run"
        echo "Check 3: Running new test cases on mutant code..."
        # We already compiled the mutant with the *original* test cases earlier (TEST_RUNNER_EXEC), we need a new binary:
        gcc -I"$INCLUDE_DIR" "$mutant_file" "$new_test_case_file" -o "$MUTANT_NEW_RUN_EXEC"
        if [ $? -ne 0 ]; then
            echo "FAIL: Mutant code failed to compile with new test cases. Aborting iteration. MUTANT AND NEW TEST CASE ARE DISCARDED. :("
            continue
        fi

        ./"$MUTANT_NEW_RUN_EXEC"
        if [ $? -eq 0 ]; then
            # If exit code is 0, the test passed, which is the wrong outcome for a successful mutation.
            echo "FAIL: Mutant passed the new security test case. No valid vulnerability found for this issue. SO THIS MUTANT AND NEW TEST CASES ARE DISCARDED. :("
            echo "--------------------------------------------------------------------"
            continue
        else
            # If exit code is non-zero, the test failed, which is the desired outcome (mutant is caught)
            echo "Mutant failed the new security test case. FINALLY Valid mutant found! MUTANT KILLED. SUCCESS !!"
            echo "--------------------------------------------------------------------"
            # Proceed with final logging or move the found mutant file to a specific location
        fi

    else
        # If the checker says it IS equivalent (which matches our test results)
        echo "EQUIVALENT MUTANT confirmed by LLM2 eqChecker (Answer was: $equi_ans). Aborting repo. DISCARD THIS MUTANT :("
        continue
    fi
done
echo
echo "Script Process finished."
echo