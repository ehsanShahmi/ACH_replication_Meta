#!/bin/bash

# master_script.sh
# Usage: ./master_script.sh CWE-119 [skip_issues.csv]
#
# Optional second argument: path to a CSV file containing issue IDs to skip
# when processing cwe_020_0_c_task.c (one issue ID per line, e.g. "issue_1").
# All other (issue, source) pairs are unaffected and run normally.

# --- 1. ARGUMENT PARSING ---
if [ -z "$1" ]; then
    echo "ERROR: No issue folder name provided."
    echo "Usage: $0 <CWE-folder-name>   e.g.  $0 CWE-119"
    exit 1
fi

ISSUE_FOLDER_NAME="$1"

# --- SKIP-LIST CONFIG (HARDCODED) ---
SKIP_SOURCE_NAME="cwe_020_0_c_task.c"
SKIP_CSV="sample_done_issue_list.csv"  # Hardcoded path
declare -A skip_set

# --- 2. DIRECTORY DEFINITIONS ---
REPO_BASE_DIR="./CWEval/benchmark/core/c"
ISSUE_DIR="./security_issues_FINAL_v5_with_cwe/$ISSUE_FOLDER_NAME"
OUTPUT_DIR="$REPO_BASE_DIR/$ISSUE_FOLDER_NAME"

# Sub-folder definitions
FAILED_MUTANTS_DIR="$OUTPUT_DIR/incorrect-failed-mutants"
NON_EQ_DIR="$OUTPUT_DIR/non-eq-$ISSUE_FOLDER_NAME"       # created by eqCheckerFolder_v2.py
NEW_TESTS_DIR="$OUTPUT_DIR/new-tests-$ISSUE_FOLDER_NAME"  # created by sec_test_gen.py
declare -a VALID_NEWTEST_ENTRIES=()

# Create required directories upfront
mkdir -p "$OUTPUT_DIR"
mkdir -p "$FAILED_MUTANTS_DIR"
mkdir -p "$NEW_TESTS_DIR"

# --- [SAFETY CHANGE] CLEANUP AND RECOVERY LOGIC ---
cleanup() {
    # This runs on Ctrl+C or script exit to ensure files aren't lost
    find "$REPO_BASE_DIR" -maxdepth 1 -name "*.bak" | while read -r bak_file; do
        original="${bak_file%.bak}"
        mv -f "$bak_file" "$original" 2>/dev/null
    done
}
trap cleanup SIGINT SIGTERM EXIT

# If previous run crashed, recover files now
if find "$REPO_BASE_DIR" -maxdepth 1 -name "*.bak" -quit | grep -q .; then
    echo "Found leftover .bak files from a previous run. Recovering originals..."
    cleanup
fi

# --- 3. PATH VALIDATION ---
if [ ! -d "$REPO_BASE_DIR" ]; then
    echo "ERROR: The repository directory '$REPO_BASE_DIR' does not exist."
    exit 1
fi
if [ ! -d "$ISSUE_DIR" ]; then
    echo "ERROR: The issue directory '$ISSUE_DIR' does not exist."
    exit 1
fi

# Logging everything in a log file
FULL_LOG="$OUTPUT_DIR/output_log-$ISSUE_FOLDER_NAME.log"
exec > >(tee -i "$FULL_LOG") 2>&1
echo "============================================================"
echo "STARTING PROCESS FOR $ISSUE_FOLDER_NAME"
echo "Log file: $FULL_LOG"
echo "============================================================"

# --- 4. SKIP-LIST LOADING ---
# Reads the CSV (one issue ID per row, ignores blank lines and # comments)
# and populates skip_set. Only applies to SKIP_SOURCE_NAME at runtime.
if [ -n "$SKIP_CSV" ]; then
    if [ ! -f "$SKIP_CSV" ]; then
        echo "ERROR: Skip-list CSV not found: '$SKIP_CSV'"
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip leading/trailing whitespace and Windows carriage returns
        trimmed=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\.txt$//')
        # Skip blank lines and comment lines starting with #
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        skip_set["$trimmed"]=1
    done < "$SKIP_CSV"
    echo "Skip-list loaded: ${#skip_set[@]} issue(s) will be skipped for '$SKIP_SOURCE_NAME'"
    echo "  (CSV: $SKIP_CSV)"
else
    echo "No skip-list CSV provided. All (issue, source) pairs will be processed."
fi

# --- 5. SCRIPT PATHS ---
Mutator="scripts/mutator.py"
eqCheckerFolder="scripts/eqCheckerFolder_v2.py"
sec_test_gen="scripts/sec_test_gen.py"

echo "Whole script process started..."
echo "Target Repo:              $REPO_BASE_DIR"
echo "Issue Folder:             $ISSUE_DIR"
echo "Output Folder:            $OUTPUT_DIR"
echo "  ├── Valid Mutants:      $OUTPUT_DIR  (root *.c files)"
echo "  ├── Failed Mutants:     $FAILED_MUTANTS_DIR"
echo "  ├── Non-EQ Mutants:     $NON_EQ_DIR  (created by eqCheckerFolder)"
echo "  └── New Tests:          $NEW_TESTS_DIR  (created by sec_test_gen)"
echo "-------------------------------------"

# --- 6. DATA COLLECTION ---
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*issue*.txt" | sort)
readarray -t code_files  < <(find "$REPO_BASE_DIR" -maxdepth 1 -name "*_task.c" | sort)

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
# STATISTICAL COUNTERS
# ==========================================
TOTAL_PAIRS_FOUND=0
TOTAL_PAIRS_SKIPPED=0
TOTAL_MUTANTS_GENERATED=0
TOTAL_MUTANTS_BUILDABLE_AND_PASS=0
TOTAL_MUTANTS_FAILED=0
TOTAL_NON_EQUIVALENT_MUTANTS=0
TOTAL_NEWTESTS_GENERATED=0
TOTAL_NEWTESTS_STAGE2_PASSED=0  
TOTAL_VALID_VULNERABILITIES_FOUND=0

echo "Found ${NUM_SUMMARIES} issue files and ${NUM_CODES} task files."
echo "============================================================"
echo "  PHASE 1: MUTANT GENERATION"
echo "  Running N x M loop: Every issue x Every Code Pair"
echo "============================================================"

issue_count=0

