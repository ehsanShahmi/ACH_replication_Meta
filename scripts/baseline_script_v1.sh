#!/bin/bash

# baseline_script.sh
# Usage: ./baseline_script.sh CWE-835

# --- 1. ARGUMENT PARSING ---
if [ -z "$1" ]; then
    echo "ERROR: No issue folder name provided."
    echo "Usage: $0 <CWE-folder-name>   e.g.  $0 CWE-835"
    exit 1
fi

ISSUE_FOLDER_NAME="$1"

# --- 2. DIRECTORY DEFINITIONS ---
REPO_BASE_DIR="./CWEval/benchmark/core/c"
ISSUE_DIR="./security_issues_FINAL_v5_with_cwe/$ISSUE_FOLDER_NAME"

# Baseline specific directories
BASELINE_ROOT_DIR="$REPO_BASE_DIR/$ISSUE_FOLDER_NAME/baseline"
GEN_DIR_ALL="$BASELINE_ROOT_DIR/baseline-new-tests-$ISSUE_FOLDER_NAME-all"
GEN_DIR_PASSED="$BASELINE_ROOT_DIR/baseline-new-tests-$ISSUE_FOLDER_NAME"
MUTANT_DIR_ALL="$BASELINE_ROOT_DIR/baseline-mutants-all"
MUTANT_DIR_CAUGHT="$BASELINE_ROOT_DIR/baseline-mutants"
REPORT_FILE="$REPO_BASE_DIR/$ISSUE_FOLDER_NAME/baseline_report_$ISSUE_FOLDER_NAME.txt"

# Create required directories
mkdir -p "$GEN_DIR_ALL"
mkdir -p "$GEN_DIR_PASSED"
mkdir -p "$MUTANT_DIR_ALL"
mkdir -p "$MUTANT_DIR_CAUGHT"

# --- SAFETY CLEANUP AND RECOVERY LOGIC ---
cleanup() {
    find "$REPO_BASE_DIR" -maxdepth 1 -name "*.bak" | while read -r bak_file; do
        original="${bak_file%.bak}"
        mv -f "$bak_file" "$original" 2>/dev/null
    done
}
trap cleanup SIGINT SIGTERM EXIT

# --- 3. PATH VALIDATION ---
if [ ! -d "$REPO_BASE_DIR" ]; then echo "ERROR: Repo base missing."; exit 1; fi
if [ ! -d "$ISSUE_DIR" ]; then echo "ERROR: Issue dir missing."; exit 1; fi

# Logging
FULL_LOG="$BASELINE_ROOT_DIR/baseline_output_$ISSUE_FOLDER_NAME.log"
exec > >(tee -i "$FULL_LOG") 2>&1
echo "============================================================"
echo "STARTING BASELINE PROCESS FOR $ISSUE_FOLDER_NAME"
echo "============================================================"

# --- 4. SCRIPT PATHS ---
Baseline_Newtest="scripts/baseline_newtest.py"
Baseline_Mutant_Gen="scripts/baseline_mutant_gen.py"

# --- 5. DATA COLLECTION ---
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*issue*.txt" | sort)
readarray -t code_files  < <(find "$REPO_BASE_DIR" -maxdepth 1 -name "*_task.c" | sort)

