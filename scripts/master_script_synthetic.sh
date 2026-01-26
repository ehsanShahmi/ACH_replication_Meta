#!/bin/bash

# master_script.sh

# --- 1. ARGUMENT PARSING ---
if [ -z "$1" ]; then
    echo "ERROR: No repository directory provided."
    echo "Usage: $0 <path_to_repo_folder>"
    exit 1
fi

REPO_BASE_DIR="${1%/}"

# Define the DIRECTORIES
SUMMARY_DIR="./security_issue_summaries1"
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
# Collect all SUMMARY files (e.g., CWE-119-summary.txt)
readarray -t summary_files < <(find "$SUMMARY_DIR" -maxdepth 1 -name "*-summary.txt" | sort)

# Collect all C code TASK files from the repo, searching recursively
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
# --- OUTER LOOP: Iterate through each SUMMARY file ---
for summary_file in "${summary_files[@]}"; do
    ((summary_count++))
    
    base_name=$(basename "$summary_file")
    issue_id=${base_name%-summary.txt}

    echo "############################################################"
    echo "[OUTER LOOP] Processing Summary $summary_count / $NUM_SUMMARIES : $issue_id"
    echo "############################################################"

    # --- INNER LOOP: Iterate through each discovered CODE file ---
    for current_code in "${code_files[@]}"; do
        
        # --- Simplified Pairing Logic ---
        # Derive the expected test case path from the current code path.
        # Example: './CWEval/c/cwe_078/cwe_078_0_c_task.c' -> './CWEval/c/cwe_078/cwe_078_0_c_test.c'
        existing_test_cases="${current_code/_task.c/_test.c}"

        # If the corresponding test file doesn't exist, this is not a valid pair.
        if [ ! -f "$existing_test_cases" ]; then
            continue # Silently skip to the next code file.
        fi

        ((TOTAL_PAIRS_FOUND++))

        echo "========================================================"
        echo "   [INNER LOOP] Applying '$issue_id' to '$(basename "$current_code")'"
        echo "========================================================"

        # 1. Mutator (Passes summary file path, code path, test path)
        echo "(LLM1) Generating a mutant for $(basename "$current_code")..."
        mutant_file=$(python3 "$Mutator" "$summary_file" "$current_code" "$existing_test_cases")
        
        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed. Continuing."
            continue
        else
            echo "Mutant generated successfully in $mutant_file. SUCCESS !!"
            ((TOTAL_MUTANTS_GENERATED++))
        fi

        # --- The rest of your validation pipeline remains exactly the same ---
        
        echo "<---STAGE 1 VALIDATION: buildable and passes existing tests--->"
        echo "--------------------------------------------------------------------"
        TEST_RUNNER_EXEC="$OUTPUT_DIR/test_runner"
        
        # COMPILE and RUN existing tests against the MUTANT
        gcc -w -I"$INCLUDE_DIR" "$mutant_file" "$existing_test_cases" -o "$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
            echo "COMPILATION FAILED: Non-buildable mutant. DISCARD."
            continue
        fi
        ./"$TEST_RUNNER_EXEC"
        if [ $? -ne 0 ]; then
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
            
            if [ $? -ne 0 ]; then
                echo "ERROR: sec_test_gen script failed."
                continue
            fi
            echo "New test case generated: $new_test_case_file. SUCCESS !!"
            
            echo "<---STAGE 2 VALIDATION: New tests logic--->"
            echo "--------------------------------------------------------------------"
            
            ORIGINAL_RUN_EXEC="$OUTPUT_DIR/original_test_run"
            gcc -w -I"$INCLUDE_DIR" "$current_code" "$new_test_case_file" -o "$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: Original code failed to compile with new tests. DISCARD."
                continue
            fi
            ./"$ORIGINAL_RUN_EXEC"
            if [ $? -ne 0 ]; then
                echo "FAIL: New test cases failed on original code. DISCARD."
                continue
            fi

            MUTANT_NEW_RUN_EXEC="$OUTPUT_DIR/mutant_new_test_run"
            gcc -w -I"$INCLUDE_DIR" "$mutant_file" "$new_test_case_file" -o "$MUTANT_NEW_RUN_EXEC"
            if [ $? -ne 0 ]; then
                 echo "FAIL: Mutant failed compile with new tests. DISCARD."
                 continue
            fi
            ./"$MUTANT_NEW_RUN_EXEC"
            if [ $? -eq 0 ]; then
                echo "FAIL: Mutant passed the security test (Not Caught). DISCARD."
            else
                echo "Mutant failed the new security test. VALID MUTANT FOUND! SUCCESS !!"
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

echo
echo "========================================================"
echo "              FINAL STATISTICAL REPORT                  "
echo "========================================================"
echo "Target Directory: $REPO_BASE_DIR"
echo "Total Summaries Processed: $NUM_SUMMARIES"
echo "Total Code/Test Pairs Processed: $TOTAL_PAIRS_FOUND"
echo "--------------------------------------------------------"
echo "1. Total Mutants Generated: $TOTAL_MUTANTS_GENERATED"
echo "2. Mutants that Build & Pass Existing Tests: $TOTAL_MUTANTS_BUILDABLE_AND_PASS"
echo "   -> Success Rate (Stage 1): $PERC_BUILD_PASS %"
echo "3. Non-Equivalent Mutants (Confirmed by LLM): $TOTAL_NON_EQUIVALENT_MUTANTS"
echo "   -> Non-Equivalence Rate (out of buildable and passable) mutants: $PERC_NON_EQUIV %"
echo "--------------------------------------------------------"
echo "4. Final Valid Vulnerabilities Found (Killed): $TOTAL_VALID_VULNERABILITIES_FOUND"
echo "========================================================"
echo
echo "Script Process finished."
echo