# ===========================================================
# PHASE 1: MUTANT GENERATION — N x M nested loop
# ===========================================================
for issue_file in "${issue_files[@]}"; do
    ((issue_count++))
    base_name=$(basename "$issue_file")
    issue_id=${base_name%.txt}

    echo "############################################################"
    echo "[PHASE 1 - OUTER] Issue $issue_count / $NUM_SUMMARIES : $issue_id"
    echo "############################################################"

    for current_code in "${code_files[@]}"; do

        existing_test_cases="${current_code/_task.c/_test.py}"
        if [ ! -f "$existing_test_cases" ]; then
            continue
        fi

        ((TOTAL_PAIRS_FOUND++))

        current_basename=$(basename "$current_code")
        if [[ "$current_basename" == "$SKIP_SOURCE_NAME" ]] && \
           [[ -n "${skip_set[$issue_id]+_}" ]]; then
            echo "  [SKIP] '$issue_id' x '$current_basename' — found in skip-list. Skipping."
            ((TOTAL_PAIRS_SKIPPED++))
            continue
        fi

        echo "========================================================"
        echo "  [PAIR] '$issue_id' x '$current_basename'"
        echo "========================================================"

        # --- Step 1: Generate mutant directly into OUTPUT_DIR ---
        echo "(LLM1) Generating mutant for $current_basename..."
        mutant_file=$(python3 "$Mutator" "$issue_file" "$current_code" "$existing_test_cases" "$OUTPUT_DIR")

        if [ $? -ne 0 ] || [ -z "$mutant_file" ]; then
            echo "ERROR: Mutator script failed. Skipping pair."
            continue
        fi
        echo "Mutant generated: $mutant_file"
        ((TOTAL_MUTANTS_GENERATED++))

        # --- Step 2: Stage 1 Validation ---
        echo "<--- STAGE 1: Mutant vs existing tests (expect PASS) --->"
        cd "$REPO_BASE_DIR"
        mkdir -p ./compiled

        TASK_BASENAME=$(basename "$current_code")
        TEST_BASENAME=$(basename "$existing_test_cases")
        MUTANT_REL_PATH="../../../../$mutant_file"

        # [SAFETY] Swap mutant in using backups
        cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
        cp "$MUTANT_REL_PATH" "$TASK_BASENAME"

        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        compile_exit=$?
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%.c}_unsafe" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        if [ $compile_exit -eq 0 ]; then
            pytest -v --timeout=300 "$TEST_BASENAME"
            test_exit_code=$?
        else
            echo "COMPILE FAILED for mutant."
            test_exit_code=1
        fi

        # [SAFETY] Restore original task file immediately
        mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
        cd - >/dev/null

        if [ $test_exit_code -ne 0 ]; then
            echo "DISCARD: Mutant failed to compile or was killed by existing tests."
            echo "  → Moving to $FAILED_MUTANTS_DIR"
            mv "$mutant_file" "$FAILED_MUTANTS_DIR/"
            ((TOTAL_MUTANTS_FAILED++))
            continue
        fi

        echo "PASS: Mutant survives existing tests → kept in $OUTPUT_DIR"
        ((TOTAL_MUTANTS_BUILDABLE_AND_PASS++))
        echo "--------------------------------------------------------------------"

    done
done

echo
echo "============================================================"
echo "  PHASE 1 COMPLETE"
echo "  Valid mutants in:       $OUTPUT_DIR  (*.c files)"
echo "  Failed mutants in:      $FAILED_MUTANTS_DIR"
echo "  Total pairs found:      $TOTAL_PAIRS_FOUND"
echo "  Pairs skipped (CSV):    $TOTAL_PAIRS_SKIPPED"
echo "  Total generated:        $TOTAL_MUTANTS_GENERATED"
echo "  Buildable & pass tests: $TOTAL_MUTANTS_BUILDABLE_AND_PASS"
echo "  Failed/non-buildable:   $TOTAL_MUTANTS_FAILED"
echo "============================================================"
echo


# ===========================================================
# PHASE 2: EQUIVALENCY CHECKING
# ===========================================================
echo "============================================================"
echo "  PHASE 2: EQUIVALENCY CHECKING (folder-level)"
echo "  Input folder:  $OUTPUT_DIR"
echo "  Output folder: $NON_EQ_DIR  (created by eqCheckerFolder)"
echo "============================================================"

valid_mutant_count=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.c" | wc -l)

if [ "$valid_mutant_count" -eq 0 ]; then
    echo "WARNING: No valid mutant .c files in $OUTPUT_DIR. Skipping equivalency check."
else
    echo "Running eqCheckerFolder_v2.py on $valid_mutant_count mutant(s)..."
    python3 "$eqCheckerFolder" "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        echo "ERROR: eqCheckerFolder_v2.py failed."
        exit 1
    fi
    echo "Equivalency checking complete."
fi