NUM_SUMMARIES=${#issue_files[@]}
NUM_CODES=${#code_files[@]}

# STATISTICAL COUNTERS
TOTAL_NEWTESTS_GENERATED=0
TOTAL_NEWTESTS_PASSED_ORIGINAL=0
TOTAL_MUTANTS_GENERATED=0
TOTAL_MUTANTS_BUILDABLE=0
TOTAL_MUTANTS_CAUGHT_BY_NEWTEST=0

# ===========================================================
# PHASE 1: BASELINE TEST GENERATION & VALIDATION
# ===========================================================
echo ""
echo "============================================================"
echo "PHASE 1: GENERATING bNewtests (Issue x Task)"
echo "============================================================"

for issue_file in "${issue_files[@]}"; do
    base_name=$(basename "$issue_file")
    issue_id=${base_name%.txt}

    for current_code in "${code_files[@]}"; do
        existing_test_suite="${current_code/_task.c/_test.py}"
        if [ ! -f "$existing_test_suite" ]; then continue; fi

        current_basename=$(basename "$current_code")
        echo "[PHASE1-LLM1-NEWTEST] $issue_id x $current_basename"

        # Step 1: Generate bNewtest
        generated_test_path=$(python3 "$Baseline_Newtest" "$issue_file" "$current_code" "$existing_test_suite" "$GEN_DIR_ALL")

        if [ $? -ne 0 ] || [ -z "$generated_test_path" ]; then
            echo "  ERROR: baseline_newtest.py script failed."
            continue
        fi

        # Compilability Check for the Python Test
        python3 -m py_compile "$generated_test_path" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "  DISCARD: Newtest has syntax errors (not compilable). DISCARD !!!"
            continue
        fi

        ((TOTAL_NEWTESTS_GENERATED++))

        # Step 2: Validate against ORIGINAL source
        cd "$REPO_BASE_DIR"
        TASK_BASENAME=$(basename "$current_code")
        TEST_BASENAME=$(basename "$existing_test_suite")
        
        cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
        cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
        
        cp "../../../../$generated_test_path" "$TEST_BASENAME"

        gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/${TASK_BASENAME%.c} -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
        if [ $? -eq 0 ]; then
            pytest -v --timeout=300 "$TEST_BASENAME"
            test_exit_code=$?
        else
            echo "  ERROR: Original source failed to compile."
            test_exit_code=1
        fi

        mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
        mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
        cd - >/dev/null

        if [ $test_exit_code -eq 0 ]; then
            echo "  PASS: Newtest passed on Original Source. Moving to -> $GEN_DIR_PASSED"
            mv "$generated_test_path" "$GEN_DIR_PASSED/"
            ((TOTAL_NEWTESTS_PASSED_ORIGINAL++))
        else
            echo "  FAIL: Newtest failed on Original. DISCARD !!!"
        fi
    done
done

# ===========================================================
# PHASE 2: MUTANT GENERATION & VALIDATION
# ===========================================================
echo ""
echo "============================================================"
echo "PHASE 2: GENERATING MUTANTS FROM PASSED bNewtests"
echo "============================================================"

readarray -t passed_newtests < <(find "$GEN_DIR_PASSED" -maxdepth 1 -name "*.py" | sort)

for bNewtest_path in "${passed_newtests[@]}"; do
    bNewtest_basename=$(basename "$bNewtest_path")
    
    # Filename Logic: CWE-XXX_issue_X_cwe_XXX_X_c_task_bNewtest.py
    temp_name="${bNewtest_basename%_bNewtest.py}"
    task_stem=$(echo "$temp_name" | grep -o 'cwe_[0-9a-z_]*_task')
    issue_id=$(echo "$temp_name" | sed "s/_${task_stem}//")
    
    orig_c_path="$REPO_BASE_DIR/${task_stem}.c"
    orig_test_path="$REPO_BASE_DIR/${task_stem/_task/_test}.py"
    issue_txt_path="$ISSUE_DIR/${issue_id}.txt"

    if [ ! -f "$orig_c_path" ] || [ ! -f "$issue_txt_path" ]; then
        echo "ERROR: Could not find original files for $bNewtest_basename"
        continue
    fi

    echo "[PHASE2-LLM2-MUTANT] Creating mutant for $bNewtest_basename"

    # Step 1: Generate Mutant
    generated_mutant_path=$(python3 "$Baseline_Mutant_Gen" "$orig_c_path" "$orig_test_path" "$bNewtest_path" "$issue_txt_path" "$MUTANT_DIR_ALL")
    if [ $? -ne 0 ] || [ -z "$generated_mutant_path" ]; then
        echo "  ERROR: baseline_mutant_gen.py script failed."
        continue
    fi
    echo "bMutant generated in: $generated_mutant_path"
    ((TOTAL_MUTANTS_GENERATED++))

    # Step 2: Validate Mutant
    cd "$REPO_BASE_DIR"
    TASK_BASENAME=$(basename "$orig_c_path")
    TEST_BASENAME=$(basename "$orig_test_path")
    
    cp "$TASK_BASENAME" "$TASK_BASENAME.bak"
    cp "$TEST_BASENAME" "$TEST_BASENAME.bak"
    
    # Swap in Mutant and bNewtest
    cp "../../../../$generated_mutant_path" "$TASK_BASENAME"
    cp "../../../../$bNewtest_path" "$TEST_BASENAME"

    echo "  Compiling mutant..."
    gcc -w -I./includes "$TASK_BASENAME" -o ./compiled/${TASK_BASENAME%.c} -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3
    compile_status=$?

    if [ $compile_status -eq 0 ]; then
        ((TOTAL_MUTANTS_BUILDABLE++))
        echo "  Mutant compiled successfully. Running pytest..."
        pytest -v --timeout=300 "$TEST_BASENAME"
        # In this phase, a FAIL (exit code != 0) means the mutant was caught
        pytest_exit=$?
    else
        echo "  DISCARD: Mutant failed to compile. Skipping testing. DISCARD MUTANT !!!"
        pytest_exit=0 
    fi

    # Restore originals
    mv -f "$TEST_BASENAME.bak" "$TEST_BASENAME"
    mv -f "$TASK_BASENAME.bak" "$TASK_BASENAME"
    cd - >/dev/null

    # If it compiled AND pytest failed, it's a success (caught mutant)
    if [ $compile_status -eq 0 ] && [ $pytest_exit -ne 0 ]; then
        echo "  SUCCESS: Mutant caught by bNewtest. Moving to -> $MUTANT_DIR_CAUGHT"
        mv "$generated_mutant_path" "$MUTANT_DIR_CAUGHT/"
        ((TOTAL_MUTANTS_CAUGHT_BY_NEWTEST++))
    elif [ $compile_status -eq 0 ]; then
        echo "  FAILURE: Mutant PASSED bNewtest. Vulnerability missed."
    fi
done

# Calculate Percentages
if [ "$TOTAL_NEWTESTS_GENERATED" -gt 0 ]; then
    PERC_NEWTEST=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_NEWTESTS_PASSED_ORIGINAL / $TOTAL_NEWTESTS_GENERATED) * 100}")
