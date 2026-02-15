#!/bin/bash

# USAGE: scripts/eqCheckerFolder.sh <C_folder_absolute_or_relative_to_project_root>

if [ "$#" -ne 1 ]; then
    echo "Usage: scripts/eqCheckerFolder.sh <input_folder>"
    exit 1
fi

input_folder="$1"
# Get absolute path to input folder
abs_input_folder="$(cd "$input_folder" && pwd)"

if [ ! -d "$abs_input_folder" ]; then
    echo "Input directory does not exist: $abs_input_folder"
    exit 1
fi

# Find all C files in the folder, not recursively
mapfile -t files < <(find "$abs_input_folder" -maxdepth 1 -type f -name "*.c" | sort)
num_files="${#files[@]}"

if [ "$num_files" -le 1 ]; then
    echo "Only one or zero *.c files, nothing to compare."
    exit 0
fi

mkdir -p "$abs_input_folder/eq_checker_output"
output_dir="$abs_input_folder/non-eq-$(basename "$abs_input_folder")"
mkdir -p "$output_dir"

# Get path to eqChecker.py relative to bash script regardless of CWD
eqchecker_py="$(dirname "$0")/eqChecker.py"

for ((i=0; i<$num_files; i++)); do
    file_i="${files[$i]}"
    unique=1
    for ((j=i+1; j<$num_files; j++)); do
        if [ "$i" -eq "$j" ]; then continue; fi
        file_j="${files[$j]}"
        output=$(python3 "$eqchecker_py" "$file_i" "$file_j" "$abs_input_folder/eq_checker_output")
        if echo "$output" | grep -iq "{yes}"; then
            unique=0
            break
        fi
    done

    if [ "$unique" -eq 1 ]; then
        cp "$file_i" "$output_dir/"
        echo "Unique (non-equivalent) file: $file_i"
    fi
done

echo "Done. Non-equivalent files are copied to: $output_dir"