readarray -t non_eq_mutants < <(find "$NON_EQ_DIR" -maxdepth 1 -name "*.c" 2>/dev/null | sort)
TOTAL_NON_EQUIVALENT_MUTANTS=${#non_eq_mutants[@]}

echo
echo "============================================================"
echo "  PHASE 2 COMPLETE"
echo "  Non-equivalent mutants: $TOTAL_NON_EQUIVALENT_MUTANTS"
echo "  Saved to: $NON_EQ_DIR"
echo "============================================================"
echo


# ===========================================================
# PHASE 3 & 4: NEW TEST GENERATION + VALIDATION
# ===========================================================
echo "============================================================"
echo "  PHASE 3 & 4: NEW TEST GENERATION + VALIDATION"
echo "============================================================"

if [ "$TOTAL_NON_EQUIVALENT_MUTANTS" -eq 0 ]; then
    echo "WARNING: No non-equivalent mutants found. Skipping test generation."
else

    for non_eq_mutant in "${non_eq_mutants[@]}"; do
        mutant_basename=$(basename "$non_eq_mutant")

        echo "###########################################################"
        echo "  [NON-EQ MUTANT] $mutant_basename"
        echo "###########################################################"

        no_ext="${mutant_basename%.c}"
        stripped="${no_ext#${ISSUE_FOLDER_NAME}_}"
        issue_and_task="${stripped%_mutant}"
        task_stem=$(echo "$issue_and_task" | sed 's/^issue_[0-9]*_//')

        current_code="$REPO_BASE_DIR/${task_stem}.c"
        existing_test_cases="$REPO_BASE_DIR/${task_stem/_task/_test}.py"

        if [ ! -f "$current_code" ]; then
            echo "WARNING: Source file not found: '$current_code'. Skipping."
            continue
        fi
        if [ ! -f "$existing_test_cases" ]; then
            echo "WARNING: Test file not found: '$existing_test_cases'. Skipping."
            continue
        fi

        echo "  Source:        $current_code"
        echo "  Existing test: $existing_test_cases"
        echo "  Mutant:        $non_eq_mutant"

        TASK_BASENAME=$(basename "$current_code")
        TEST_BASENAME=$(basename "$existing_test_cases")

        echo "(LLM3) Generating new test cases..."
        sec_test_output=$(timeout 300s python3 "$sec_test_gen" "$current_code" "$existing_test_cases" "$non_eq_mutant" "$OUTPUT_DIR")
        if [ $? -ne 0 ] || [ $? -eq 124 ] || [ -z "$sec_test_output" ]; then
            echo "  ERROR: LLM3 (sec_test_gen) Timed out or failed for $mutant_basename. Skipping."
            continue
        fi
        ((TOTAL_NEWTESTS_GENERATED++))

        newtest_1_file=$(echo "$sec_test_output" | sed -n '1p')
        newtest_2_file=$(echo "$sec_test_output" | sed -n '2p')

        if [ ! -f "$newtest_1_file" ]; then
            echo "ERROR: newtest_1 not found at '$newtest_1_file'. Skipping."
            continue
        fi
        if [ ! -f "$newtest_2_file" ]; then
            echo "ERROR: newtest_2 not found at '$newtest_2_file'. Skipping."
            continue
        fi

        echo "  newtest_1 (vs original): $newtest_1_file"
        echo "  newtest_2 (vs mutant):   $newtest_2_file"

        # Stage 2: newtest_1 vs ORIGINAL source
        echo "<--- STAGE 2: newtest_1 vs original source (expect PASS) --->"
        cd "$REPO_BASE_DIR"
        mkdir -p ./compiled

        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        stage2_compile_exit=$?
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%.c}_unsafe" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        if [ $stage2_compile_exit -ne 0 ]; then
            echo "DISCARD: newtest_1 discarded for non-buildable (Original source failed to compile)."
            cd - >/dev/null
            continue
        fi

        # [SAFETY] Backup test
        cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
        cd - >/dev/null
        cp "$newtest_1_file" "$REPO_BASE_DIR/$TEST_BASENAME"
        cd "$REPO_BASE_DIR"

        pytest -v --timeout=300 "$TEST_BASENAME"
        stage2_pytest_exit=$?

        # [SAFETY] Restore original test
        mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
        cd - >/dev/null

        if [ $stage2_pytest_exit -ne 0 ]; then
            echo "DISCARD: newtest_1 FAILED on original source."
            continue
        fi
        
        echo "PASS: newtest_1 passed on original source."
        ((TOTAL_NEWTESTS_STAGE2_PASSED++))
        echo "--------------------------------------------------------------------"


        # Stage 3: newtest_2 vs MUTANT
        echo "<--- STAGE 3: newtest_2 vs mutant (expect FAIL) --->"
        cd "$REPO_BASE_DIR"
        mkdir -p ./compiled

        # [SAFETY] Backup task and test
        cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
        cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
        cd - >/dev/null
        cp "$non_eq_mutant" "$REPO_BASE_DIR/$TASK_BASENAME"
        cp "$newtest_2_file" "$REPO_BASE_DIR/$TEST_BASENAME"
        cd "$REPO_BASE_DIR"

        # --- SYNTAX CHECK FOR NEWTEST_2 ---
        python3 -m py_compile "$TEST_BASENAME" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "DISCARD: newtest_2 discarded due to SYNTAX ERROR in generated test."
            mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
            mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
            cd - >/dev/null
            continue
        fi

        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        stage3_compile_exit=$?
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%.c}_unsafe" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        if [ $stage3_compile_exit -ne 0 ]; then
            echo "DISCARD: newtest_2 discarded for non-buildable (Mutant failed to compile)."
            mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
            mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
            cd - >/dev/null
            continue
        fi

        pytest -v --timeout=300 "$TEST_BASENAME"
        stage3_pytest_exit=$?

        # [SAFETY] Restore both
        mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
        mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
        cd - >/dev/null

        if [ $stage3_pytest_exit -eq 0 ]; then
            echo "DISCARD: newtest_2 PASSED on mutant — vulnerability not caught."
        else
            echo "SUCCESS: newtest_2 FAILED on mutant — VALID VULNERABILITY FOUND!"
            ((TOTAL_VALID_VULNERABILITIES_FOUND++))
            VALID_NEWTEST_ENTRIES+=("$(basename "$non_eq_mutant") | $(basename "$newtest_2_file")")

            # --- MOVE FINAL TESTS TO tool-new-tests SUBFOLDER ---
            mkdir -p "$NEW_TESTS_DIR/tool-new-tests"
            mv "$newtest_1_file" "$newtest_2_file" "$NEW_TESTS_DIR/tool-new-tests/"
        fi
        echo "--------------------------------------------------------------------"

    done
fi


# ==========================================
# FINAL STATISTICAL REPORT (EXACT COPY)
# ==========================================
REPORT_FILE="$OUTPUT_DIR/final_report_$ISSUE_FOLDER_NAME.txt"

if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
    PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_MUTANTS_GENERATED) * 100}")
else
    PERC_BUILD_PASS="0.00"
fi

if [ "$TOTAL_MUTANTS_BUILDABLE_AND_PASS" -gt 0 ]; then
    PERC_NON_EQUIV=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NON_EQUIVALENT_MUTANTS / $TOTAL_MUTANTS_BUILDABLE_AND_PASS) * 100}")
else
    PERC_NON_EQUIV="0.00"
fi

if [ "$TOTAL_NEWTESTS_GENERATED" -gt 0 ]; then
    PERC_FINAL_NEWTESTS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_VALID_VULNERABILITIES_FOUND / $TOTAL_NEWTESTS_GENERATED) * 100}")
else
    PERC_FINAL_NEWTESTS="0.00"
fi

