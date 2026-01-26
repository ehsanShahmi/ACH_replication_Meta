#!/bin/bash

# master_script.sh
# Usage: ./master_script.sh CWE-119

# --- 1. ARGUMENT PARSING ---
if [ -z "$1" ]; then
    echo "ERROR: No issue folder name provided."
    echo "Usage: $0 <CWE-folder-name>   e.g.  $0 CWE-119"
    exit 1
fi

ISSUE_FOLDER_NAME="$1"

# --- 2. DIRECTORY DEFINITIONS ---
REPO_BASE_DIR="./CWEval/benchmark/core/c"
ISSUE_DIR="./security_issues_FINAL/$ISSUE_FOLDER_NAME"
INCLUDE_DIR="./includes"
OUTPUT_DIR="$REPO_BASE_DIR/$ISSUE_FOLDER_NAME"

# Create output directory for the CWE if it doesn’t exist
mkdir -p "$OUTPUT_DIR"

# --- 3. PATH VALIDATION ---
if [ ! -d "$REPO_BASE_DIR" ]; then
    echo "ERROR: The repository directory '$REPO_BASE_DIR' does not exist."
    exit 1
fi
if [ ! -d "$ISSUE_DIR" ]; then
    echo "ERROR: The issue directory '$ISSUE_DIR' does not exist."
    exit 1
fi

# --- 4. SCRIPT PATHS ---
Mutator="scripts/mutator.py"
eqChecker="scripts/eqChecker.py"
sec_test_gen="scripts/sec_test_gen.py"

echo "Whole script process started..."
echo "Target Repo: $REPO_BASE_DIR"
echo "Issue Folder: $ISSUE_DIR"
echo "Output Folder: $OUTPUT_DIR"
echo "-------------------------------------"

# --- 5. DATA COLLECTION ---
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*issue*.txt" | sort)
readarray -t code_files < <(find "$REPO_BASE_DIR" -name "*_task.c" | sort)

