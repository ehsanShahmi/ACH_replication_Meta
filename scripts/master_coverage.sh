# #!/bin/bash

# # Check if at least one CWE number is provided
# if [ $# -eq 0 ]; then
#     echo "Usage: ./master_coverage.sh <CWE-NUM-1> <CWE-NUM-2> ..."
#     echo "Example: ./master_coverage.sh 16 20 78"
#     exit 1
# fi

# ROOT_DIR=$(pwd)
# BASE_DIR="$ROOT_DIR/CWEval/benchmark/core/c"

# # Outer loop to process each CWE number provided as an argument
# for CWE_NUM in "$@"; do
#     CWE_FOLDER="CWE-$CWE_NUM"

#     echo "=========================================================="
#     echo "STARTING PROCESSING FOR: $CWE_FOLDER"
#     echo "=========================================================="

#     CWE_PATH="$BASE_DIR/$CWE_FOLDER"
#     REF_FILE="$CWE_PATH/final_report_${CWE_FOLDER}.txt"
#     REPORT_FILE="$CWE_PATH/final_tool_coverage_report-$CWE_FOLDER.txt"

#     if [ ! -f "$REF_FILE" ]; then
#         echo "Error: Reference file $REF_FILE not found. Skipping $CWE_FOLDER..."
#         continue
#     fi

#     mapfile -t NEWTEST_2_FILES < <(awk '/Newtest_2 File/{flag=1; next} /---/{next} flag{if($NF != "") print $NF}' "$REF_FILE")

#     if [ ${#NEWTEST_2_FILES[@]} -eq 0 ]; then
#         echo "No successful tests found in $REF_FILE. Skipping $CWE_FOLDER..."
#         continue
#     fi

#     total_coverage=0
#     test_count=0

#     echo "Coverage Analysis for Successfully Validated Tests ($CWE_FOLDER)" > "$REPORT_FILE"
#     echo "Generated on: $(date)" >> "$REPORT_FILE"
#     echo "==========================================================" >> "$REPORT_FILE"

#     cd "$BASE_DIR" || exit
#     mkdir -p compiled

#     for nt2_file in "${NEWTEST_2_FILES[@]}"; do
#         nt1_file="${nt2_file/_newtest_2.py/_newtest_1.py}"
#         task_name=$(echo "$nt1_file" | grep -oP 'cwe_\d+_\d+_c_task')
#         base_name=$(echo "$task_name" | sed 's/_task//')
        
#         source_c="$task_name.c"
#         target_test_py="${base_name}_test.py"
#         full_nt1_path="$CWE_FOLDER/new-tests-$CWE_FOLDER/$nt1_file"

#         echo "[$CWE_FOLDER] Processing $nt1_file..."

#         if [ ! -f "$full_nt1_path" ]; then
#             echo "   Warning: $nt1_file not found, skipping..."
#             continue
#         fi

#         # Step 1: Backup
#         [ -f "$target_test_py" ] && mv "$target_test_py" "$target_test_py.bak"
#         cp "$full_nt1_path" "$target_test_py"

#         # Step 2: Compile (and kill any existing binary with the same name just in case)
#         pkill -f "compiled/$task_name" 2>/dev/null
#         gcc -w -I./includes "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3 --coverage

#         if [ $? -ne 0 ]; then
#              echo "   ERROR: Compilation failed for $source_c"
#              # Restore backup
#              [ -f "$target_test_py.bak" ] && mv "$target_test_py.bak" "$target_test_py"
#              continue
#         fi

#         # Step 3: Run pytest (Reduced timeout to 60s and removed total suppression)
#         echo "   Running pytest..."
#         # We only suppress stdout, but keep stderr to see errors
#         pytest -v --timeout=150 "$target_test_py" > /dev/null
#         pytest_exit=$?

#         if [ $pytest_exit -eq 124 ]; then
#             echo "   TIMEOUT: pytest took longer than 150s. Likely infinite loop."
#         fi

#         # Step 4: Run gcov
#         if [ -f "./compiled/$task_name.gcda" ]; then
#             coverage_output=$(gcov -o ./compiled/ "$source_c" 2>/dev/null | grep "Lines executed" | head -n 1)
#             coverage_info=$(echo "$coverage_output" | xargs)
#             perc_val=$(echo "$coverage_output" | grep -oP '\d+(\.\d+)?(?=%)')
#             [ -z "$perc_val" ] && perc_val="0.00"
#         else
#             coverage_info="Lines executed: 0.00% (Error: .gcda file not found)"
#             perc_val="0.00"
#         fi

#         total_coverage=$(echo "$total_coverage + $perc_val" | bc)
#         ((test_count++))

#         {
#             echo "Task:        $task_name"
#             echo "Test File:   $nt1_file"
#             echo "Coverage:    $coverage_info"
#             echo "----------------------------------------------------------"
#         } >> "$REPORT_FILE"

#         # Step 5: Restore and Cleanup
#         if [ -f "$target_test_py.bak" ]; then
#             mv "$target_test_py.bak" "$target_test_py"
#         else
#             rm "$target_test_py"
#         fi
#         rm -f "./compiled/$task_name"
#         rm -f ./compiled/*.gcno ./compiled/*.gcda
#         rm -f "$source_c.gcov"
#     done

#     if [ "$test_count" -gt 0 ]; then
#         average_coverage=$(echo "scale=2; $total_coverage / $test_count" | bc)
#     else
#         average_coverage="0.00"
#     fi

#     {
#         echo ""
#         echo "=========================================================="
#         echo "FINAL SUMMARY FOR $CWE_FOLDER"
#         echo "Total Tests Processed: $test_count"
#         echo "Average Line Coverage: $average_coverage%"
#         echo "=========================================================="
#     } >> "$REPORT_FILE"

