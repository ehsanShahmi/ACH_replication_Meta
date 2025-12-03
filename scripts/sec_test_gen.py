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
import glob
client = genai.Client()

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


def sec_test_gen(current_filename_path: str, test_case_filename_path: str, mutant_filename_path: str) -> str:
    base_dir = 'current_code_repo'
    testcases_dir = 'testcases'
    new_testcase_dir = 'new_testcase'
    all_header_content = get_includes_as_string(include_dir="./includes")

    # test_case_filename = f'{existing_test_case}.c'
    # test_case_filename_path = os.path.join(base_dir, testcases_dir, test_case_filename)
    with open(test_case_filename_path, 'r') as file:
        string_test_case_filename = file.read()

    # code_repo_filename = f'{current_file}.c'
    # code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(current_filename_path, 'r') as file:
        string_current_filename = file.read()

    # MUTANT_filename_path = f'{mutant}'
    # MUTANT_filename_path = os.path.join(base_dir, MUTANT_filename)
    with open(mutant_filename_path, 'r') as file:
        file_MUTANT = file.read()

    # header_filename = f'{current_file}.h'
    # header_filename_path = os.path.join(base_dir, header_filename)
    # with open(header_filename_path, 'r') as file:
    #     file_header = file.read()

    INSTRUCT_3 = "What follows is two versions of a C file under test. An original correct file and a mutated version of that file that contains one mutant per C function, each of which represents a bug. Each bug is delimited by the comment pair `// MUTANT <START>' and `// MUTANT <END>'. The original C file and its mutant are followed by a set of existing test cases that contains unit tests for the original correct file under test. This is the original version of the file under test:'''{" +all_header_content+string_current_filename+ "}'''."+" This is the mutated version of the file under test:'''{" +file_MUTANT+"}. Here is the existing test suite:'''{" +string_test_case_filename+"}'''."+" Write an extended version of the test class that contains extra test cases that MUST FAIL on the mutant version of the file, but MUST PASS on the correct version." +"[IN YOUR NEW TEST SUITE CLASS, THE FILE MUST RETURN FAILED IF ANY 1 TEST CASE FAILS ON THE MUTANT, NO NEED TO CHECK OTHER TEST CASES ANY MORE THEN. DO NOT INCLUDE MARKDOWN CODEBLOCKS (```c...```) AT THE START AND END OF THE FILE. WHEN GENERATING THE FINAL MUTANT CODE, ONLY USE STANDARD #include 'filename.h' STATEMENTS. DO NOT COPY THE CONTENTS OF THE HEADERS INTO THE FINAL CODE FILE. ]"

    PROMPT3 = INSTRUCT_3
    response = client._models.generate_content(model="gemini-2.5-flash", contents=PROMPT3)
    # response_gpt = client_gpt.responses.create(model="gpt-4o", input=[current_code_repo, MUTANT, EXISTING_TEST_CASES, INSTRUCT_3])
    file_content_new_testcases = response.text

    current_filename_basename = os.path.basename(current_filename_path) 
    current_filename_root, extension = os.path.splitext(current_filename_basename)
    new_testcase_filename = f"{current_filename_root}_new_testcase{extension}"
    new_testcase_filename_path = os.path.join(new_testcase_dir, new_testcase_filename)
    os.makedirs(new_testcase_dir, exist_ok=True)
    with open(new_testcase_filename_path, 'w', encoding='utf-8') as file:
        file.write(file_content_new_testcases)

    return new_testcase_filename_path


if __name__ == "__main__":
    mutant_file = sys.argv[2]
    current_file = sys.argv[1]
    existing_test_case = sys.argv[3]
    new_testcase_filename_path = sec_test_gen(current_file, existing_test_case, mutant_file)

    print (new_testcase_filename_path)