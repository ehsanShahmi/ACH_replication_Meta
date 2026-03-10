# python3 scripts/baseline_genLLM.py security_issues_FINAL_v5_with_cwe/CWE-119/CWE-119_issue_131.txt CWEval/benchmark/core/c/cwe_020_0_c_task.c CWEval/benchmark/core/c/cwe_020_0_c_test.py CWEval/benchmark/core/c/CWE-119/new-tests-CWE-119/baseline/
# models used for the project: gemma-3-27b-it, gemini-2.5-flash, gemini-2.5-pro, gemini-3-flash-preview, gemini-3-pro-preview


from dotenv import load_dotenv
load_dotenv()
from google import genai
from google.genai import types
import pandas as pd
import numpy as np
import coverage as cv
import os
import subprocess
from pathlib import Path
import sys
import unittest
import io
import openai
import sys
import os
import glob
client = genai.Client()
client_gpt = openai.OpenAI()




def get_includes_as_string(include_dir="./includes") -> str:
    """
    Reads all files in the includes directory and formats them into a single string 
    with clear boundaries for the LLM.
    """
    combined_includes = ""
    # Find all .h files in the specified directory
    header_files = glob.glob(os.path.join(include_dir, '*.h'))
    
    for file_path in header_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                # Use a clear markdown structure for the LLM context
                combined_includes += f"\n--- START HEADER FILE: {os.path.basename(file_path)} ---\n"
                combined_includes += content
                combined_includes += f"\n--- END HEADER FILE: {os.path.basename(file_path)} ---\n"
        except IOError as e:
            print(f"Warning: Could not read file {file_path}: {e}")
            continue
            
    return combined_includes


import re
import os
import sys

def clean_llm_markdown(input_string) -> str:
    # Regex to match ```language_name ... ``` and capture the content inside
    # it handles cases with or without a language name (like 'python', 'c', etc.)
    pattern = r'^```(?:\w+)?\n(.*?)\n```$'
    
    # Use re.DOTALL to make '.' match newlines
    # Use re.MULTILINE if the markdown is part of a larger string
    cleaned = re.sub(pattern, r'\1', input_string.strip(), flags=re.DOTALL)
    
    return cleaned

def mutator(issue_filepath: str, current_filename_path: str, test_case_filename_path: str, output_directory: str) -> str:
    """
    Generates a mutant from the given issue, code, and test files.
    Saves mutant into the specified output directory.
    """
    # Ensure output dir exists
    os.makedirs(output_directory, exist_ok=True)
    
    # --- Load includes and contents ---
    all_header_content = get_includes_as_string(include_dir="./includes")

    with open(issue_filepath, 'r', encoding='utf-8') as f:
        issue_content = f.read()

    with open(test_case_filename_path, 'r', encoding='utf-8') as file:
        string_test_case_filename = file.read()

    with open(current_filename_path, 'r', encoding='utf-8') as file:
        string_current_filename = file.read()

    # --- LLM Prompt ---
    INSTRUCT_1 = (
        "INSTRUCTION: Here is a file under test and a file with some unit tests for the file under test."
        "{" + string_current_filename + "}."
        "{" + string_test_case_filename + "}."
        " Write a new test file with more tests in which the coverage will be increased than the original test file."
        " Your new test file should also handle testcases concerning security violations introduced in the context."
        " YOUR NEW TESTSUITE MUSS PASS THE ORIGINAL SOURCE FILE."
        "______________________________________________________________________________________"
        "IMPORTANT instructions: "
        "The produced testfile MUST BE BUILDABLE. No import module error will be present. This means, add ONLY STANDARD LIBRARIES."
        "______________________________________________________________________________________"
        "Extra instructions: "
        "Your new testsuite file must have the original import modules, same runner functions and structures of pytest libraries."
        "It MUST NOT have any technical compile or other errors."
        "You must keep the comments EXACTLY as given in the original testcase file. "
        "DO NOT INCLUDE ANYTHING for any help like 'input', 'output', 'CTRL', etc. or anything without comments at the start/end of the file."
        "DO NOT INCLUDE MARKDOWN (```python...```) python CODEBLOCKS at start/end of your file. "
        "USE STANDARD #include 'filename.h' STATEMENTS. DO NOT COPY HEADER CONTENT.]"
    )
    PROMPT1 = "CONTEXT: " + issue_content + " " + INSTRUCT_1

    
    # --- Generate new mutant content ---
    response = client.models.generate_content(model="gemini-2.5-flash", contents=PROMPT1)
    file_content_mutant = clean_llm_markdown(response.text)

    # --- LLM Call using gpt---
    # response = client_gpt.responses.create(model="gpt-4o-mini", input=PROMPT1)
    # file_content_mutant = clean_llm_markdown(response.output_text)

    # --- Build mutant filename ---
    current_filename_basename = os.path.basename(current_filename_path)
    current_filename_root, extension = os.path.splitext(current_filename_basename)

    issue_filename = os.path.basename(issue_filepath)
    issue_root, _ = os.path.splitext(issue_filename)

    # Example: CWE-120_issue_2_math_task_mutant.c
    new_mutant_filename = f"{issue_root}_{current_filename_root}_bNewtest.py"
    mutant_filename_path = os.path.join(output_directory, new_mutant_filename)

    # --- Write mutant file ---
    with open(mutant_filename_path, 'w', encoding='utf-8') as file:
        file.write(file_content_mutant)

    return mutant_filename_path


if __name__ == "__main__":
    # Expect 4 arguments
    if len(sys.argv) != 5:
        print("Usage: python3 mutator.py <path_to_issue_file> <path_to_c_file> <path_to_test_file> <output_directory>")
        sys.exit(1)

    issue_filepath = sys.argv[1]
    current_file = sys.argv[2]
    existing_test_case = sys.argv[3]
    output_directory = sys.argv[4]

    # Check paths
    for path in [issue_filepath, current_file, existing_test_case]:
        if not os.path.exists(path):
            print(f"Error: file not found at '{path}'")
            sys.exit(1)

    mutant_filename = mutator(issue_filepath, current_file, existing_test_case, output_directory)
    print(mutant_filename)