(
    echo
    echo "========================================================"
    echo "              FINAL STATISTICAL REPORT                  "
    echo "========================================================"
    echo "Target Directory:         $REPO_BASE_DIR"
    echo "Issue Source Directory:   $ISSUE_DIR"
    echo "Output Directory:         $OUTPUT_DIR"
    echo "  ├── Valid Mutants:      $OUTPUT_DIR  (*.c)"
    echo "  ├── Failed Mutants:     $FAILED_MUTANTS_DIR"
    echo "  ├── Non-EQ Mutants:     $NON_EQ_DIR"
    echo "  └── New Tests:          $NEW_TESTS_DIR"
    echo "--------------------------------------------------------"
    echo "Skip-list source: $SKIP_SOURCE_NAME"
    echo "Skip-list CSV:    ${SKIP_CSV:-'(none)'}"
    echo "Pairs skipped:    $TOTAL_PAIRS_SKIPPED"
    echo "--------------------------------------------------------"
    echo "Total Issues Processed:               $NUM_SUMMARIES"
    echo "Total Code/Test Pairs Found:          $TOTAL_PAIRS_FOUND"
    echo "Total Code/Test Pairs Skipped:        $TOTAL_PAIRS_SKIPPED"
    echo "Total Code/Test Pairs Run:            $(( TOTAL_PAIRS_FOUND - TOTAL_PAIRS_SKIPPED ))"
    echo "--------------------------------------------------------"
    echo "PHASE 1 — Mutant Generation:"
    echo "  Total Mutants Generated:            $TOTAL_MUTANTS_GENERATED"
    echo "  Buildable & Pass Existing Tests:    $TOTAL_MUTANTS_BUILDABLE_AND_PASS ($PERC_BUILD_PASS %)"
    echo "  Failed / Non-buildable (discarded): $TOTAL_MUTANTS_FAILED"
    echo "--------------------------------------------------------"
    echo "PHASE 2 — Equivalency Checking:"
    echo "  Non-Equivalent Mutants:             $TOTAL_NON_EQUIVALENT_MUTANTS ($PERC_NON_EQUIV %)"
    echo "--------------------------------------------------------"
    echo "PHASE 3/4 — Test Generation & Validation:"
    echo "  Total new tests generated after 3rd LLM:        $TOTAL_NEWTESTS_GENERATED"
    echo "  New Tests Passing Stage 2:          $TOTAL_NEWTESTS_STAGE2_PASSED"
    echo "  Valid Vulnerabilities Found at the end:        $TOTAL_VALID_VULNERABILITIES_FOUND ($PERC_FINAL_NEWTESTS %)"
    echo "========================================================"
    echo "--------------------------------------------------------"
    echo "Successful Newtests (newtest_2 that FAILED on mutant):"
    echo "  (These are the finalized security tests that exposed a vulnerability)"
    echo ""
    if [ "${#VALID_NEWTEST_ENTRIES[@]}" -eq 0 ]; then
        echo "  (none)"
    else
        printf "  %-3s  %-55s  %s\n" "No." "Mutant File" "Newtest_2 File"
        printf "  %-3s  %-55s  %s\n" "---" "-------------------------------------------------------" "-----------------------------"
        idx=1
        for entry in "${VALID_NEWTEST_ENTRIES[@]}"; do
            mutant_part="${entry% | *}"
            newtest_part="${entry#* | }"
            printf "  %-3d  %-55s  %s\n" "$idx" "$mutant_part" "$newtest_part"
            ((idx++))
        done
    fi
) | tee -a "$REPORT_FILE"

echo
echo "Script process finished."
echo "Final report saved to: $REPORT_FILE"
echo


# #!/bin/bash

# # master_script_RESUME_PHASE2.sh
# # Usage: ./master_script.sh CWE-119 [skip_issues.csv]

# # --- 1. ARGUMENT PARSING ---
# if [ -z "$1" ]; then
#     echo "ERROR: No issue folder name provided."
#     echo "Usage: $0 <CWE-folder-name>"
#     exit 1
# fi

# ISSUE_FOLDER_NAME="$1"
# SKIP_CSV="sample_done_issue_list.csv"  

# # --- 2. DIRECTORY DEFINITIONS ---
# REPO_BASE_DIR="./CWEval/benchmark/core/c"
# ISSUE_DIR="./security_issues_FINAL_v5_with_cwe/$ISSUE_FOLDER_NAME"
# OUTPUT_DIR="$REPO_BASE_DIR/$ISSUE_FOLDER_NAME"

# FAILED_MUTANTS_DIR="$OUTPUT_DIR/incorrect-failed-mutants"
# NON_EQ_DIR="$OUTPUT_DIR/non-eq-$ISSUE_FOLDER_NAME"       
# NEW_TESTS_DIR="$OUTPUT_DIR/new-tests-$ISSUE_FOLDER_NAME"  
# declare -a VALID_NEWTEST_ENTRIES=()

# # --- 3. SCRIPT PATHS ---
# Mutator="scripts/mutator.py"
# eqCheckerFolder="scripts/eqCheckerFolder_v2.py"
# sec_test_gen="scripts/sec_test_gen.py"

# # Logging (Append to existing log)
# FULL_LOG="$OUTPUT_DIR/latest-output_log-$ISSUE_FOLDER_NAME.log"
# exec > >(tee -i -a "$FULL_LOG") 2>&1

# echo "============================================================"
# echo "RESUMING PROCESS AT PHASE 2: EQUIVALENCY CHECKING"
# echo "Target Folder: $ISSUE_FOLDER_NAME"
# echo "============================================================"

# # --- 4. RECONSTRUCT STATISTICAL COUNTERS ---
# # We count files in the output folders to ensure the final report is accurate.
# NUM_SUMMARIES=$(find "$ISSUE_DIR" -maxdepth 1 -name "*issue*.txt" | wc -l)
# NUM_CODES=$(find "$REPO_BASE_DIR" -maxdepth 1 -name "*_task.c" | wc -l)

# TOTAL_MUTANTS_BUILDABLE_AND_PASS=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.c" | wc -l)
# TOTAL_MUTANTS_FAILED=$(find "$FAILED_MUTANTS_DIR" -maxdepth 1 -name "*.c" | wc -l)
# TOTAL_MUTANTS_GENERATED=$((TOTAL_MUTANTS_BUILDABLE_AND_PASS + TOTAL_MUTANTS_FAILED))
# TOTAL_PAIRS_FOUND=$((NUM_SUMMARIES * NUM_CODES))
# TOTAL_PAIRS_SKIPPED=0

