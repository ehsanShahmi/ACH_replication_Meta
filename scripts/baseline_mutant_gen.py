# python3 scripts/baseline_mutant_gen.py ./CWEval/benchmark/core/c/cwe_020_0_c_task.c ./CWEval/benchmark/core/c/cwe_020_0_c_test.py ./CWEval/benchmark/core/c/CWE-835/baselne/baseline-new-test-CWE-835/CWE-835_issue_1_cwe_020_0_c_newtest.py ./CWEval/benchmark/core/c/CWE-835/baseline/baseline-mutants-all

from dotenv import load_dotenv
load_dotenv()
from google import genai
from google.genai import types
import os
import sys
import glob
from pathlib import Path
import logging
import openai
import re


client = genai.Client()
client_gpt = openai.OpenAI()

def get_includes_as_string(include_dir="./includes") -> str:
    """
    Reads all .h files in the include directory and returns them concatenated.
    """
    combined_includes = ""
    header_files = glob.glob(os.path.join(include_dir, "*.h"))
    
    for file_path in header_files:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
                combined_includes += f"\n--- START HEADER FILE: {os.path.basename(file_path)} ---\n"
                combined_includes += content
                combined_includes += f"\n--- END HEADER FILE: {os.path.basename(file_path)} ---\n"
        except IOError as e:
            print(f"Warning: Could not read file {file_path}: {e}")
            continue
    return combined_includes

import re

def clean_llm_markdown(input_string: str) -> str:
    # 1. Initial Markdown Extraction
    # Prioritize content inside ```python ... ``` blocks
    text = input_string.strip()
    pattern = r'```(?:\w+)?\n?(.*?)\n?```'
    match = re.search(pattern, text, flags=re.DOTALL)
    if match:
        text = match.group(1).strip()
    
    # 2. Remove stray trailing triple quotes
    # This handles Sample 1 where the LLM appends an extra """ at the end
    # We use a non-greedy approach to only target quotes at the absolute end
    text = re.sub(r'\s*["\']{3}\s*$', '', text)

    # 3. Repair unclosed brackets (The "Sample 2" Fix)
    # Instead of deleting code, we find what's missing and add it.
    stack = []
    bracket_map = {'(': ')', '[': ']', '{': '}'}
    
    # We only care about unclosed brackets that were opened
    for char in text:
        if char in bracket_map:
            stack.append(bracket_map[char])
        elif char in bracket_map.values():
            if stack and stack[-1] == char:
                stack.pop()
            else:
                # If we see a stray closer that doesn't match the stack, 
                # we don't pop, as the code is already malformed there.
                pass

    # Append missing closers in reverse order (FILO)
    # e.g., if stack is [']', ')'], it appends ')]'
    if stack:
        text += "".join(reversed(stack))

    # 4. Final Cleanup
    # Remove any trailing whitespace left after appending
    return text.strip()

