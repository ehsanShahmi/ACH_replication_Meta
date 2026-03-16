#!/bin/bash

# baseline_original_test_coverage.sh
# Usage: ./baseline_original_test_coverage.sh 78 122 284

# --- 1. ARGUMENT PARSING ---
if [ $# -eq 0 ]; then
    echo "Usage: $0 <CWE-NUM-1> <CWE-NUM-2> ..."
    echo "Example: $0 78 122 284"
    exit 1
fi

ROOT_DIR=$(pwd)
BASE_DIR="$ROOT_DIR/CWEval/benchmark/core/c"

# --- OUTER LOOP: Process each CWE number provided ---
for CWE_NUM in "$@"; do
    CWE_FOLDER="CWE-$CWE_NUM"
    
    echo "=========================================================="
    echo "STARTING ORIGINAL COVERAGE FOR PASSED BASELINES: $CWE_FOLDER"
    echo "=========================================================="

    CWE_PATH="$BASE_DIR/$CWE_FOLDER"
    BASELINE_PASSED_DIR="$CWE_PATH/baseline/baseline-new-tests-$CWE_FOLDER"
    REPORT_FILE="$CWE_PATH/baseline_original_test_coverage_report-baselines-$CWE_FOLDER.txt"

    # 1. Verification
    if [ ! -d "$BASELINE_PASSED_DIR" ]; then
        echo "Error: Baseline folder $BASELINE_PASSED_DIR not found. Skipping..."
        continue
    fi

    # 2. Identify tasks that passed bNewtest by looking at the files in the baseline folder
    # filenames look like: CWE-122_issue_1_cwe_022_0_c_task_bNewtest.py
    readarray -t B_NEWTEST_FILES < <(ls "$BASELINE_PASSED_DIR"/*.py 2>/dev/null)

    if [ ${#B_NEWTEST_FILES[@]} -eq 0 ]; then
        echo "No passed bNewtests found in $BASELINE_PASSED_DIR. Skipping..."
        continue
    fi

    # 3. Initialize Variables for Average
    total_coverage=0
    test_count=0

    # 4. Initialize Report
    echo "Coverage Analysis of Original Tests for Tasks with Passed bNewtests ($CWE_FOLDER)" > "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "==========================================================" >> "$REPORT_FILE"

    # 5. Process each entry
    cd "$BASE_DIR" || exit
    mkdir -p compiled

    for bnt_path in "${B_NEWTEST_FILES[@]}"; do
        bnt_file=$(basename "$bnt_path")
        
        # Identify the task name (e.g., cwe_078_0_c_task) from the baseline filename
        task_name=$(echo "$bnt_file" | grep -oP 'cwe_\d+_\d+_c_task')
        
        if [ -z "$task_name" ]; then
            continue
        fi

        source_c="$task_name.c"
        # We target the ORIGINAL test suite
        original_test_py="${task_name/_task/_test}.py"

        if [ ! -f "$source_c" ] || [ ! -f "$original_test_py" ]; then
            echo "   Warning: Original Source ($source_c) or Test ($original_test_py) not found, skipping..."
            continue
        fi

        echo "   Processing $task_name (Original Test Coverage)..."

        # Step A: Compile the original source with coverage flags
        # Ensure we kill any hanging binaries from previous runs
        pkill -9 -f "compiled/$task_name" 2>/dev/null
        gcc -w -I./includes --coverage "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        # Step B: Run the original test
        # Use a timeout to prevent infinite loop freezes
        timeout 160s pytest -v --timeout=150 "$original_test_py" > /dev/null 2>&1
        pytest_exit=$?

        # Step C: Run gcov and extract summary line
        if [ -f "./compiled/$task_name.gcda" ]; then
            sync
            coverage_output=$(gcov -o ./compiled/ "$source_c" 2>/dev/null | grep "Lines executed" | head -n 1)
            coverage_info=$(echo "$coverage_output" | xargs)
            perc_val=$(echo "$coverage_output" | grep -oP '\d+(\.\d+)?(?=%)')
            [ -z "$perc_val" ] && perc_val="0.00"
        else
            coverage_info="Lines executed: 0.00% (Error: .gcda file not found)"
            perc_val="0.00"
        fi

        total_coverage=$(echo "$total_coverage + $perc_val" | bc)
        ((test_count++))

        # Step D: Record to report
        {
            echo "Task:            $task_name"
            echo "bNewtest Found:  $bnt_file"
            echo "Original Test:   $original_test_py"
            echo "Coverage:        $coverage_info"
            echo "----------------------------------------------------------"
        } >> "$REPORT_FILE"

        # Step E: Cleanup artifacts
        rm -f "./compiled/$task_name"
        rm -f ./compiled/*.gcno ./compiled/*.gcda
        rm -f "$source_c.gcov"
    done

    # 6. Final Calculation for this CWE
    if [ "$test_count" -gt 0 ]; then
        average_coverage=$(echo "scale=2; $total_coverage / $test_count" | bc)
    else
        average_coverage="0.00"
    fi

    # Append Summary to report
    {
        echo ""
        echo "=========================================================="
        echo "FINAL SUMMARY FOR $CWE_FOLDER (Original Test Baseline)"
        echo "Total Tasks Processed: $test_count"
        echo "Average Line Coverage: $average_coverage%"
        echo "=========================================================="
    } >> "$REPORT_FILE"

    # Terminal output for the current CWE
    echo "----------------------------------------------------------"
    echo "COMPLETED $CWE_FOLDER"
    echo "Total Tasks with Passed Baselines: $test_count"
    echo "Average Line Coverage of Original Tests: $average_coverage%"
    echo "Report: $REPORT_FILE"
    echo "----------------------------------------------------------"
    echo ""

    # Return to project root before next CWE iteration
    cd "$ROOT_DIR" || exit

done

echo "All baseline-filtered original coverage tasks have been processed."