else
    PERC_NEWTEST="0.00"
fi

if [ "$TOTAL_MUTANTS_GENERATED" -gt 0 ]; then
    PERC_MUTANT=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_MUTANTS_CAUGHT_BY_NEWTEST / $TOTAL_MUTANTS_GENERATED) * 100}")
else
    PERC_MUTANT="0.00"
fi

# ==========================================
# FINAL REPORT
# ==========================================
(
    echo ""
    echo "========================================================"
    echo "             BASELINE FINAL STATS REPORT                "
    echo "========================================================"
    echo "CWE Folder:                         $ISSUE_FOLDER_NAME"
    echo "--------------------------------------------------------"
    echo "PHASE 1 (Test Generation):"
    echo "  Total bNewtests (Compilable):     $TOTAL_NEWTESTS_GENERATED"
    echo "  Passed (Original Source):         $TOTAL_NEWTESTS_PASSED_ORIGINAL ($PERC_NEWTEST %)"
    echo "--------------------------------------------------------"
    echo "PHASE 2 (Mutant Generation):"
    echo "  Total bMutants Generated:         $TOTAL_MUTANTS_GENERATED"
    echo "  Total bMutants Buildable:         $TOTAL_MUTANTS_BUILDABLE"
    echo "  Caught (Pytest Failed):           $TOTAL_MUTANTS_CAUGHT_BY_NEWTEST ($PERC_MUTANT %)"
    echo "--------------------------------------------------------"
    echo "Caught mutants saved in: $MUTANT_DIR_CAUGHT"
    echo "========================================================"
) | tee "$REPORT_FILE"

echo "Process Finished. Report saved to: $REPORT_FILE"