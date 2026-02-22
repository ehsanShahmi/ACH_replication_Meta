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
        " Write a new version of this file under test in which the function is replaced by a new version "
        "that contains a typical bug that introduces a SECURITY violation similar to context. "
        "Delimit the mutated part using the comment-pair '// MUTANT <START>' and '// MUTANT <END>'. "
        "______________________________________________________________________________________"
        "IMPORTANT instructions: "
        "THE MUTANT MUST PASS ALL THE EXISTING TEST CASES. YOU HAVE TO INTRODUCE A NEW CWE TYPE, ACCORDING TO THE GIVEN CONTEXT."
        "YOUR MAIN TASK WILL BE TO INTRODUCE THE NEW CWE TYPE ACCORDING TO THE FILE UNDER TEST. DO NOT JUST MIMIC THE SITUATION GIVEN IN THE CONTEXT."
        "DO NOT CHANGE THE ORIGINAL SECURITY ISSUE IN ANY WAY, SO THAT EXISTING ALL TEST CASES PASS YOUR MUTANT."
        "______________________________________________________________________________________"
        "Extra instructions: "
        "[DO NOT INCLUDE MARKDOWN CODEBLOCKS (```c...``` or ```python...```) AT THE START AND END OF THE FILE. "
        "WHEN GENERATING THE FINAL MUTANT CODE, ONLY USE STANDARD #include 'filename.h' STATEMENTS. "
        "DO NOT COPY THE CONTENTS OF THE HEADERS INTO THE FINAL CODE FILE.]"
    )
    PROMPT1 = "CONTEXT: " + issue_content + " " + INSTRUCT_1

    
    # --- Generate new mutant content ---
    response = client.models.generate_content(model="gemini-2.5-flash", contents=PROMPT1)
    file_content_mutant = clean_llm_markdown(response.text)

    # --- Build mutant filename ---
    current_filename_basename = os.path.basename(current_filename_path)
    current_filename_root, extension = os.path.splitext(current_filename_basename)

    issue_filename = os.path.basename(issue_filepath)
    issue_root, _ = os.path.splitext(issue_filename)

    # Example: CWE-120_issue_2_math_task_mutant.c
    new_mutant_filename = f"{issue_root}_{current_filename_root}_mutant{extension}"
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