#!/bin/bash

# master_script.sh

# Define the DIRECTORIES for clarity
ISSUE_DIR="./security_issue_cluster_test"
INCLUDE_DIR="./includes"
OUTPUT_DIR="./outputs"
REPO_BASE_DIR="./current_code_repo" 
TEST_SUBDIR="testcases"

# Define the scripts inside
Summarizer="./scripts/summarizer.py"
Mutator="./scripts/mutator.py"
eqChecker="./scripts/eqChecker.py"
sec_test_gen="./scripts/sec_test_gen.py"

echo "Whole script process started..."
echo "-------------------------------------"

# Create output dir if not exists
mkdir -p "$OUTPUT_DIR"

# Collect all issue files into an array (e.g., CWE-16.txt, CWE-119.txt)
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*.txt" | sort)
# Collect all *code* files into an array (grep -v ignores files with 'test_' in their name)
readarray -t code_files < <(find "$REPO_BASE_DIR" -maxdepth 1 -name "*.c" | grep -v 'test_')

NUM_ISSUES=${#issue_files[@]}
NUM_CODES=${#code_files[@]}

if [ "$NUM_ISSUES" -eq 0 ] || [ "$NUM_CODES" -eq 0 ]; then
    echo "ERROR: Zero issues or code files found. Aborting script."
    exit 1
fi

echo "Found ${NUM_ISSUES} issue files and ${NUM_CODES} code files."
echo "Running Nested Loop: Every Issue x Every Code Pair."
echo "-------------------------------------"

# Initialize counters for logging
issue_count=0

# --- OUTER LOOP: Iterate through each ISSUE file ---
for issue_file in "${issue_files[@]}"; do
    ((issue_count++))
    issue_name=$(basename "$issue_file")
    
    echo "############################################################"
    echo "[OUTER LOOP] Processing Issue $issue_count / $NUM_ISSUES : $issue_name"
    echo "############################################################"

    # 1. Generate Summary ONCE per issue file to save resources
    echo "Generating Summary for issue: $issue_name..."
    summary=$(python3 "$Summarizer" "$issue_file")
    
    if [ -z "$summary" ]; then
        echo "ERROR: Summary generation failed for $issue_name. Skipping this issue."
        continue
    fi

    # Initialize code counter for inner loop
    code_count=0

    # --- INNER LOOP: Iterate through each CODE file ---
    for current_code in "${code_files[@]}"; do
        ((code_count++))
        
        # --- STRICT PAIRING LOGIC ---
        base_code_filename=$(basename "$current_code")
        test_filename="test_$base_code_filename"
        existing_test_cases="$REPO_BASE_DIR/$TEST_SUBDIR/$test_filename"

        # Verify that the strictly named test file actually exists
        if [ ! -f "$existing_test_cases" ]; then
            echo "[SKIP] Code '$base_code_filename' skipped. Expected test file '$test_filename' not found."
            continue 
        fi

        echo "========================================================"
        echo "   [INNER LOOP] Issue: $issue_name | Code Pair: $base_code_filename ($code_count/$NUM_CODES)"
        echo "========================================================"

        # 2. Mutator: Uses the Outer Loop Summary + Inner Loop Code
        echo "(LLM1) Generating a mutant for $base_code_filename..."
        mutant_file=$(python3 "$Mutator" "$summary" "$current_code" "$existing_test_cases")
        
        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed. Continuing to next code pair."
            continue
        else
            echo "Mutant generated successfully in $mutant_file. SUCCESS !!"
            echo
        fi

        echo "<---STAGE 1 VALIDATION: buildable and passes existing tests--->"
        echo "--------------------------------------------------------------------"
        
        # Define binary paths (Overwritten per iteration to save space)
        TEST_RUNNER_EXEC="$OUTPUT_DIR/test_runner"
        
        # --- STEP 1: ATTEMPT TO COMPILE MUTANT ---
        echo "Check 1: Building mutant code..."
        gcc -I"$INCLUDE_DIR" "$mutant_file" "$existing_test_cases" -o "$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
            echo "COMPILATION FAILED: Non-buildable mutant. DISCARD THIS MUTANT :("
            continue
        fi
        echo "Mutant is buildable. SUCCESS !!"
        echo

        # --- STEP 2: RUN EXISTING TEST CASES ---
        echo "Check 2: Running existing test cases on mutant..."
        ./"$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
            echo "TESTS FAILED: Mutant killed by existing tests. DISCARD THIS MUTANT :("
            continue
        else
            echo "TESTS PASSED: Mutant passes existing tests. SUCCESS !!"
            echo
        fi
        echo "--------------------------------------------------------------------"
            
        # --- RUN EQUIVALENCY CHECKER ---
        echo "(LLM2) Equivalency Checker initiated..."
        equi_ans=$(python3 "$eqChecker" "$mutant_file" "$current_code")

        if [[ "$equi_ans" == "{no}"* ]]; then
            echo "Equivalency test returned {no}. SUCCESS !!"
            echo
            echo "(LLM3) New Test Case Generation initiated..."
            
            # 3. New Test Case Generation
            new_test_case_file=$(python3 "$sec_test_gen" "$current_code" "$mutant_file" "$existing_test_cases")
            
            if [ $? -ne 0 ]; then
                echo "ERROR: sec_test_gen script failed."
                continue
            fi
            echo "New test case generated: $new_test_case_file. SUCCESS !!"
            echo

            echo "<---STAGE 2 VALIDATION: New tests logic--->"
            echo "--------------------------------------------------------------------"
            
            # 1. Check if new tests build with ORIGINAL code
            ORIGINAL_RUN_EXEC="$OUTPUT_DIR/original_test_run"
            echo "Check 1: Building original repo with new test cases..."
            gcc -I"$INCLUDE_DIR" "$current_code" "$new_test_case_file" -o "$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: Original code failed to compile with new tests. DISCARD MUTANT :("
                continue
            else
                echo "New test cases buildable. SUCCESS !!"
                echo
            fi

            # 2. Check if new tests PASS on ORIGINAL code
            echo "Check 2: Running new test cases on original code..."
            ./"$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: New test cases failed on original code (False Positive). DISCARD MUTANT :("
                continue
            fi
            echo "PASS: New test cases pass on original code. SUCCESS !!"
            echo

            # 3. Check if new tests FAIL on MUTANT code (The Kill)
            MUTANT_NEW_RUN_EXEC="$OUTPUT_DIR/mutant_new_test_run"
            echo "Check 3: Running new test cases on mutant code..."
            gcc -I"$INCLUDE_DIR" "$mutant_file" "$new_test_case_file" -o "$MUTANT_NEW_RUN_EXEC"
            
            if [ $? -ne 0 ]; then
                 echo "FAIL: Mutant failed compile with new tests. DISCARD MUTANT :("
                 continue
            fi

            ./"$MUTANT_NEW_RUN_EXEC"
            if [ $? -eq 0 ]; then
                # Exit code 0 means tests passed (Mutant survived)
                echo "FAIL: Mutant passed the security test (Not Caught). DISCARD MUTANT :("
                echo "--------------------------------------------------------------------"
                continue
            else
                # Exit code non-zero means tests failed (Mutant Caught)
                echo "Mutant failed the new security test. VALID MUTANT FOUND! MUTANT KILLED. SUCCESS !!"
                echo "--------------------------------------------------------------------"
                
                # Optional: Move the successful artifacts to a 'saved' folder here
                # cp "$mutant_file" "./saved_mutants/${issue_name}_${base_code_filename}_mutant.c"
            fi

        else
            echo "EQUIVALENT MUTANT confirmed by LLM2 (Answer: $equi_ans). DISCARD THIS MUTANT :("
            continue
        fi
    done # End Inner Loop (Code)

done # End Outer Loop (Issues)

echo
echo "Script Process finished."
echo