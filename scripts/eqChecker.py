# models used for the project: gemma-3-27b-it, gemini-2.5-flash, gemini-2.5-pro, gemini-3-flash-preview, gemini-3-pro-preview
#  python3 eqChecker.py ./CWEval/benchmark/core/c/CWE-119/CWE-119_issue_1_math_task_mutant.c ./CWEval/benchmark/core/c/math_task.c ./CWEval/benchmark/core/c/CWE-119/

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

import os
from pathlib import Path

def eqChecker(mutant_filename_path: str, current_filename_path: str, output_directory: str) -> str:
    """
    Compare an original C file and its mutant.
    Store the equivalency answer in the output directory.

    Output filename format:
        <mutant_base_name>_eq_ans.txt
    """
    # --- Read both code files ---
    with open(current_filename_path, 'r', encoding='utf-8') as f:
        string_current_filename = f.read()

    with open(mutant_filename_path, 'r', encoding='utf-8') as f:
        string_mutant = f.read()

    # --- Prompt for Gemini ---
    INSTRUCT_2 = (
        "I'm going to show you two slightly different versions of a C file. "
        "Here is the first version of the file: '''" + string_current_filename + "'''. "
        "Here is the second version of the C file: '''" + string_mutant + "'''. "
        "INSTRUCTION: If the first version of the file will always do exactly the same thing "
        "as the second version, just respond with '{yes}'. "
        "However, if the two versions of the file are not equivalent, respond with '{no}', "
        "and give a short explanation of how execution of the first version can produce different behavior."
    )

    # --- LLM Call ---
    response = client.models.generate_content(model="gemini-2.5-flash", contents=INSTRUCT_2)
    file_content_eq = response.text

    # --- Ensure output directory exists ---
    os.makedirs(output_directory, exist_ok=True)

    # --- Construct equivalency answer filename ---
    mutant_basename = os.path.basename(mutant_filename_path)
    mutant_root, _ = os.path.splitext(mutant_basename)
    output_filename = f"{mutant_root}_eq_ans.txt"
    output_path = os.path.join(output_directory, output_filename)

    # --- Write answer to file ---
    with open(output_path, 'w', encoding='utf-8') as file:
        file.write(file_content_eq)

    return file_content_eq


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 eqChecker.py <version1_c_file> <version2_c_file> <output_directory>")
        sys.exit(1)

    current_file = sys.argv[1]      # version 1
    mutant_file = sys.argv[2]       # version 2
    output_directory = sys.argv[3]

    if not os.path.exists(mutant_file):
        print(f"Error: mutant file not found at '{mutant_file}'")
        sys.exit(1)
    if not os.path.exists(current_file):
        print(f"Error: current file not found at '{current_file}'")
        sys.exit(1)
    os.makedirs(output_directory, exist_ok=True)

    # Fix: swap current_file and mutant_file so mutant is first to eqChecker
    eq_answer = eqChecker(mutant_file, current_file, output_directory)
    print(eq_answer)