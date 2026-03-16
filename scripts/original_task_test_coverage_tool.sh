#!/bin/bash

# original_task_test_coverage.sh
# Usage: ./original_task_test_coverage.sh 78 122 284

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
    echo "STARTING PROCESSING FOR: $CWE_FOLDER"
    echo "=========================================================="

    CWE_PATH="$BASE_DIR/$CWE_FOLDER"
    REF_FILE="$CWE_PATH/final_report_${CWE_FOLDER}.txt"
    REPORT_FILE="$CWE_PATH/original_test_coverage_report-${CWE_FOLDER}.txt"

    # 1. Verification
    if [ ! -f "$REF_FILE" ]; then
        echo "Error: Reference report file $REF_FILE not found. Skipping..."
        continue
    fi

    # 2. Extract the list of successful newtest_2 files from the report
    mapfile -t NEWTEST_2_FILES < <(sed -n '/Successful Newtests/,/]]/p' "$REF_FILE" | grep '_newtest_2.py' | awk '{print $NF}')

    if [ ${#NEWTEST_2_FILES[@]} -eq 0 ]; then
        echo "No successful tests found in $REF_FILE. Skipping..."
        continue
    fi

    # 3. Initialize Variables for Average (Reset for each CWE)
    total_coverage=0
    test_count=0

    # 4. Initialize Report
    echo "Coverage Analysis for Successfully Validated Tests ($CWE_FOLDER)" > "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "==========================================================" >> "$REPORT_FILE"

    # 5. Process each entry
    cd "$BASE_DIR" || exit
    mkdir -p compiled

    for nt2_file in "${NEWTEST_2_FILES[@]}"; do
        # Identify the task name (e.g., cwe_078_0_c_task)
        task_name=$(echo "$nt2_file" | grep -oP 'cwe_\d+_\d+_c_task')
        
        if [ -z "$task_name" ]; then
            continue
        fi

        source_c="$task_name.c"
        original_test_py="${task_name/_task/_test}.py"

        if [ ! -f "$source_c" ] || [ ! -f "$original_test_py" ]; then
            echo "   Warning: Source ($source_c) or Test ($original_test_py) not found, skipping..."
            continue
        fi

        echo "   Processing $task_name..."

        # Step A: Compile the original source with coverage flags
        gcc -w -I./includes --coverage "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        # Step B: Run the original test
        pytest -v "$original_test_py" > /dev/null 2>&1

        # Step C: Run gcov and extract summary line
        if [ -f "./compiled/$task_name.gcda" ]; then
            coverage_output=$(gcov -o ./compiled/ "$source_c" 2>/dev/null | grep "Lines executed" | head -n 1)
            coverage_info=$(echo "$coverage_output" | xargs)
            perc_val=$(echo "$coverage_output" | grep -oP '\d+(\.\d+)?(?=%)')
            [ -z "$perc_val" ] && perc_val="0.00"
        else
            coverage_info="Lines executed: 0.00% (Error: data not generated)"
            perc_val="0.00"
        fi

        total_coverage=$(echo "$total_coverage + $perc_val" | bc)
        ((test_count++))

        # Step D: Record to report
        {
            echo "Task:        $task_name"
            echo "Test File:   $original_test_py"
            echo "Coverage:    $coverage_info"
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
        echo "FINAL SUMMARY FOR $CWE_FOLDER"
        echo "Total Tests Processed: $test_count"
        echo "Average Line Coverage: $average_coverage%"
        echo "=========================================================="
    } >> "$REPORT_FILE"

    # Terminal output for the current CWE
    echo "----------------------------------------------------------"
    echo "COMPLETED $CWE_FOLDER"
    echo "Total Tests: $test_count"
    echo "Average Line Coverage: $average_coverage%"
    echo "Report: $REPORT_FILE"
    echo "----------------------------------------------------------"
    echo ""
    echo ""
    echo ""

    # Return to project root before next CWE iteration
    cd "$ROOT_DIR" || exit

done

echo "All requested CWE folders have been processed."