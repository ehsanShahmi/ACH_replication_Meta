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

# --- 3. PATH VALIDATION ---
if [ ! -d "$REPO_BASE_DIR" ]; then
    echo "ERROR: The repository directory '$REPO_BASE_DIR' does not exist."
    exit 1
fi
if [ ! -d "$ISSUE_DIR" ]; then
    echo "ERROR: The issue directory '$ISSUE_DIR' does not exist."
    exit 1
fi

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
#   For every (issue, code) pair:
#     0. SKIP CHECK: if source == SKIP_SOURCE_NAME and issue_id
#        is in skip_set, skip this pair entirely (no LLM call).
#     1. Generate mutant → saved directly into OUTPUT_DIR
#     2. Validate: must compile + pass existing tests
#     3. If fails → move to FAILED_MUTANTS_DIR
#     4. If passes → leave in OUTPUT_DIR (ready for eqChecker)
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

        # ------------------------------------------------------------------
        # SKIP CHECK
        # Only applies when the current source is SKIP_SOURCE_NAME AND
        # this issue_id is present in the loaded skip_set.
        # ------------------------------------------------------------------
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

        # --- Step 2: Stage 1 Validation — mutant must compile + pass existing tests ---
        echo "<--- STAGE 1: Mutant vs existing tests (expect PASS) --->"
        cd "$REPO_BASE_DIR"

        TASK_BASENAME=$(basename "$current_code")
        TEST_BASENAME=$(basename "$existing_test_cases")
        # Path to mutant relative to REPO_BASE_DIR (4 levels from project root)
        MUTANT_REL_PATH="../../../../$mutant_file"

        # Swap mutant in as the task file
        mv "$TASK_BASENAME" "$TASK_BASENAME.bak"
        cp "$MUTANT_REL_PATH" "$TASK_BASENAME"

        # Compile mutant (and _unsafe if present)
        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}" -larchive
        compile_exit=$?
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe" -larchive

        # Only run pytest if compilation succeeded
        if [ $compile_exit -eq 0 ]; then
            pytest -v "$TEST_BASENAME"
            test_exit_code=$?
        else
            echo "COMPILE FAILED for mutant."
            test_exit_code=1
        fi

        # Restore original task file
        rm "$TASK_BASENAME"
        mv "$TASK_BASENAME.bak" "$TASK_BASENAME"
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

    done  # end inner loop (code files)
done  # end outer loop (issue files)

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
# PHASE 2: EQUIVALENCY CHECKING (folder-level)
#   eqCheckerFolder_v2.py operates on OUTPUT_DIR directly.
#   It compares all *.c mutant files in that folder and saves
#   non-equivalent ones to NON_EQ_DIR (auto-created by script).
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