NUM_SUMMARIES=${#issue_files[@]}
NUM_CODES=${#code_files[@]}

if [ "$NUM_SUMMARIES" -eq 0 ]; then
    echo "ERROR: No issue files found in $ISSUE_DIR."
    exit 1
fi
if [ "$NUM_CODES" -eq 0 ]; then
    echo "ERROR: No '*_task.c' files found in $REPO_BASE_DIR."
    exit 1
fi

# ==========================================
# STATISTICAL COUNTERS INITIALIZATION
# ==========================================
TOTAL_PAIRS_FOUND=0
TOTAL_MUTANTS_GENERATED=0
TOTAL_MUTANTS_BUILDABLE_AND_PASS=0
TOTAL_NON_EQUIVALENT_MUTANTS=0
TOTAL_VALID_VULNERABILITIES_FOUND=0

echo "Found ${NUM_SUMMARIES} issue files and ${NUM_CODES} task files."
echo "Running Nested Loop: Every issue x Every Code Pair."
echo "-------------------------------------"

issue_count=0
# --- OUTER LOOP ---
for issue_file in "${issue_files[@]}"; do
    ((issue_count++))
    base_name=$(basename "$issue_file")
    issue_id=${base_name%-issue.txt}

    echo "############################################################"
    echo "[OUTER LOOP] Processing issue $issue_count / $NUM_SUMMARIES : $issue_id"
    echo "############################################################"

    # --- INNER LOOP ---
    for current_code in "${code_files[@]}"; do
        
        existing_test_cases="${current_code/_task.c/_test.py}"
        if [ ! -f "$existing_test_cases" ]; then
            continue
        fi

        ((TOTAL_PAIRS_FOUND++))

        echo "========================================================"
        echo "   [INNER LOOP] Applying '$issue_id' to '$(basename "$current_code")'"
        echo "========================================================"

        # 1. Mutator
        echo "(LLM1) Generating a mutant for $(basename "$current_code")..."
        mutant_file=$(python3 "$Mutator" "$issue_file" "$current_code" "$existing_test_cases" "$OUTPUT_DIR")
        
        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed. Continuing."
            continue
        else
            echo "Mutant generated successfully in $mutant_file. SUCCESS !!"
            ((TOTAL_MUTANTS_GENERATED++))
        fi

        # --- STAGE 1 VALIDATION: Mutant against existing test case ---
        echo "<---STAGE 1 VALIDATION: Mutant against existing test--->"
        cd "$REPO_BASE_DIR"

        TASK_BASENAME=$(basename "$current_code")
        TEST_BASENAME=$(basename "$existing_test_cases")
        MUTANT_ABS_PATH="../../../../$mutant_file"  # relative from $REPO_BASE_DIR

        # Backup the original task file
        mv "$TASK_BASENAME" "$TASK_BASENAME.bak"

        # Copy mutant over as the main task file
        cp "$MUTANT_ABS_PATH" "$TASK_BASENAME"

        # Recompile code and (optional) _unsafe
        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}"
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe"

        pytest -q "$TEST_BASENAME"
        test_exit_code=$?

        rm "$TASK_BASENAME"
        mv "$TASK_BASENAME.bak" "$TASK_BASENAME"
        cd - >/dev/null

        if [ $test_exit_code -ne 0 ]; then
            echo "TESTS FAILED: Mutant killed by existing tests. DISCARD."
            continue
        else
            echo "TESTS PASSED: Mutant passes existing tests. SUCCESS !!"
            ((TOTAL_MUTANTS_BUILDABLE_AND_PASS++))
        fi
        echo "--------------------------------------------------------------------"
            
        # RUN EQUIVALENCY CHECKER
        echo "(LLM2) Equivalency Checker initiated..."
        equi_ans=$(python3 "$eqChecker" "$mutant_file" "$current_code" "$OUTPUT_DIR")

        if [[ "$equi_ans" == "{no}"* ]]; then
            echo "Equivalency test returned {no}. SUCCESS !!"
            ((TOTAL_NON_EQUIVALENT_MUTANTS++))
            echo "(LLM3) New Test Case Generation initiated..."
            
            # New Test Case Generation
            new_test_case_file=$(python3 "$sec_test_gen" "$current_code" "$existing_test_cases" "$mutant_file" "$OUTPUT_DIR")
            
            if [ $? -ne 0 ] || [ -z "$new_test_case_file" ]; then
                echo "ERROR: sec_test_gen script failed."
                continue
            fi
            echo "New test case generated: $new_test_case_file. SUCCESS !!"

            # --- STAGE 2: New test against original code ---
            echo "<---STAGE 2 VALIDATION: New test against original code (expect PASS)--->"
            cd "$REPO_BASE_DIR"

            # Backup the original test file
            mv "$TEST_BASENAME" "$TEST_BASENAME.bak"

            # Copy new test suite into place
            cp "../../../../$new_test_case_file" "$TEST_BASENAME"

            # Recompile original code and (optional) _unsafe
            gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}"
            [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe"

            pytest -v "$TEST_BASENAME"
            orig_test_exit_code=$?

            rm "$TEST_BASENAME"
            mv "$TEST_BASENAME.bak" "$TEST_BASENAME"
            cd - >/dev/null

            if [ $orig_test_exit_code -ne 0 ]; then
                echo "FAIL: New test case failed on original code. DISCARD."
                continue
            fi
            echo "-> Success: New test passed on original code."

                        # --- STAGE 3: New test against mutant code ---
            echo "<---STAGE 3 VALIDATION: New test against mutant code (expect FAIL) --->"
            cd "$REPO_BASE_DIR"

            # Backup original task file again
            mv "$TASK_BASENAME" "$TASK_BASENAME.bak"
            cp "$MUTANT_ABS_PATH" "$TASK_BASENAME"

            # Backup test file again
            mv "$TEST_BASENAME" "$TEST_BASENAME.bak"
            cp "../../../../$new_test_case_file" "$TEST_BASENAME"

            # Recompile mutant code and (optional) _unsafe
            gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}"
            [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe"

            pytest -v "$TEST_BASENAME"
            mutant_test_exit_code=$?

            # Restore both originals
            rm "$TASK_BASENAME"
            mv "$TASK_BASENAME.bak" "$TASK_BASENAME"
            rm "$TEST_BASENAME"
            mv "$TEST_BASENAME.bak" "$TEST_BASENAME"
            cd - >/dev/null

            if [ $mutant_test_exit_code -eq 0 ]; then
                echo "FAIL: Mutant PASSED the security test (Vulnerability not caught). DISCARD."
            else
                echo "-> Success: Mutant FAILED the new security test. VALID VULNERABILITY FOUND!"
                ((TOTAL_VALID_VULNERABILITIES_FOUND++))
            fi
            echo "--------------------------------------------------------------------"
        else
            echo "EQUIVALENT MUTANT confirmed by LLM2. DISCARD."
        fi
    done
done

# ==========================================
# FINAL STATISTICAL REPORT
# ==========================================
REPORT_FILE="$OUTPUT_DIR/final_report_$1.txt"

if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
    PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_MUTANTS_GENERATED) * 100}")
    PERC_NON_EQUIV=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NON_EQUIVALENT_MUTANTS / $TOTAL_MUTANTS_BUILDABLE_AND_PASS) * 100}")
else
    PERC_BUILD_PASS="0.00"
    PERC_NON_EQUIV="0.00"
fi

(
    echo
    echo "========================================================"
    echo "              FINAL STATISTICAL REPORT                  "
    echo "========================================================"
    echo "Target Directory: $REPO_BASE_DIR"
    echo "Issue Source Directory: $ISSUE_DIR"
    echo "Output Directory: $OUTPUT_DIR"
    echo "--------------------------------------------------------"
    echo "Total Issues Processed: $NUM_SUMMARIES"
    echo "Total Code/Test Pairs Processed: $TOTAL_PAIRS_FOUND"
    echo "--------------------------------------------------------"
    echo "1. Total Mutants Generated: $TOTAL_MUTANTS_GENERATED"
    echo "2. Mutants that Build & Pass Existing Tests: $TOTAL_MUTANTS_BUILDABLE_AND_PASS ($PERC_BUILD_PASS %)"
    echo "3. Non-Equivalent Mutants (Confirmed by LLM): $TOTAL_NON_EQUIV_MUTANTS ($PERC_NON_EQUIV %)"
    echo "--------------------------------------------------------"
    echo "4. Final Valid Vulnerabilities Found (Killed): $TOTAL_VALID_VULNERABILITIES_FOUND"
    echo "========================================================"
) | tee -a "$REPORT_FILE"

echo
echo "Script Process finished."
echo "Final report saved to: $REPORT_FILE"
echo