# TOTAL_NEWTESTS_GENERATED=0
# TOTAL_NEWTESTS_STAGE2_PASSED=0  
# TOTAL_VALID_VULNERABILITIES_FOUND=0

# # Recover tool-test list if some were already completed
# if [ -d "$NEW_TESTS_DIR/tool-new-tests" ]; then
#     while IFS= read -r test_file; do
#         mutant_name=$(basename "$test_file" | sed 's/_newtest_2.py/.c/')
#         VALID_NEWTEST_ENTRIES+=("$mutant_name | $(basename "$test_file")")
#         ((TOTAL_VALID_VULNERABILITIES_FOUND++))
#     done < <(find "$NEW_TESTS_DIR/tool-new-tests" -name "*newtest_2.py")
# fi

# echo "Phase 1 Stats Recovered: Generated: $TOTAL_MUTANTS_GENERATED | Valid: $TOTAL_MUTANTS_BUILDABLE_AND_PASS"

# # --- [SAFETY] CLEANUP ---
# cleanup() {
#     find "$REPO_BASE_DIR" -maxdepth 1 -name "*.bak" | while read -r bak_file; do
#         original="${bak_file%.bak}"
#         mv -f "$bak_file" "$original" 2>/dev/null
#     done
# }
# trap cleanup SIGINT SIGTERM EXIT

# # ===========================================================
# # PHASE 2: EQUIVALENCY CHECKING
# # ===========================================================
# echo "Running Equivalency Checker..."
# if [ "$TOTAL_MUTANTS_BUILDABLE_AND_PASS" -gt 0 ]; then
#     python3 "$eqCheckerFolder" "$OUTPUT_DIR"
# else
#     echo "ERROR: No mutants found to check."
#     exit 1
# fi

# readarray -t non_eq_mutants < <(find "$NON_EQ_DIR" -maxdepth 1 -name "*.c" 2>/dev/null | sort)
# TOTAL_NON_EQUIVALENT_MUTANTS=${#non_eq_mutants[@]}

# # ===========================================================
# # PHASE 3 & 4: NEW TEST GENERATION + VALIDATION
# # ===========================================================
# echo "Starting Phase 3 & 4..."

# for non_eq_mutant in "${non_eq_mutants[@]}"; do
#     mutant_basename=$(basename "$non_eq_mutant")
    
#     # Resume Logic: skip if vulnerability is already caught and moved
#     if find "$NEW_TESTS_DIR/tool-new-tests" -name "*${mutant_basename%.c}*newtest_2.py" -quit | grep -q .; then
#         echo "  [RESUME] skipping already validated mutant: $mutant_basename"
#         continue
#     fi

#     no_ext="${mutant_basename%.c}"
#     stripped="${no_ext#${ISSUE_FOLDER_NAME}_}"
#     issue_and_task="${stripped%_mutant}"
#     task_stem=$(echo "$issue_and_task" | sed 's/^issue_[0-9]*_//')
#     current_code="$REPO_BASE_DIR/${task_stem}.c"
#     existing_test_cases="$REPO_BASE_DIR/${task_stem/_task/_test}.py"

#     if [ ! -f "$current_code" ]; then continue; fi

#     echo "--------------------------------------------------------"
#     echo "Processing: $mutant_basename"

#     # LLM3 Call with 5-min timeout
#     sec_test_output=$(timeout 300s python3 "$sec_test_gen" "$current_code" "$existing_test_cases" "$non_eq_mutant" "$OUTPUT_DIR")
#     if [ $? -eq 124 ] || [ -z "$sec_test_output" ]; then
#         echo "  ERROR: LLM3 Timed out or failed."
#         continue
#     fi
#     ((TOTAL_NEWTESTS_GENERATED++))

#     newtest_1_file=$(echo "$sec_test_output" | sed -n '1p')
#     newtest_2_file=$(echo "$sec_test_output" | sed -n '2p')

#     TASK_BASENAME=$(basename "$current_code")
#     TEST_BASENAME=$(basename "$existing_test_cases")

#     # --- STAGE 2: newtest_1 vs ORIGINAL ---
#     echo "  <STAGE 2: Original vs Newtest_1>"
#     cd "$REPO_BASE_DIR"
#     mkdir -p ./compiled
#     gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
    
#     if [ $? -eq 0 ]; then
#         cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
#         cd - >/dev/null
#         cp "$newtest_1_file" "$REPO_BASE_DIR/$TEST_BASENAME"
#         cd "$REPO_BASE_DIR"
        
#         pytest -v --timeout=300 "$TEST_BASENAME"
#         st2_exit=$?
        
#         mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
#         cd - >/dev/null
        
#         if [ $st2_exit -ne 0 ]; then
#             echo "  DISCARD: Newtest_1 failed on original."
#             continue
#         fi
#         echo "SUCCSESS newtest_1 passed on the original. so we can proceed on newtest_2 on the mutant."
#         ((TOTAL_NEWTESTS_STAGE2_PASSED++))
#     else
#         echo "  ERROR: Original failed to compile."
#         cd - >/dev/null
#         continue
#     fi

#     # --- STAGE 3: newtest_2 vs MUTANT ---
#     echo "  <STAGE 3: Mutant vs Newtest_2>"
#     cd "$REPO_BASE_DIR"
#     cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
#     cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
#     cd - >/dev/null
#     cp "$non_eq_mutant" "$REPO_BASE_DIR/$TASK_BASENAME"
#     cp "$newtest_2_file" "$REPO_BASE_DIR/$TEST_BASENAME"
#     cd "$REPO_BASE_DIR"

#     # Syntax Check
#     python3 -m py_compile "$TEST_BASENAME" > /dev/null 2>&1
#     if [ $? -eq 0 ]; then
#         gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        
#         if [ $? -eq 0 ]; then
#             pytest -v --timeout=300 "$TEST_BASENAME"
#             st3_exit=$?
            
#             if [ $st3_exit -ne 0 ] && [ $st3_exit -lt 2 ]; then
#                 echo "  SUCCESS: Vulnerability caught! Newtest finally suceeded !!! Yay !!!"
#                 ((TOTAL_VALID_VULNERABILITIES_FOUND++))
#                 VALID_NEWTEST_ENTRIES+=("$(basename "$non_eq_mutant") | $(basename "$newtest_2_file")")
#                 mkdir -p "$NEW_TESTS_DIR/tool-new-tests"
#                 mv "$newtest_1_file" "$newtest_2_file" "$NEW_TESTS_DIR/tool-new-tests/"
#             else
#                 echo "  DISCARD NEWTEST: Mutant passed test or execution error."
#             fi
#         else
#             echo "  ERROR: Mutant failed to compile."
#         fi
#     else
#         echo "  DISCARD: Newtest_2 has syntax errors."
#     fi

