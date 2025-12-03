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

def eqChecker(mutant_filename_path: str, current_filename_path: str) -> str:
    base_dir = 'current_code_repo'
    equi_dir = "equivalency"
    # code_repo_filename = f'{current_file}.c'
    # code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(current_filename_path, 'r') as file:
       string_current_filename = file.read()
    MUTANT_filename_path = mutant_filename_path
    with open(MUTANT_filename_path, 'r') as file:
        MUTANT_string = file.read()

    
    INSTRUCT_2 = "I'm going to show you two slightly different versions of a C file. Here is the first version of the file:'''"+ string_current_filename +"'''. Here is the second version of the C file:'''"+ MUTANT_string +"'''." +"INSTRUCTION: If the first version of the file will always do exactly the same thing as the second version, just respond with '{yes}'. However, if the two versions of the file are not equivalent, respond with '{no}', and give an explanation of how execution of the first version can produce a different behaviour to execution of the second version."
    PROMPT2 = INSTRUCT_2
    response = client.models.generate_content(model="gemini-2.5-pro", contents=PROMPT2)
    # response_gpt = client_gpt.responses.create(model="gpt-5", input=[original_repo, MUTANT, INSTRUCT_2])
    file_content_eq = response.text

    current_filename_basename = os.path.basename(current_filename_path) 
    current_filename_root, currentfile_extension = os.path.splitext(current_filename_basename)
    mutant_filename_basename = os.path.basename(mutant_filename_path) 
    mutant_filename_root, mutant_extension = os.path.splitext(current_filename_basename)
    
    equivalency_ans_filename = f"{current_filename_root}_equi_ans.txt"
    equi_ans = os.path.join(equi_dir, equivalency_ans_filename)
    os.makedirs(equi_dir, exist_ok=True)
    with open(equi_ans, 'w', encoding='utf-8') as file:
        file.write(file_content_eq)

    return file_content_eq


if __name__ == "__main__":
    mutant_file = sys.argv[1]
    current_file = sys.argv[2]
    equi_ans = eqChecker(mutant_file, current_file)

    print (equi_ans)