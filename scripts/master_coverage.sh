#!/bin/bash

# Check if at least one CWE folder name is provided
if [ $# -eq 0 ]; then
    echo "Usage: ./master_coverage.sh <CWE-FOLDER-1> <CWE-FOLDER-2> ..."
    echo "Example: ./master_coverage.sh CWE-16 CWE-20 CWE-78"
    exit 1
fi

ROOT_DIR=$(pwd)
BASE_DIR="$ROOT_DIR/CWEval/benchmark/core/c"

# Outer loop to process each CWE folder provided as an argument
for CWE_FOLDER in "$@"; do
    echo "=========================================================="
    echo "STARTING PROCESSING FOR: $CWE_FOLDER"
    echo "=========================================================="

    CWE_PATH="$BASE_DIR/$CWE_FOLDER"
    REF_FILE="$CWE_PATH/final_report_${CWE_FOLDER}.txt"
    REPORT_FILE="$CWE_PATH/final_coverage_report-$CWE_FOLDER.txt"

    # 1. Verification
    if [ ! -f "$REF_FILE" ]; then
        echo "Error: Reference file $REF_FILE not found. Skipping $CWE_FOLDER..."
        continue
    fi

    # 2. Extract the list of successful newtest_2 files from the report
    mapfile -t NEWTEST_2_FILES < <(awk '/Newtest_2 File/{flag=1; next} /---/{next} flag{if($NF != "") print $NF}' "$REF_FILE")

    if [ ${#NEWTEST_2_FILES[@]} -eq 0 ]; then
        echo "No successful tests found in $REF_FILE. Skipping $CWE_FOLDER..."
        continue
    fi

    # 3. Initialize Variables for Average (Reset for each CWE)
    total_coverage=0
    test_count=0

    # 4. Initialize Report
    echo "Coverage Analysis for Successfully Validated Tests ($CWE_FOLDER)" > "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "==========================================================" >> "$REPORT_FILE"

    # 5. Enter the C core directory
    cd "$BASE_DIR" || exit
    mkdir -p compiled

    for nt2_file in "${NEWTEST_2_FILES[@]}"; do
        nt1_file="${nt2_file/_newtest_2.py/_newtest_1.py}"
        task_name=$(echo "$nt1_file" | grep -oP 'cwe_\d+_\d+_c_task')
        base_name=$(echo "$task_name" | sed 's/_task//')
        
        source_c="$task_name.c"
        target_test_py="${base_name}_test.py"
        full_nt1_path="$CWE_FOLDER/new-tests-$CWE_FOLDER/$nt1_file"

        echo "[$CWE_FOLDER] Processing $nt1_file..."

        if [ ! -f "$full_nt1_path" ]; then
            echo "Warning: $nt1_file not found, skipping..."
            continue
        fi

        # Step 1: Backup original test file
        [ -f "$target_test_py" ] && mv "$target_test_py" "$target_test_py.bak"

        # Step 2: Copy the newtest_1 file
        cp "$full_nt1_path" "$target_test_py"

        # Step 3: Compile
        gcc -w -I./includes --coverage "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3

        # Step 4: Run pytest
        pytest -v "$target_test_py" > /dev/null 2>&1

        # Step 5: Run gcov and extract summary
        if [ -f "./compiled/$task_name.gcda" ]; then
            coverage_output=$(gcov -o ./compiled/ "$source_c" | grep "Lines executed" | head -n 1)
            coverage_info=$(echo "$coverage_output" | xargs)
            perc_val=$(echo "$coverage_output" | grep -oP '\d+(\.\d+)?(?=%)')
        else
            coverage_info="Lines executed: 0.00% (Error: .gcda file not found)"
            perc_val="0.00"
        fi

        # Accumulate for average
        total_coverage=$(echo "$total_coverage + $perc_val" | bc)
        ((test_count++))

        # Step 6: Record to report
        {
            echo "Task:        $task_name"
            echo "Test File:   $nt1_file"
            echo "Coverage:    $coverage_info"
            echo "----------------------------------------------------------"
        } >> "$REPORT_FILE"

        # Step 7: Restore and Cleanup
        if [ -f "$target_test_py.bak" ]; then
            mv "$target_test_py.bak" "$target_test_py"
        else
            rm "$target_test_py"
        fi
        rm -f "./compiled/$task_name"
        rm -f ./compiled/*.gcno ./compiled/*.gcda
        rm -f "$source_c.gcov"
    done

    # Calculate Final Average for this CWE
    if [ "$test_count" -gt 0 ]; then
        average_coverage=$(echo "scale=2; $total_coverage / $test_count" | bc)
    else
        average_coverage="0.00"
    fi

    # Append Average to individual folder report
    {
        echo ""
        echo "=========================================================="
        echo "FINAL SUMMARY FOR $CWE_FOLDER"
        echo "Total Tests Processed: $test_count"
        echo "Average Line Coverage: $average_coverage%"
        echo "=========================================================="
    } >> "$REPORT_FILE"

    echo "Completed $CWE_FOLDER. Report: $REPORT_FILE"
    echo ""

    # Return to root directory before next loop iteration
    cd "$ROOT_DIR" || exit

done

echo "All requested folders have been processed."