#     mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
#     mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
#     cd - >/dev/null
# done

# # ==========================================
# # FINAL STATISTICAL REPORT (EXACT COPY)
# # ==========================================
# REPORT_FILE="$OUTPUT_DIR/final_report_$ISSUE_FOLDER_NAME.txt"

# if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
#     PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_MUTANTS_GENERATED) * 100}")
# else
#     PERC_BUILD_PASS="0.00"
# fi

# if [ "$TOTAL_MUTANTS_BUILDABLE_AND_PASS" -gt 0 ]; then
#     PERC_NON_EQUIV=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NON_EQUIVALENT_MUTANTS / $TOTAL_MUTANTS_BUILDABLE_AND_PASS) * 100}")
# else
#     PERC_NON_EQUIV="0.00"
# fi

# if [ "$TOTAL_NEWTESTS_GENERATED" -gt 0 ]; then
#     PERC_FINAL_NEWTESTS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_VALID_VULNERABILITIES_FOUND / $TOTAL_NEWTESTS_GENERATED) * 100}")
# else
#     PERC_FINAL_NEWTESTS="0.00"
# fi

# (
#     echo
#     echo "========================================================"
#     echo "              FINAL STATISTICAL REPORT                  "
#     echo "========================================================"
#     echo "Target Directory:         $REPO_BASE_DIR"
#     echo "Issue Source Directory:   $ISSUE_DIR"
#     echo "Output Directory:         $OUTPUT_DIR"
#     echo "  ├── Valid Mutants:      $OUTPUT_DIR  (*.c)"
#     echo "  ├── Failed Mutants:     $FAILED_MUTANTS_DIR"
#     echo "  ├── Non-EQ Mutants:     $NON_EQ_DIR"
#     echo "  └── New Tests:          $NEW_TESTS_DIR"
#     echo "--------------------------------------------------------"
#     echo "Skip-list source: $SKIP_SOURCE_NAME"
#     echo "Skip-list CSV:    ${SKIP_CSV:-'(none)'}"
#     echo "Pairs skipped:    $TOTAL_PAIRS_SKIPPED"
#     echo "--------------------------------------------------------"
#     echo "Total Issues Processed:               $NUM_SUMMARIES"
#     echo "Total Code/Test Pairs Found:          $TOTAL_PAIRS_FOUND"
#     echo "Total Code/Test Pairs Skipped:        $TOTAL_PAIRS_SKIPPED"
#     echo "Total Code/Test Pairs Run:            $(( TOTAL_PAIRS_FOUND - TOTAL_PAIRS_SKIPPED ))"
#     echo "--------------------------------------------------------"
#     echo "PHASE 1 — Mutant Generation:"
#     echo "  Total Mutants Generated:            $TOTAL_MUTANTS_GENERATED"
#     echo "  Buildable & Pass Existing Tests:    $TOTAL_MUTANTS_BUILDABLE_AND_PASS ($PERC_BUILD_PASS %)"
#     echo "  Failed / Non-buildable (discarded): $TOTAL_MUTANTS_FAILED"
#     echo "--------------------------------------------------------"
#     echo "PHASE 2 — Equivalency Checking:"
#     echo "  Non-Equivalent Mutants:             $TOTAL_NON_EQUIVALENT_MUTANTS ($PERC_NON_EQUIV %)"
#     echo "--------------------------------------------------------"
#     echo "PHASE 3/4 — Test Generation & Validation:"
#     echo "  Total new tests generated after 3rd LLM:        $TOTAL_NEWTESTS_GENERATED"
#     echo "  New Tests Passing Stage 2:          $TOTAL_NEWTESTS_STAGE2_PASSED"
#     echo "  Valid Vulnerabilities Found at the end:        $TOTAL_VALID_VULNERABILITIES_FOUND ($PERC_FINAL_NEWTESTS %)"
#     echo "========================================================"
#     echo "--------------------------------------------------------"
#     echo "Successful Newtests (newtest_2 that FAILED on mutant):"
#     echo "  (These are the finalized security tests that exposed a vulnerability)"
#     echo ""
#     if [ "${#VALID_NEWTEST_ENTRIES[@]}" -eq 0 ]; then
#         echo "  (none)"
#     else
#         printf "  %-3s  %-55s  %s\n" "No." "Mutant File" "Newtest_2 File"
#         printf "  %-3s  %-55s  %s\n" "---" "-------------------------------------------------------" "-----------------------------"
#         idx=1
#         for entry in "${VALID_NEWTEST_ENTRIES[@]}"; do
#             mutant_part="${entry% | *}"
#             newtest_part="${entry#* | }"
#             printf "  %-3d  %-55s  %s\n" "$idx" "$mutant_part" "$newtest_part"
#             ((idx++))
#         done
#     fi
# ) | tee -a "$REPORT_FILE"

# echo
# echo "Script process finished."
# echo "Final report saved to: $REPORT_FILE"
# echo


#!/bin/bash

# master_script_RESUME_PHASE3.sh
# Resumes from LLM3 Test Generation, reconstructs all previous stats.

# # --- 1. ARGUMENT PARSING ---
# if [ -z "$1" ]; then
#     echo "ERROR: No issue folder name provided."
#     echo "Usage: $0 <CWE-folder-name>"
#     exit 1
# fi

# ISSUE_FOLDER_NAME="$1"

# # --- 2. DIRECTORY DEFINITIONS (ABSOLUTE PATHS) ---
# # Using realpath ensures 'mv' and 'cp' never fail after a 'cd' command
# REPO_BASE_DIR=$(realpath "./CWEval/benchmark/core/c")
# ISSUE_DIR=$(realpath "./security_issues_FINAL_v5_with_cwe/$ISSUE_FOLDER_NAME")
# OUTPUT_DIR=$(realpath "$REPO_BASE_DIR/$ISSUE_FOLDER_NAME")

