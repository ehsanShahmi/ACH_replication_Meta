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




def mutator(SUMMARY: str, current_filename_path: str, test_case_filename_path: str) -> str:
    base_dir = 'current_code_repo'
    testcases_dir = 'testcases'
    all_header_content = get_includes_as_string(include_dir="./includes")
    mutant_dir = 'mutants'

    # test_case_filename = f'{existing_test_case}'
    # test_case_filename_path = os.path.join(base_dir, testcases_dir, test_case_filename)
    with open(test_case_filename_path, 'r') as file:
        string_test_case_filename = file.read()

    # code_repo_filename = f'{current_file}'
    # code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(current_filename_path, 'r') as file:
        string_current_filename = file.read()

    # # Use os.path.splitext() to get the filename root without the extension
    # filename_root, extension = os.path.splitext(current_file)
    # # Now use the root filename to build the header file path
    # header_filename = f'{filename_root}.h'
    # header_filename_path = os.path.join(base_dir, include_dir, header_filename)
    # with open(header_filename_path, 'r') as file:
    #     file_header = file.read()


    INSTRUCT_1 = "INSTRUCTION: Here is a file under test and a file with some unit tests for the file under test.{"+all_header_content+string_current_filename+"}.{"+string_test_case_filename+"}. Write a new version of this file under test in which each function is replaced by a new version of that same function that contains a typical bug that introduces a SECURITY violation similar to context. Delimit the mutated part using the comment-pair '// MUTANT <START>' and '// MUTANT <END>'. [DO NOT INCLUDE MARKDOWN CODEBLOCKS (```c...```) AT THE START AND END OF THE FILE. WHEN GENERATING THE FINAL MUTANT CODE, ONLY USE STANDARD #include 'filename.h' STATEMENTS. DO NOT COPY THE CONTENTS OF THE HEADERS INTO THE FINAL CODE FILE.]"

    PROMPT1 = "CONTEXT: "+SUMMARY+" "+INSTRUCT_1
    response = client.models.generate_content(model="gemini-3-pro-preview", contents=PROMPT1)
    # response_gpt = client_gpt.responses.create(model="gpt-5", input=[SUMMARY, EXISTING_TEST_CASES, current_code_repo, INSTRUCT_1])
    current_filename_basename = os.path.basename(current_filename_path) 
    current_filename_root, extension = os.path.splitext(current_filename_basename)
    new_mutant_filename = f"{current_filename_root}_mutant{extension}"
    mutant_filename_path = os.path.join(mutant_dir, new_mutant_filename)
    os.makedirs(mutant_dir, exist_ok=True)
    file_content_mutant = response.text
    with open(mutant_filename_path, 'w', encoding='utf-8') as file:
        file.write(file_content_mutant)
    
    return mutant_filename_path



if __name__ == "__main__":
    summary = sys.argv[1]
    current_file = sys.argv[2]
    existing_test_case = sys.argv[3]
    mutant_filename = mutator(summary, current_file, existing_test_case)
    print (mutant_filename)