# =============================================================================
# Function 1: sec_test_gen
# =============================================================================
def sec_test_gen(current_filename_path: str, test_case_filename_path: str, mutant_filename_path: str, output_directory: str) -> str:
    """
    Generates extended Python test cases for a C source file and its mutant,
    stores the new test file in the given output directory.
    """
    # Logic to handle specific CWE path formatting
    if "CWE-" in output_directory:
        # normpath removes trailing slashes so basename correctly gets the folder name
        # e.g., "./CWE-125/" becomes "CWE-125"
        clean_path = os.path.normpath(output_directory)
        cwe_folder_name = os.path.basename(clean_path)
        
        # Append the new sub-directory name
        output_directory = os.path.join(output_directory, f"new-tests-{cwe_folder_name}")
        logging.info(f"Output directory modified to: {output_directory}")
    os.makedirs(output_directory, exist_ok=True)


    all_header_content = get_includes_as_string(include_dir="./includes")

    with open(test_case_filename_path, 'r', encoding='utf-8') as file:
        string_test_case_filename = file.read()
    with open(current_filename_path, 'r', encoding='utf-8') as file:
        string_current_filename = file.read()
    with open(mutant_filename_path, 'r', encoding='utf-8') as file:
        file_MUTANT = file.read()

    INSTRUCT_3 = (
        "What follows is two versions of a C file under test. "
        "An original correct file and a mutated version of that file, "
        "which represents new bugs of the specified CWE type which is mostly written in the mutant file as comments. "
        "Each bug is delimited by the comment pair `// MUTANT <START>' and `// MUTANT <END>'. "
        "The original C file and its mutant are accompanied by a set of existing test cases that contains unit tests "
        "for the original correct file under test. "
        "This is the original version of the file: '''{" + string_current_filename + "}'''. "
        "This is the mutated version: '''{" + file_MUTANT + "}'''. "
        "Here is the existing test suite: '''{" + string_test_case_filename + "}'''. "
        "Write an extended version of the test class that contains extra test cases that SHOULD FAIL on the mutant version "
        "but MUST PASS on the original version of the file. "
        "_______________________________________________________"
        "IMPORTANT Instruction:"
        "THIS NEW TEST CASES ALL MUST PASS IN THE ORIGINAL C FILE. MUST PASS ON ORIGINAL. MUST FAIL ON MUTANT."
        "The new testcase file must have the original import modules, same runner functions and structures of pytest libraries."
        "The new testcase file MUST NOT have any technical compile or other errors."
        "The new testcase file will contain testcases TOGETHER that pass on original C version, but fail on mutant version."
        "But the new testcases will be run separately when run against original C version and then run against mutant version,"
        "so that tests designed to pass on original C version will not be considered even running against mutant version and "
        "tests designed to fail on mutant will not be considered even running against the original C version."
        "_______________________________________________________"
        "Extra Instructions:"
        "You must keep the comments EXACTLY as given in the original testcase file. "
        "DO NOT INCLUDE ANYTHING for any help like 'input', 'output', 'CTRL', etc. or anything without comments at the start/end of the file."
        "DO NOT INCLUDE MARKDOWN (```python...```) python CODEBLOCKS at start/end of your file. "
        "USE STANDARD #include 'filename.h' STATEMENTS. DO NOT COPY HEADER CONTENT.]"
    )

    # --- LLM Call using gemini---
    response = client.models.generate_content(model="gemini-3-flash-preview", contents=INSTRUCT_3)
    file_content_new_testcases = clean_llm_markdown(response.text)

    # # --- LLM Call using gpt---
    # response = client_gpt.responses.create(model="gpt-5-mini", input=INSTRUCT_3)
    # file_content_new_testcases = clean_llm_markdown(response.output_text)

    # Compose output filename using the format 
    issue_file_name = os.path.basename(mutant_filename_path)
    issue_root, _ = os.path.splitext(issue_file_name)
    if issue_root.endswith("_mutant"):
        issue_root = issue_root[:-7]
    new_testcase_filename = f"{issue_root}_newtest.py"
    new_testcase_filename_path = os.path.join(output_directory, new_testcase_filename)

    with open(new_testcase_filename_path, "w", encoding="utf-8") as file:
        file.write(file_content_new_testcases)

    return new_testcase_filename_path