# FAILED_MUTANTS_DIR=$(realpath "$OUTPUT_DIR/incorrect-failed-mutants")
# NON_EQ_DIR=$(realpath "$OUTPUT_DIR/non-eq-$ISSUE_FOLDER_NAME")       
# NEW_TESTS_DIR=$(realpath "$OUTPUT_DIR/new-tests-$ISSUE_FOLDER_NAME")
# # Pre-define Tool Tests Dir as absolute
# TOOL_TESTS_DIR="$NEW_TESTS_DIR/tool-new-tests"

# # Create directories upfront
# mkdir -p "$FAILED_MUTANTS_DIR"
# mkdir -p "$NON_EQ_DIR"
# mkdir -p "$NEW_TESTS_DIR"
# mkdir -p "$TOOL_TESTS_DIR"

# # Confirm Tool Tests Dir absolute path
# TOOL_TESTS_DIR=$(realpath "$TOOL_TESTS_DIR")

# declare -a VALID_NEWTEST_ENTRIES=()

# # --- 3. SCRIPT PATHS (ABSOLUTE) ---
# sec_test_gen=$(realpath "scripts/sec_test_gen.py")

# # Logging (Append to existing log)
# FULL_LOG="$OUTPUT_DIR/lastest-latest_log-$ISSUE_FOLDER_NAME.log"
# exec > >(tee -i -a "$FULL_LOG") 2>&1

# echo "============================================================"
# echo "RESUMING PROCESS AT PHASE 3: TEST GENERATION (LLM3)"
# echo "Target Folder: $ISSUE_FOLDER_NAME"
# echo "============================================================"

# # --- 4. RECONSTRUCT STATISTICAL COUNTERS ---
# NUM_SUMMARIES=$(find "$ISSUE_DIR" -maxdepth 1 -name "*issue*.txt" | wc -l)
# NUM_CODES=$(find "$REPO_BASE_DIR" -maxdepth 1 -name "*_task.c" | wc -l)

# TOTAL_MUTANTS_BUILDABLE_AND_PASS=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.c" | wc -l)
# TOTAL_MUTANTS_FAILED=$(find "$FAILED_MUTANTS_DIR" -maxdepth 1 -name "*.c" 2>/dev/null | wc -l)
# TOTAL_MUTANTS_GENERATED=$((TOTAL_MUTANTS_BUILDABLE_AND_PASS + TOTAL_MUTANTS_FAILED))
# TOTAL_PAIRS_FOUND=$((NUM_SUMMARIES * NUM_CODES))
# TOTAL_PAIRS_SKIPPED=0 

# TOTAL_NON_EQUIVALENT_MUTANTS=$(find "$NON_EQ_DIR" -maxdepth 1 -name "*.c" 2>/dev/null | wc -l)
# TOTAL_VALID_VULNERABILITIES_FOUND=0
# TOTAL_NEWTESTS_GENERATED=0
# TOTAL_NEWTESTS_STAGE2_PASSED=0

# # Recover tool-test list for report
# if [ -d "$TOOL_TESTS_DIR" ]; then
#     while IFS= read -r test_file; do
#         m_name=$(basename "$test_file" | sed 's/_newtest_2.py/.c/')
#         VALID_NEWTEST_ENTRIES+=("$m_name | $(basename "$test_file")")
#         ((TOTAL_VALID_VULNERABILITIES_FOUND++))
#     done < <(find "$TOOL_TESTS_DIR" -name "*newtest_2.py" | sort -V)
# fi

# echo "  [STATS] Recovered Generated: $TOTAL_MUTANTS_GENERATED | Valid: $TOTAL_MUTANTS_BUILDABLE_AND_PASS"
# echo "  [STATS] Non-Equivalent: $TOTAL_NON_EQUIVALENT_MUTANTS | Caught: $TOTAL_VALID_VULNERABILITIES_FOUND"
# echo "------------------------------------------------------------"

# # --- [SAFETY] CLEANUP ---
# cleanup() {
#     find "$REPO_BASE_DIR" -maxdepth 1 -name "*.bak" | while read -r bak_file; do
#         original="${bak_file%.bak}"
#         mv -f "$bak_file" "$original" 2>/dev/null
#     done
# }
# trap cleanup SIGINT SIGTERM EXIT

# # ===========================================================
# # PHASE 3 & 4: NEW TEST GENERATION + VALIDATION
# # ===========================================================
# echo "Starting Phase 3 & 4 (LLM3)..."

# # NATURAL SORT (-V) ensures issue_1 comes before issue_10
# readarray -t non_eq_mutants < <(find "$NON_EQ_DIR" -maxdepth 1 -name "*.c" 2>/dev/null | sort -V)

# for non_eq_mutant in "${non_eq_mutants[@]}"; do
#     mutant_basename=$(basename "$non_eq_mutant")
#     stem="${mutant_basename%.c}"
    
#     # Resume check
#     if ls "$TOOL_TESTS_DIR" | grep -q "${stem}_newtest_2.py"; then
#         echo "  [RESUME] Skipping $mutant_basename (already exists in tool-new-tests)."
#         continue
#     fi

#     no_ext="${mutant_basename%.c}"
#     stripped="${no_ext#${ISSUE_FOLDER_NAME}_}"
#     issue_and_task="${stripped%_mutant}"
#     task_stem=$(echo "$issue_and_task" | sed 's/^issue_[0-9]*_//')
    
#     current_code="$REPO_BASE_DIR/${task_stem}.c"
#     existing_test_cases="$REPO_BASE_DIR/${task_stem/_task/_test}.py"

#     if [ ! -f "$current_code" ]; then
#         echo "  WARNING: Source file not found: $current_code. Skipping."
#         continue
#     fi

#     echo "--------------------------------------------------------"
#     echo "Processing: $mutant_basename"

#     # LLM3 Generation
#     sec_test_output=$(timeout 300s python3 "$sec_test_gen" "$current_code" "$existing_test_cases" "$non_eq_mutant" "$OUTPUT_DIR")
#     if [ $? -eq 124 ] || [ -z "$sec_test_output" ]; then
#         echo "  ERROR: LLM3 Timed out or failed for $mutant_basename"
#         continue
#     fi
#     ((TOTAL_NEWTESTS_GENERATED++))

#     newtest_1_file=$(echo "$sec_test_output" | sed -n '1p')
#     newtest_2_file=$(echo "$sec_test_output" | sed -n '2p')

#     TASK_BASENAME=$(basename "$current_code")
#     TEST_BASENAME=$(basename "$existing_test_cases")

