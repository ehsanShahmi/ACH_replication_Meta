#!/bin/bash

# master_script.sh

# # --- 1. ARGUMENT PARSING ---
# if [ -z "$1" ]; then
#     echo "ERROR: No repository directory provided."
#     echo "Usage: $0 <path_to_repo_folder>"
#     exit 1
# fi

REPO_BASE_DIR="./CWEval/benchmark/core/c"

# Define the DIRECTORIES
SUMMARY_DIR="./security_issue_summaries2"
INCLUDE_DIR="./includes"
OUTPUT_DIR="./outputs"

# --- 2. PATH VALIDATION & SCRIPT DEFINITIONS ---
if [ ! -d "$REPO_BASE_DIR" ]; then
    echo "ERROR: The repository directory '$REPO_BASE_DIR' does not exist."
    exit 1
fi
if [ ! -d "$SUMMARY_DIR" ]; then
    echo "ERROR: Summary directory '$SUMMARY_DIR' not found."
    exit 1
fi

# Define the scripts inside
Mutator="./scripts/mutator.py"
eqChecker="./scripts/eqChecker.py"
sec_test_gen="./scripts/sec_test_gen.py"

echo "Whole script process started..."
echo "Target Repo: $REPO_BASE_DIR"
echo "-------------------------------------"

mkdir -p "$OUTPUT_DIR"

# --- 3. DATA COLLECTION ---
readarray -t summary_files < <(find "$SUMMARY_DIR" -maxdepth 1 -name "*-summary.txt" | sort)
readarray -t code_files < <(find "$REPO_BASE_DIR" -name "*_task.c" | sort)

NUM_SUMMARIES=${#summary_files[@]}
NUM_CODES=${#code_files[@]}

if [ "$NUM_SUMMARIES" -eq 0 ]; then
    echo "ERROR: No summary files found in $SUMMARY_DIR."
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

echo "Found ${NUM_SUMMARIES} summary files and ${NUM_CODES} task files."
echo "Running Nested Loop: Every Summary x Every Code Pair."
echo "-------------------------------------"

summary_count=0
# --- OUTER LOOP ---
for summary_file in "${summary_files[@]}"; do
    ((summary_count++))
    base_name=$(basename "$summary_file")
    issue_id=${base_name%-summary.txt}

    echo "############################################################"
    echo "[OUTER LOOP] Processing Summary $summary_count / $NUM_SUMMARIES : $issue_id"
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
        mutant_file=$(python3 "$Mutator" "$summary_file" "$current_code" "$existing_test_cases")
        
        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed. Continuing."
            continue
        else
            echo "Mutant generated successfully in $mutant_file. SUCCESS !!"
            ((TOTAL_MUTANTS_GENERATED++))
        fi

        # --- STAGE 1 VALIDATION (CORRECTED with Symbolic Link) ---
        echo "<---STAGE 1 VALIDATION: Use symbolic link to run existing test--->"
        
        # 1. Backup the original C file
        mv "$current_code" "${current_code}.bak"
        # 2. Create a symbolic link from the original's name to the mutant
        ln -s "$mutant_file" "$current_code"

        echo "Running existing Python test ('$(basename "$existing_test_cases")') on mutant via symlink..."
        # 3. Run the hardcoded test script (it will now use the mutant)
        python3 "$existing_test_cases"
        test_exit_code=$? # 4. Capture the exit code

        # 5. CRITICAL: Clean up by removing the link and restoring the backup
        rm "$current_code"
        mv "${current_code}.bak" "$current_code"
        
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
        equi_ans=$(python3 "$eqChecker" "$mutant_file" "$current_code")

        if [[ "$equi_ans" == "{no}"* ]]; then
            echo "Equivalency test returned {no}. SUCCESS !!"
            ((TOTAL_NON_EQUIVALENT_MUTANTS++))
            echo "(LLM3) New Test Case Generation initiated..."
            
            # New Test Case Generation
            new_test_case_file=$(python3 "$sec_test_gen" "$current_code" "$mutant_file" "$existing_test_cases")
            
            if [ $? -ne 0 ] || [ -z "$new_test_case_file" ]; then
                echo "ERROR: sec_test_gen script failed."
                continue
            fi
            echo "New test case generated: $new_test_case_file. SUCCESS !!"
            
            # --- STAGE 2 VALIDATION (CORRECTED with Direct Execution) ---
            echo "<---STAGE 2 VALIDATION: New Python test logic--->"
            
            # 1. Check if new test PASSES on ORIGINAL code (Exit code must be 0)
            echo "Check 1: Running new test on original code (expecting PASS)..."
            python3 "$new_test_case_file" "$current_code"
            if [ $? -ne 0 ]; then
                echo "FAIL: New test case failed on original code. DISCARD."
                continue
            fi
            echo "-> Success: New test passed on original code."

            # 2. Check if new test FAILS on MUTANT code (Exit code must be non-zero)
            echo "Check 2: Running new test on mutant code (expecting FAIL)..."
            python3 "$new_test_case_file" "$mutant_file"
            if [ $? -eq 0 ]; then
                echo "FAIL: Mutant PASSED the security test (Vulnerability not caught). DISCARD."
            else
                echo "-> Success: Mutant FAILED the new security test. VALID VULNERABILITY FOUND!"
                ((TOTAL_VALID_VULNERABILITIES_FOUND++))
            fi
            echo "--------------------------------------------------------------------"
        else
            echo "EQUIVALENT MUTANT confirmed by LLM2. DISCARD."
        fi
    done # End Inner Loop

done # End Outer Loop

# ==========================================
# FINAL STATISTICAL REPORT
# ==========================================

if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
    PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_MUTANTS_GENERATED) * 100}")
    PERC_NON_EQUIV=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NON_EQUIVALENT_MUTANTS / $TOTAL_MUTANTS_BUILDABLE_AND_PASS) * 100}")
else
    PERC_BUILD_PASS="0.00"
    PERC_NON_EQUIV="0.00"
fi

# Add this line
REPORT_FILE="$OUTPUT_DIR/final_report_summaries2.txt"
# ==========================================
# FINAL STATISTICAL REPORT
# ==========================================
# Perform the percentage calculations first
if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ] && [ "$TOTAL_MUTANTS_BUILDABLE_AND_PASS" -gt 0 ]; then
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
    echo "Total Summaries Processed: $NUM_SUMMARIES"
    echo "Total Code/Test Pairs Processed: $TOTAL_PAIRS_FOUND"
    echo "--------------------------------------------------------"
    echo "1. Total Mutants Generated: $TOTAL_MUTANTS_GENERATED"
    echo "2. Mutants that Build & Pass Existing Tests: $TOTAL_MUTANTS_BUILDABLE_AND_PASS ($PERC_BUILD_PASS %)"
    echo "3. Non-Equivalent Mutants (Confirmed by LLM): $TOTAL_NON_EQUIVALENT_MUTANTS ($PERC_NON_EQUIV %)"
    echo "--------------------------------------------------------"
    echo "4. Final Valid Vulnerabilities Found (Killed): $TOTAL_VALID_VULNERABILITIES_FOUND"
    echo "========================================================"
) | tee -a "$REPORT_FILE"

echo
echo "Script Process finished."
echo "Final report also saved to: $REPORT_FILE"
echo