# =============================================================================
# Function 1v2: sec_test_gen
# =============================================================================
def baseline_mutant_gen(current_filename_path: str, test_case_filename_path: str, baseline_newtest_filename_path: str, issue_filepath: str, output_directory: str) -> str:
    """
    Generates extended Python test cases for a C source file and its mutant,
    stores the new test file in the given output directory.
    """
    # Logic to handle specific CWE path formatting modified to use provided directory directly
    os.makedirs(output_directory, exist_ok=True)
    logging.info(f"Output directory set to: {output_directory}")

    # (Original logic for reading files remains unchanged)
    # all_header_content = get_includes_as_string(include_dir="./includes")
    with open(test_case_filename_path, 'r', encoding='utf-8') as file:
        string_test_case_filename = file.read()
    with open(current_filename_path, 'r', encoding='utf-8') as file:
        string_current_filename = file.read()
    with open(baseline_newtest_filename_path, 'r', encoding='utf-8') as file:
        file_baseline_newtest = file.read()
    with open(issue_filepath, 'r', encoding='utf-8') as f:
        issue_content = f.read()

    INSTRUCT_3 = (
        "PRIMARY INSTRUCTIONS:"
        "What follows is an original source task file followed by two versions of a testcase file, "
        "an original test file and an extended testcase file, both against the original source file."
        "This is the original source task file: '''{" + string_current_filename + "}'''. "
        "This is the original test file: '''{" + string_test_case_filename + "}'''. "
        "This is the extended test file: '''{" + file_baseline_newtest + "}'''. "
        "Finally, you are given a security issue file: '''{" + issue_content + "}'''. "
        " Write a new version of the ORIGINAL SOURCE TASK file in which the function is replaced by a new version "
        "that contains a typical bug that introduces a SECURITY violation similar to the above issue file. "
        "Delimit the mutated part using the comment-pair '// MUTANT <START>' and '// MUTANT <END>'. "
        "_______________________________________________________"
        "MUST-FOLLOW Instructions:"
        "TRY TO PRODUCE A MUTANT INTRODUCing the NEW CWE TYPE, ACCORDING TO THE GIVEN ISSUE FILE. DO NOT CHANGE THE ORIGINAL SECURITY ISSUE IN ANY WAY, SO THAT EXISTING ALL TEST CASES PASSes YOUR MUTANT."
        "YOUR MAIN TASK and FOCUS WILL BE TO PRODUCE A MUTANT THAT WILL FAIL BY THE EXTENDED TEST FILE, that means the EXTENDED TEST FILE CATCHES YOUR MUTANT with new CWE type - THIS IS THE MOST IMPORTANT REQUIREMENT." 
        "The produced mutant MUST BE BUILDABLE. No import module error will be present. This means, add ONLY STANDARD LIBRARIES."
        "_______________________________________________________"
        "Additional Instructions:"
        "DO NOT INCLUDE ANYTHING for any help like 'input', 'output', 'CTRL', etc. or anything without comments at the start/end of the file."
        "DO NOT INCLUDE MARKDOWN (```python...```) python CODEBLOCKS at start/end of your file. "
        "USE STANDARD #include 'filename.h' STATEMENTS. DO NOT COPY HEADER CONTENT.]"
    )

    # --- LLM Call using gpt---
    # Assuming client_gpt and clean_llm_markdown are defined globally as in your original script
    response = client_gpt.responses.create(model="gpt-4o-mini", input=INSTRUCT_3)
    raw_text = response.output_text
    file_content_full = clean_llm_markdown(raw_text)

    # --- Construct Filenames ---
    # Target naming logic: Take the baseline newtest filename, replace _bNewtest.py with _bMutant.c
    newtest_base = os.path.basename(baseline_newtest_filename_path)
    mutant_filename = newtest_base.replace("_bNewtest.py", "_bMutant.c")
    
    path_mutant = os.path.join(output_directory, mutant_filename)

    # --- Write to File ---
    with open(path_mutant, "w", encoding="utf-8") as f:
        f.write(file_content_full)

    return path_mutant

if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("Usage: python3 baseline_mutant_gen.py <path_to_c_file> <path_to_existing_test> <path_to_baseline_newtests> <path_to_issue_file> <output_directory>")
        sys.exit(1)

    current_file = sys.argv[1]
    existing_test_case = sys.argv[2]
    new_test_case = sys.argv[3]
    issue_filepath = sys.argv[4]
    output_directory = sys.argv[5]

    baseline_mutant_filename_path = baseline_mutant_gen(current_file, existing_test_case, new_test_case, issue_filepath, output_directory)
    print(baseline_mutant_filename_path)

    # python3 scripts/baseline_mutant_gen.py ./CWEval/benchmark/core/c/cwe_020_0_c_task.c ./CWEval/benchmark/core/c/cwe_020_0_c_test.py ./CWEval/benchmark/core/c/CWE-835/baseline/baseline-new-tests-CWE-835/CWE-835_issue_1_cwe_020_0_c_task_bNewtest.py security_issues_FINAL_v5_with_cwe/CWE-835/CWE-835_issue_1.txt ./CWEval/benchmark/core/c/CWE-835/baseline/baseline-mutants-all