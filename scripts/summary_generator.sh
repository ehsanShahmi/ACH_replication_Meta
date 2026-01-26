#!/bin/bash

# summary_generator.sh

# Directories
ISSUE_DIR="./security_issue_cluster_test5"
SUMMARY_DIR="./security_issue_summaries5"
SUMMARIZER_SCRIPT="./scripts/summarizer.py"

# Create the output directory if it doesn't exist
mkdir -p "$SUMMARY_DIR"

echo "=========================================="
echo "Starting Summary Generation Process..."
echo "Input Directory:  $ISSUE_DIR"
echo "Output Directory: $SUMMARY_DIR"
echo "=========================================="

# Collect all issue files
readarray -t issue_files < <(find "$ISSUE_DIR" -maxdepth 1 -name "*.txt" | sort)
NUM_ISSUES=${#issue_files[@]}

if [ "$NUM_ISSUES" -eq 0 ]; then
    echo "ERROR: No issue files found in $ISSUE_DIR"
    exit 1
fi

count=0

for issue_file in "${issue_files[@]}"; do
    ((count++))
    
    # Extract filename (e.g., "CWE-119.txt")
    base_name=$(basename "$issue_file")
    # Remove extension to get ID (e.g., "CWE-119")
    issue_id="${base_name%.*}"
    
    # Define output filename (e.g., "CWE-119-summary.txt")
    output_file="$SUMMARY_DIR/${issue_id}-summary.txt"

    echo "[$count/$NUM_ISSUES] Generating summary for $base_name..."

    # Run the Python summarizer and redirect output to the text file
    # Assuming summarizer.py prints the summary to stdout. 
    # If it writes to a file internally, you might need to adjust this line.
    python3 "$SUMMARIZER_SCRIPT" "$issue_file" > "$output_file"

    if [ $? -eq 0 ]; then
        echo "   -> Saved to: $output_file"
    else
        echo "   -> ERROR: Failed to generate summary for $base_name"
    fi
done

echo "=========================================="
echo "Summary generation complete."
echo "=========================================="