#     # --- STAGE 2: newtest_1 vs ORIGINAL ---
#     echo "  <STAGE 2: Original vs Newtest_1>"
#     cd "$REPO_BASE_DIR"
#     mkdir -p ./compiled
#     gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
    
#     if [ $? -eq 0 ]; then
#         cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
#         cd - >/dev/null
#         cp "$newtest_1_file" "$REPO_BASE_DIR/$TEST_BASENAME"
#         cd "$REPO_BASE_DIR"
        
#         pytest -v --timeout=300 "$TEST_BASENAME"
#         st2_exit=$?
        
#         mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
#         cd - >/dev/null
        
#         if [ $st2_exit -ne 0 ]; then
#             echo "  DISCARD: Newtest_1 failed on original."
#             continue
#         fi
#         echo "  SUCCESS: Newtest_1 passed on original source."
#         ((TOTAL_NEWTESTS_STAGE2_PASSED++))
#     else
#         echo "  ERROR: Original failed to compile."
#         cd - >/dev/null
#         continue
#     fi

#     # --- STAGE 3: newtest_2 vs MUTANT ---
#     echo "  <STAGE 3: Mutant vs Newtest_2>"
#     cd "$REPO_BASE_DIR"
#     cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
#     cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
#     cd - >/dev/null
#     cp "$non_eq_mutant" "$REPO_BASE_DIR/$TASK_BASENAME"
#     cp "$newtest_2_file" "$REPO_BASE_DIR/$TEST_BASENAME"
#     cd "$REPO_BASE_DIR"

#     python3 -m py_compile "$TEST_BASENAME" > /dev/null 2>&1
#     if [ $? -eq 0 ]; then
#         gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%.c}" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        
#         if [ $? -eq 0 ]; then
#             pytest -v --timeout=300 "$TEST_BASENAME"
#             st3_exit=$?
            
#             if [ $st3_exit -ne 0 ] && [ $st3_exit -lt 2 ]; then
#                 echo "  SUCCESS: Valid Vulnerability Found!"
#                 ((TOTAL_VALID_VULNERABILITIES_FOUND++))
#                 VALID_NEWTEST_ENTRIES+=("$(basename "$non_eq_mutant") | $(basename "$newtest_2_file")")
#                 # Moving files to Tool Tests Dir (Absolute path avoids error)
#                 mv "$newtest_1_file" "$newtest_2_file" "$TOOL_TESTS_DIR/"
#             else
#                 echo "  DISCARD: Mutant passed test or execution error."
#             fi
#         else
#             echo "  ERROR: Mutant failed to compile."
#         fi
#     else
#         echo "  DISCARD: Newtest_2 has syntax errors."
#     fi

#     mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
#     mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
#     cd - >/dev/null
# done

# # ==========================================
# # FINAL STATISTICAL REPORT
# # ==========================================
# REPORT_FILE="$OUTPUT_DIR/final_report_$ISSUE_FOLDER_NAME.txt"

# if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
#     PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_MUTANTS_GENERATED) * 100}")
# else
#     PERC_BUILD_PASS="0.00"
# fi

# if [ "$TOTAL_MUTANTS_BUILDABLE_AND_PASS" -gt 0 ]; then
#     PERC_NON_EQUIV=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NON_EQUIVALENT_MUTANTS / $TOTAL_MUTANTS_BUILDABLE_AND_PASS) * 100}")
# else
#     PERC_NON_EQUIV="0.00"
# fi

# if [ "$TOTAL_NEWTESTS_GENERATED" -gt 0 ]; then
#     PERC_FINAL_NEWTESTS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_VALID_VULNERABILITIES_FOUND / $TOTAL_NEWTESTS_GENERATED) * 100}")
# else
#     PERC_FINAL_NEWTESTS="0.00"
# fi

# (
#     echo ""
#     echo "========================================================"
#     echo "              FINAL STATISTICAL REPORT                  "
#     echo "========================================================"
#     echo "Target Directory:         $REPO_BASE_DIR"
#     echo "Output Directory:         $OUTPUT_DIR"
#     echo "--------------------------------------------------------"
#     echo "Total Issues Processed:               $NUM_SUMMARIES"
#     echo "Total Code/Test Pairs Found:          $TOTAL_PAIRS_FOUND"
#     echo "--------------------------------------------------------"
#     echo "PHASE 1 — Mutant Generation (Reconstructed):"
#     echo "  Total Mutants Generated:            $TOTAL_MUTANTS_GENERATED"
#     echo "  Passed Existing Tests:              $TOTAL_MUTANTS_BUILDABLE_AND_PASS ($PERC_BUILD_PASS %)"
#     echo "  Failed / Non-buildable (discarded): $TOTAL_MUTANTS_FAILED"
#     echo "--------------------------------------------------------"
#     echo "PHASE 2 — Equivalency Checking (Reconstructed):"
#     echo "  Non-Equivalent Mutants:             $TOTAL_NON_EQUIVALENT_MUTANTS ($PERC_NON_EQUIV %)"
#     echo "--------------------------------------------------------"
#     echo "PHASE 3/4 — Test Generation & Validation:"
#     echo "  Total new tests generated after 3rd LLM:        $TOTAL_NEWTESTS_GENERATED"
#     echo "  New Tests Passing Stage 2:          $TOTAL_NEWTESTS_STAGE2_PASSED"
#     echo "  Valid Vulnerabilities Found at the end:        $TOTAL_VALID_VULNERABILITIES_FOUND ($PERC_FINAL_NEWTESTS %)"
#     echo "========================================================"
#     echo "Successful Newtests (newtest_2 that FAILED on mutant):"
#     echo ""
#     if [ "${#VALID_NEWTEST_ENTRIES[@]}" -eq 0 ]; then
#         echo "  (none)"
#     else
#         printf "  %-3s  %-55s  %s\n" "No." "Mutant File" "Newtest_2 File"
#         printf "  %-3s  %-55s  %s\n" "---" "-------------------------------------------------------" "-----------------------------"
#         idx=1
#         for entry in "${VALID_NEWTEST_ENTRIES[@]}"; do
#             mutant_part="${entry% | *}"
#             newtest_part="${entry#* | }"
#             printf "  %-3d  %-55s  %s\n" "$idx" "$mutant_part" "$newtest_part"
#             ((idx++))
#         done
#     fi
# ) | tee -a "$REPORT_FILE"

# echo ""
# echo "Script process finished. Final report saved to: $REPORT_FILE"