#!/bin/bash

# Check if at least one CWE number is provided
if [ $# -eq 0 ]; then
    echo "Usage: ./baseline_coverage.sh <CWE-NUM-1> <CWE-NUM-2> ..."
    echo "Example: ./baseline_coverage.sh 122 835"
    exit 1
fi

ROOT_DIR=$(pwd)
BASE_DIR="$ROOT_DIR/CWEval/benchmark/core/c"

# Outer loop to process each CWE number provided as an argument
for CWE_NUM in "$@"; do
    CWE_FOLDER="CWE-$CWE_NUM"

    echo "=========================================================="
    echo "STARTING BASELINE COVERAGE FOR: $CWE_FOLDER"
    echo "=========================================================="

    CWE_PATH="$BASE_DIR/$CWE_FOLDER"
    PASSED_TESTS_DIR="$CWE_PATH/baseline/baseline-new-tests-$CWE_FOLDER"
    REPORT_FILE="$CWE_PATH/baseline_coverage_report-$CWE_FOLDER.txt"

    if [ ! -d "$PASSED_TESTS_DIR" ]; then
        echo "Error: Directory $PASSED_TESTS_DIR not found. Skipping $CWE_FOLDER..."
        continue
    fi

    # Extract the list of .py files in the passed baseline tests folder
    readarray -t B_NEWTEST_FILES < <(ls "$PASSED_TESTS_DIR"/*.py 2>/dev/null)

    if [ ${#B_NEWTEST_FILES[@]} -eq 0 ]; then
        echo "No passed baseline tests found in $PASSED_TESTS_DIR. Skipping $CWE_FOLDER..."
        continue
    fi

    total_coverage=0
    test_count=0

    echo "Baseline Coverage Analysis for bNewtests ($CWE_FOLDER)" > "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "==========================================================" >> "$REPORT_FILE"

    cd "$BASE_DIR" || exit
    mkdir -p compiled

    for bnt_path in "${B_NEWTEST_FILES[@]}"; do
        bnt_file=$(basename "$bnt_path")
        
        # Identify the task name (e.g., cwe_122_0_c_task) from the bNewtest filename
        task_name=$(echo "$bnt_file" | grep -oP 'cwe_\d+_\d+_c_task')
        
        if [ -z "$task_name" ]; then
            echo "   Warning: Could not extract task name from $bnt_file, skipping..."
            continue
        fi

        source_c="$task_name.c"
        # The script temporarily replaces the standard test file so pytest runs smoothly
        target_test_py="${task_name/_task/_test}.py"

        echo "[$CWE_FOLDER] Processing $bnt_file against $source_c..."

        # --- RECOVERY / CLEANUP FUNCTION ---
        cleanup_iteration() {
            pkill -9 -f "compiled/$task_name" 2>/dev/null
            if [ -f "$target_test_py.bak" ]; then
                mv -f "$target_test_py.bak" "$target_test_py"
            fi
            rm -f "./compiled/$task_name"
            rm -f ./compiled/*.gcno ./compiled/*.gcda
            rm -f "$source_c.gcov"
        }

        # Step 1: Backup original test file
        if [ ! -f "$target_test_py.bak" ] && [ -f "$target_test_py" ]; then
            mv "$target_test_py" "$target_test_py.bak"
        fi
        cp "$bnt_path" "$target_test_py"

        # Step 2: Compile with Coverage
        pkill -9 -f "compiled/$task_name" 2>/dev/null
        gcc -w -I./includes "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3 --coverage
        
        if [ $? -ne 0 ]; then
             echo "   ERROR: Compilation failed for $source_c"
             cleanup_iteration
             continue
        fi

        # Step 3: Run pytest
        echo "   Running pytest..."
        timeout 160s pytest -v --timeout=150 "$target_test_py" > /dev/null 2>&1
        pytest_exit=$?

        if [ $pytest_exit -eq 124 ]; then
            echo "   TIMEOUT: pytest was killed after 160s."
        fi

        # Step 4: Run gcov
        perc_val="0.00"
        if [ -f "./compiled/$task_name.gcda" ]; then
            sync
            coverage_output=$(gcov -o ./compiled/ "$source_c" 2>/dev/null | grep "Lines executed" | head -n 1)
            coverage_info=$(echo "$coverage_output" | xargs)
            perc_val=$(echo "$coverage_output" | grep -oP '\d+(\.\d+)?(?=%)')
            [ -z "$perc_val" ] && perc_val="0.00"
        else
            coverage_info="Lines executed: 0.00% (Error: .gcda not found)"
        fi

        total_coverage=$(echo "$total_coverage + $perc_val" | bc)
        ((test_count++))

        {
            echo "Task:        $task_name"
            echo "bNewtest:    $bnt_file"
            echo "Coverage:    $coverage_info"
            echo "----------------------------------------------------------"
        } >> "$REPORT_FILE"

        cleanup_iteration
    done

    # Calculate Average
    if [ "$test_count" -gt 0 ]; then
        average_coverage=$(echo "scale=2; $total_coverage / $test_count" | bc)
    else
        average_coverage="0.00"
    fi

    {
        echo ""
        echo "=========================================================="
        echo "FINAL SUMMARY FOR $CWE_FOLDER (BASELINE)"
        echo "Total bNewtests Processed: $test_count"
        echo "Average Line Coverage: $average_coverage%"
        echo "=========================================================="
    } >> "$REPORT_FILE"

    echo "Completed $CWE_FOLDER. Report: $REPORT_FILE"
    echo "Average baseline coverage for $CWE_FOLDER: $average_coverage%."
    echo ""

    cd "$ROOT_DIR" || exit
done

echo "All baseline coverage tasks completed."