#     echo "Completed $CWE_FOLDER. Report: $REPORT_FILE"
#     echo "Average coverage for $CWE_FOLDER: $average_coverage%."
#     echo ""
#     echo ""

#     cd "$ROOT_DIR" || exit
# done

# echo "All requested folders have been processed."

#!/bin/bash

# Check if at least one CWE number is provided
if [ $# -eq 0 ]; then
    echo "Usage: ./master_coverage.sh <CWE-NUM-1> <CWE-NUM-2> ..."
    echo "Example: ./master_coverage.sh 16 20 78"
    exit 1
fi

ROOT_DIR=$(pwd)
BASE_DIR="$ROOT_DIR/CWEval/benchmark/core/c"

# Outer loop to process each CWE number provided as an argument
for CWE_NUM in "$@"; do
    CWE_FOLDER="CWE-$CWE_NUM"

    echo "=========================================================="
    echo "STARTING PROCESSING FOR: $CWE_FOLDER"
    echo "=========================================================="

    CWE_PATH="$BASE_DIR/$CWE_FOLDER"
    REF_FILE="$CWE_PATH/final_report_${CWE_FOLDER}.txt"
    REPORT_FILE="$CWE_PATH/final_tool_coverage_report-$CWE_FOLDER.txt"

    if [ ! -f "$REF_FILE" ]; then
        echo "Error: Reference file $REF_FILE not found. Skipping $CWE_FOLDER..."
        continue
    fi

    mapfile -t NEWTEST_2_FILES < <(awk '/Newtest_2 File/{flag=1; next} /---/{next} flag{if($NF != "") print $NF}' "$REF_FILE")

    if [ ${#NEWTEST_2_FILES[@]} -eq 0 ]; then
        echo "No successful tests found in $REF_FILE. Skipping $CWE_FOLDER..."
        continue
    fi

    total_coverage=0
    test_count=0

    echo "Coverage Analysis for Successfully Validated Tests ($CWE_FOLDER)" > "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "==========================================================" >> "$REPORT_FILE"

    cd "$BASE_DIR" || exit
    mkdir -p compiled

    for nt2_file in "${NEWTEST_2_FILES[@]}"; do
        nt1_file="${nt2_file/_newtest_2.py/_newtest_1.py}"
        task_name=$(echo "$nt1_file" | grep -oP 'cwe_\d+_\d+_c_task')
        base_name=$(echo "$task_name" | sed 's/_task//')
        
        source_c="$task_name.c"
        target_test_py="${base_name}_test.py"
        full_nt1_path="$CWE_FOLDER/new-tests-$CWE_FOLDER/tool-new-tests/$nt1_file"

        echo "[$CWE_FOLDER] Processing $nt1_file..."

        if [ ! -f "$full_nt1_path" ]; then
            echo "   Warning: $nt1_file not found, skipping..."
            continue
        fi

        # --- RECOVERY / CLEANUP FUNCTION ---
        cleanup_iteration() {
            # Kill any binary that might be hanging
            pkill -9 -f "compiled/$task_name" 2>/dev/null
            # Restore original test file
            if [ -f "$target_test_py.bak" ]; then
                mv -f "$target_test_py.bak" "$target_test_py"
            fi
            # Cleanup coverage temp files
            rm -f "./compiled/$task_name"
            rm -f ./compiled/*.gcno ./compiled/*.gcda
            rm -f "$source_c.gcov"
        }

        # Step 1: Backup original test
        # SAFETY: If a .bak already exists (from a crashed previous run), don't overwrite it
        if [ ! -f "$target_test_py.bak" ] && [ -f "$target_test_py" ]; then
            mv "$target_test_py" "$target_test_py.bak"
        fi
        cp "$full_nt1_path" "$target_test_py"

        # Step 2: Compile
        pkill -9 -f "compiled/$task_name" 2>/dev/null
        gcc -w -I./includes "$source_c" -o "./compiled/$task_name" -larchive -lcrypto -ljwt -ljansson -lxml2 -lsqlite3 --coverage
        
        if [ $? -ne 0 ]; then
             echo "   ERROR: Compilation failed for $source_c"
             cleanup_iteration
             continue
        fi

        # Step 3: Run pytest with OS-level timeout
        echo "   Running pytest..."
        # Wrap in 'timeout' to prevent the script from freezing if pytest's internal timeout fails
        timeout 160s pytest -v --timeout=150 "$target_test_py" > /dev/null 2>&1
        pytest_exit=$?

        if [ $pytest_exit -eq 124 ]; then
            echo "   TIMEOUT: pytest was killed after 160s (OS level)."
        fi

        # Step 4: Run gcov
        perc_val="0.00"
        if [ -f "./compiled/$task_name.gcda" ]; then
            # Ensure file is flushed to disk
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
            echo "Test File:   $nt1_file"
            echo "Coverage:    $coverage_info"
            echo "----------------------------------------------------------"
        } >> "$REPORT_FILE"

        # Step 5: Iteration Cleanup and Restoration
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
        echo "FINAL SUMMARY FOR $CWE_FOLDER"
        echo "Total Tests Processed: $test_count"
        echo "Average Line Coverage: $average_coverage%"
        echo "=========================================================="
    } >> "$REPORT_FILE"

    echo "Completed $CWE_FOLDER. Report: $REPORT_FILE"
    echo "Average coverage for $CWE_FOLDER: $average_coverage%."
    echo ""

    cd "$ROOT_DIR" || exit
done

echo "All requested folders have been processed."