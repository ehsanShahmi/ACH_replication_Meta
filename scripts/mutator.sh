#!/bin/bash

# process_summaries.sh

# Define variables for clarity
SCRIPT_PATH="./scripts/summarizer.py"
ISSUE_DIR="./security_issues_2"

echo "Starting summary generation process..."
echo "-------------------------------------"

# Loop through all .txt files in the target directory
for issue_file in "$ISSUE_DIR"/*.txt; do
    if [ -f "$issue_file" ]; then
        echo "Processing file: $issue_file"

        # --- KEY INTEGRATION POINT ---
        # Call the Python script with the current file path as an argument.
        # We capture the output using command substitution $() to store it in a variable.
        summary=$(python3 "$SCRIPT_PATH" "$issue_file")
        
        # Check the exit status of the python script (0 means success, non-zero is failure)
        if [ $? -eq 0 ]; then
            echo "Summary for $issue_file:"
            echo "$summary"
            echo "-------------------------------------"
        else
            echo "ERROR: Python script failed for $issue_file"
            echo "-------------------------------------"
        fi
    fi
done

echo "Process finished."