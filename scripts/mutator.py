# from datasets import load_dataset
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
client = genai.Client()
client_gpt = openai.OpenAI()

def mutator(SUMMARY: str, current_file: str, existing_test_case: str) -> str:
    base_dir = 'current_code_repo'
    testcases_dir = 'testcases'
    mutant_dir = 'mutants'
    test_case_filename = f'{existing_test_case}.c'
    test_case_filename_path = os.path.join(base_dir, testcases_dir, test_case_filename)
    code_repo_filename = f'{current_file}.c'
    code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(test_case_filename_path, 'r') as file:
        file_existing_tests = file.read()
    with open(code_repo_filename_path, 'r') as file:
        file_current_code_repo = file.read()
    header_filename = f'{current_file}.h'
    header_filename_path = os.path.join(base_dir, header_filename)
    with open(header_filename_path, 'r') as file:
        file_header = file.read()


    INSTRUCT_1 = "INSTRUCTION: Here is a file under test and a file with some unit tests for the file under test.{"+file_header+file_current_code_repo+"}.{"+file_existing_tests+"}. Write a new version of this file under test in which each function is replaced by a new version of that same function that contains a typical bug that introduces a SECURITY violation similar to context. Delimit the mutated part using the comment-pair '// MUTANT <START>' and '// MUTANT <END>'. [DO NOT INCLUDE MARKDOWN CODEBLOCKS (```c...```) AT THE START AND END OF THE FILE.]"
    PROMPT1 = "CONTEXT: "+SUMMARY+" "+INSTRUCT_1
    response = client.models.generate_content(model="gemini-2.5-pro", contents=PROMPT1)
    # response_gpt = client_gpt.responses.create(model="gpt-5", input=[SUMMARY, EXISTING_TEST_CASES, current_code_repo, INSTRUCT_1])
    mutant_filename_path = os.path.join(mutant_dir, f"mutant_(latest)_{current_file}.c")
    os.makedirs(base_dir, exist_ok=True)
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