# Count non-equivalent mutants written by eqCheckerFolder
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
#   For each non-eq mutant in NON_EQ_DIR:
#     1. Infer corresponding (source_task.c, existing_test.py) from filename.
#        Convention: <CWE>_<issue_id>_<task_stem>_mutant.c
#        e.g.  CWE-119_issue_3_cwe_020_0_c_task_mutant.c
#               → task_stem = cwe_020_0_c_task
#     2. Call sec_test_gen_v2 → returns TWO paths (newline-separated):
#          line1: <stem>_newtest_1.py  ← run vs ORIGINAL source (expect PASS)
#          line2: <stem>_newtest_2.py  ← run vs MUTANT          (expect FAIL)
#     3. Stage 2: newtest_1 vs original source → expect PASS
#     4. Stage 3: newtest_2 vs mutant          → expect FAIL
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

        # ------------------------------------------------------------------
        # Infer original task stem from mutant filename.
        # Format:  <ISSUE_FOLDER_NAME>_<issue_id>_<task_stem>_mutant.c
        # Example: CWE-119_issue_3_cwe_020_0_c_task_mutant.c
        #   1. drop .c              → CWE-119_issue_3_cwe_020_0_c_task_mutant
        #   2. strip CWE prefix     → issue_3_cwe_020_0_c_task_mutant
        #   3. strip _mutant        → issue_3_cwe_020_0_c_task
        #   4. strip issue_<N>_     → cwe_020_0_c_task
        # ------------------------------------------------------------------
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

        # ------------------------------------------------------------------
        # Step 3.1: Generate newtest_1 and newtest_2 via sec_test_gen_v2.
        # sec_test_gen_v2 returns two absolute paths separated by a newline:
        #   line 1 → *_newtest_1.py  (vs original, expect PASS)
        #   line 2 → *_newtest_2.py  (vs mutant,   expect FAIL)
        # We pass OUTPUT_DIR so sec_test_gen builds new-tests-<CWE>/ inside it.
        # ------------------------------------------------------------------
        echo "(LLM3) Generating new test cases..."
        sec_test_output=$(python3 "$sec_test_gen" "$current_code" "$existing_test_cases" "$non_eq_mutant" "$OUTPUT_DIR")

        if [ $? -ne 0 ] || [ -z "$sec_test_output" ]; then
            echo "ERROR: sec_test_gen script failed. Skipping."
            continue
        fi
        (($TOTAL_NEWTESTS_GENERATED))++

        # Parse the two newline-separated paths returned by sec_test_gen_v2
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

        # ------------------------------------------------------------------
        # Stage 2: newtest_1 vs ORIGINAL source — expect PASS
        # ------------------------------------------------------------------
        echo "<--- STAGE 2: newtest_1 vs original source (expect PASS) --->"
        cd "$REPO_BASE_DIR"

        # Compile original source (and _unsafe if present)
        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}"
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe"

        # Swap in newtest_1
        mv "$TEST_BASENAME" "$TEST_BASENAME.bak"
        cd - >/dev/null
        cp "$newtest_1_file" "$REPO_BASE_DIR/$TEST_BASENAME"
        cd "$REPO_BASE_DIR"

        pytest -v "$TEST_BASENAME"
        stage2_exit_code=$?

        # Restore original test
        rm "$TEST_BASENAME"
        mv "$TEST_BASENAME.bak" "$TEST_BASENAME"
        cd - >/dev/null

        if [ $stage2_exit_code -ne 0 ]; then
            echo "DISCARD: newtest_1 FAILED on original source."
            continue
        fi
        ((TOTAL_NEWTESTS_STAGE2_PASSED++))
        echo "PASS: newtest_1 passed on original source."
        echo "--------------------------------------------------------------------"

        # ------------------------------------------------------------------
        # Stage 3: newtest_2 vs MUTANT — expect FAIL
        # ------------------------------------------------------------------
        echo "<--- STAGE 3: newtest_2 vs mutant (expect FAIL) --->"
        cd "$REPO_BASE_DIR"

        # Swap mutant in as task file
        mv "$TASK_BASENAME" "$TASK_BASENAME.bak"
        cd - >/dev/null
        cp "$non_eq_mutant" "$REPO_BASE_DIR/$TASK_BASENAME"
        cd "$REPO_BASE_DIR"

        # Compile mutant (and _unsafe if present)
        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/"${TASK_BASENAME%_task.c}"
        [ -f "${TASK_BASENAME/_task.c/_unsafe.c}" ] && \
            gcc -w -I./includes "${TASK_BASENAME/_task.c/_unsafe.c}" -o ./compiled/"${TASK_BASENAME%_task.c}_unsafe"

        # Swap in newtest_2 as test file
        mv "$TEST_BASENAME" "$TEST_BASENAME.bak"
        cd - >/dev/null
        cp "$newtest_2_file" "$REPO_BASE_DIR/$TEST_BASENAME"
        cd "$REPO_BASE_DIR"

        pytest -v "$TEST_BASENAME"
        stage3_exit_code=$?

        # Restore both originals
        rm "$TASK_BASENAME"
        mv "$TASK_BASENAME.bak" "$TASK_BASENAME"
        rm "$TEST_BASENAME"
        mv "$TEST_BASENAME.bak" "$TEST_BASENAME"
        cd - >/dev/null

        if [ $stage3_exit_code -eq 0 ]; then
            echo "DISCARD: newtest_2 PASSED on mutant — vulnerability not caught."
        else
            echo "SUCCESS: newtest_2 FAILED on mutant — VALID VULNERABILITY FOUND!"
            ((TOTAL_VALID_VULNERABILITIES_FOUND++))
            # Record this successful (newtest_2, mutant) pair for the report
            VALID_NEWTEST_ENTRIES+=("$(basename "$non_eq_mutant") | $(basename "$newtest_2_file")")
        fi
        echo "--------------------------------------------------------------------"

    done  # end non-eq mutant loop
fi


# ==========================================
# FINAL STATISTICAL REPORT
# ==========================================
REPORT_FILE="$OUTPUT_DIR/final_report_$ISSUE_FOLDER_NAME.txt"

if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
    PERC_BUILD_PASS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_BUILDABLE_AND_PASS / $TOTAL_PAIRS_FOUND) * 100}")
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