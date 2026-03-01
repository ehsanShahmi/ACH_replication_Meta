# python3 scripts/sec_test_gen.py ./CWEval/benchmark/core/c/cwe_020_0_c_task.c ./CWEval/benchmark/core/c/cwe_020_0_c_test.py ./CWEval/benchmark/core/c/CWE-125/non-eq-CWE-125/CWE-125_issue_2_cwe_020_0_c_task_mutant.c ./CWEval/benchmark/core/c/CWE-125/

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

def clean_llm_markdown(input_string) -> str:
    # Regex to match ```language_name ... ``` and capture the content inside
    # it handles cases with or without a language name (like 'python', 'c', etc.)
    pattern = r'^```(?:\w+)?\n(.*?)\n```$'
    
    # Use re.DOTALL to make '.' match newlines
    # Use re.MULTILINE if the markdown is part of a larger string
    cleaned = re.sub(pattern, r'\1', input_string.strip(), flags=re.DOTALL)
    
    return cleaned

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
# Function 2: sec_test_gen_cweval_c
# =============================================================================
def sec_test_gen_cweval_c(current_filename_path: str, test_case_filename_path: str, mutant_filename_path: str, output_directory: str) -> str:
    """
    Similar to sec_test_gen, but uses the CWEVAL-style prompt and runner code.
    Stores new test script into output_directory.
    """
    os.makedirs(output_directory, exist_ok=True)
    all_header_content = get_includes_as_string(include_dir="./includes")

    with open(test_case_filename_path, 'r', encoding='utf-8') as file:
        string_test_case_filename = file.read()
    with open(current_filename_path, 'r', encoding='utf-8') as file:
        string_current_filename = file.read()
    with open(mutant_filename_path, 'r', encoding='utf-8') as file:
        file_MUTANT = file.read()

    # --- Runner code to be appended at the end of the generated test ---
    main_runner_code = """
import sys
import os
import subprocess

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 this_script.py <path_to_c_file_to_test>")
        sys.exit(1)
    
    c_file_path = sys.argv[1]
    if not os.path.exists(c_file_path):
        print(f"Error: C file not found at {c_file_path}")
        sys.exit(1)
    
    executable_path = "./outputs/test_executable"
    include_dir = "./includes"
    compile_cmd = ["gcc", "-w", f"-I{include_dir}", c_file_path, "-o", executable_path]
    compile_result = subprocess.run(compile_cmd, capture_output=True, text=True)
    if compile_result.returncode != 0:
        print("COMPILATION FAILED:")
        print(compile_result.stderr)
        sys.exit(1)
    
    run_result = subprocess.run([executable_path], capture_output=True, text=True)
    vulnerability_detected = (run_result.returncode != 0)
    if vulnerability_detected:
        print("--- TEST FAILED (Vulnerability found!) ---")
        sys.exit(1)
    else:
        print("--- TEST PASSED (No vulnerability found) ---")
        sys.exit(0)

if __name__ == "__main__":
    main()
"""
    INSTRUCT_3 = f"""
The following content shows two versions of a C file (original and mutated), along with a test suite.
Original file:
'''c
{all_header_content}
{string_current_filename}
'''

Mutated file (contains bugs marked with // MUTANT comments):
'''c
{file_MUTANT}
'''

Existing Python unit tests (that pass on the original):
'''python
{string_test_case_filename}
'''

Write a new Python test suite that adds stronger tests that should FAIL on the mutant but PASS on the original file.
RULES:
- No markdown or code block markers.
- The output must be a single valid Python file.
- Append the following runner code verbatim to the end:

--- START REQUIRED CODE ---
{main_runner_code}
--- END REQUIRED CODE ---
"""

    response = client.models.generate_content(model="gemini-2.5-pro", contents=INSTRUCT_3)
    file_content_new_testcases = response.text

    # Compose output filename
    current_filename_basename = os.path.basename(current_filename_path)
    current_filename_root, extension = os.path.splitext(current_filename_basename)
    test_case_filename_basename = os.path.basename(test_case_filename_path)
    test_case_filename_root, extension_testcase = os.path.splitext(test_case_filename_basename)

    new_testcase_filename = f"{current_filename_root}_newtest{extension_testcase}"
    new_testcase_filename_path = os.path.join(output_directory, new_testcase_filename)

    with open(new_testcase_filename_path, "w", encoding="utf-8") as file:
        file.write(file_content_new_testcases)

    return new_testcase_filename_path


# =============================================================================
# CLI Interface for Direct Execution
# =============================================================================
if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python3 sec_test_gen.py <path_to_c_file> <path_to_existing_test> <path_to_mutant> <output_directory>")
        sys.exit(1)

    current_file = sys.argv[1]
    existing_test_case = sys.argv[2]
    mutant_file = sys.argv[3]
    output_directory = sys.argv[4]

    new_testcase_filename_path = sec_test_gen(current_file, existing_test_case, mutant_file, output_directory)
    print(new_testcase_filename_path)