from datasets import load_dataset
from dotenv import load_dotenv
load_dotenv()
from google import genai
from google.genai import types
from sumy.parsers.plaintext import PlaintextParser
from sumy.nlp.tokenizers import Tokenizer
from sumy.summarizers.luhn import LuhnSummarizer
from sumy.nlp.stemmers import Stemmer
from sumy.utils import get_stop_words
import nltk
# nltk.download('punkt_tab')
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
client = genai.Client()
client_gpt = openai.OpenAI()
def luhn_summarize(text, sentence_count=2):
    # Parse the input text
    parser = PlaintextParser.from_string(text, Tokenizer("english"))
    # Initialize summarizer with stemmer
    summarizer = LuhnSummarizer(Stemmer("english"))
    summarizer.stop_words = get_stop_words("english")
    # Generate summary
    summary = summarizer(parser.document, sentence_count)
    return summary
filename = "secVulEval_dataset/train-00000-of-00001.parquet"




# Declaring the global variables
# secVulEvalfull = pd.read_parquet(filename)
# secVulEval = secVulEvalfull[secVulEvalfull['is_vulnerable'] != False].reset_index(drop=True)
# secVulEval = secVulEval[secVulEval['project'] == 'linux'].reset_index(drop=True)
# security_issues = secVulEval['commit_message']
security_issues_1 = "[media] dvb-usb-v2: avoid use-after-free I ran into a stack frame size warning because of the on-stack copy of the USB device structure: drivers/media/usb/dvb-usb-v2/dvb_usb_core.c: In function 'dvb_usbv2_disconnect': drivers/media/usb/dvb-usb-v2/dvb_usb_core.c:1029:1: error: the frame size of 1104 bytes is larger than 1024 bytes [-Werror=frame-larger-than=] Copying a device structure like this is wrong for a number of other reasons too aside from the possible stack overflow. One of them is that the dev_info() call will print the name of the device later, but AFAICT we have only copied a pointer to the name earlier and the actual name has been freed by the time it gets printed. This removes the on-stack copy of the device and instead copies the device name using kstrdup(). I'm ignoring the possible failure here as both printk() and kfree() are able to deal with NULL pointers.>"
CONTEXT = "The provided text describes a security vulnerability within the Linux kernel's NetLabel framework, which manages security labels for network traffic. The issue was specifically in the handling of the CIPSO protocol, a standard for conveying security information in network packets. A core function, netlbl_cipsov4_add_common(), which processes security configurations, contained two critical bugs: an 'off-by-one' error that created a buffer overflow vulnerability, and a failure to properly initialize a data array. These flaws could lead to system instability and create security holes by allowing security policies to be compromised by random data. A patch was created to fix these bugs, securing the integrity of Linux systems using CIPSO for network security."

# SUMMARY = "A patch to the Linux kernel's NetLabel subsystem has fixed two critical bugs in the handling of Commercial IP Security Options (CIPSO) tags. The corrected flaws included an 'off-by-one' error that could cause a system crash and an array initialization bug that led to unpredictable security failures. By resolving these issues, the patch strengthens the overall security and stability of the system, ensuring reliable enforcement of network security policies."

def summarizer(input_string: str) -> str:
    summary = luhn_summarize(input_string, 3)
    summary_as_string = " ".join(str(element) for element in summary)
    return summary_as_string


# # We now load our current code repo here. 
# # The 'trial_index' is JUST A TEST.
# trial_index = secVulEval.index[secVulEval['idx'] == 55][0]
# commit_messages = secVulEval['commit_message']
# func_bodies = secVulEval['func_body']
# project_urls = secVulEval['project_url']
# filepaths = secVulEval['filepath']
# current_code_repo = project_urls[trial_index] + '/tree/master/' + filepaths[trial_index]
# # print ('\n'+file_under_test+'\n')



# # We create test cases, that passes and builds on the current_code_repo. THIS WILL NOT BE DONE AND COMMENTED LATER ON.
# # INSTRUCT_0 = "Generate a buildable C code for 5 test cases using the standard unit test format for C against the following file, having the following security issue summary and context. Take help from the provided file URL. DO NOT output any suggestions or instructions. DO NOT include the include the function under test in this C code. The test cases MUST BE BUILDABLE AND PASSABLE ON THE FILE UNDER TEST."
# # PROMPT0 = current_code_repo + INSTRUCT_0
# # response0 = client.models.generate_content(
# #     model="gemini-2.5-pro", 
# #     contents=PROMPT0
# # )
# # INIT_TEST_CASES = f"init_testSuites\init_testSuite{trial_index}.c"
# # file_content = response0.text
# # with open(INIT_TEST_CASES, 'w', encoding='utf-8') as file:
# #     file.write(file_content)


# # We manually tested the existing test cases which pass.
# # We now create the mutant_repo
# # PROMPT1 = SUMMARY + CONTEXT + INIT_TEST_CASES + current_code_repo + INSTRUCT_1
# # response1 = client.models.generate_content(
# #     model="gemini-2.5-pro", 
# #     contents=PROMPT1
# # )
# # security_Mutants = f"mutants\mutant{trial_index}.c"
# # file_content1 = response1.text
# # with open(security_Mutants, 'w', encoding='utf-8') as file:
# #     file.write(file_content1)
# # CANDI_MUTANT = response1.text


def mutator(SUMMARY: str, CONTEXT: str, current_file: str, existing_test_case: str) -> str:
    base_dir = 'current_code_repo'
    testcases_dir = 'testcases'
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
    PROMPT1 = "CONTEXT:"+SUMMARY+" "+INSTRUCT_1
    response = client.models.generate_content(model="gemini-2.5-pro", contents=PROMPT1)
    # response_gpt = client_gpt.responses.create(model="gpt-5", input=[SUMMARY, EXISTING_TEST_CASES, current_code_repo, INSTRUCT_1])
    mutant_filename_path = os.path.join(base_dir, f"mutant_(latest)_{current_file}.c")
    os.makedirs(base_dir, exist_ok=True)
    file_content_mutant = response.text
    with open(mutant_filename_path, 'w', encoding='utf-8') as file:
        file.write(file_content_mutant)
    
    return mutant_filename_path




# CANDI_MUTANT = f"mutants\mutant{trial_index}.c"

# PROMPT2 = current_code_repo + CANDI_MUTANT + INSTRUCT_2
# # response2 = client.models.generate_content(
# #     model="gemini-2.5-pro", 
# #     contents=PROMPT2
# # )

# # file_content2 = response2.text
# output_dir = "equivalency"
# equi_ans = os.path.join(output_dir, f"equi_LLM_ans{trial_index}.c")
# # os.makedirs(output_dir, exist_ok=True) # This is the key line
# # with open(equi_ans, 'w', encoding='utf-8') as file:
# #     file.write(file_content2)

# # Equi_Checker_ANS = response2.text

def eqChecker(mutant: str, current_file: str) -> str:
    base_dir = 'current_code_repo'
    code_repo_filename = f'{current_file}.c'
    code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(code_repo_filename_path, 'r') as file:
        file_current_code_repo = file.read()
    MUTANT_filename_path = f'{mutant}'
    with open(MUTANT_filename_path, 'r') as file:
        MUTANT = file.read()

    
    INSTRUCT_2 = "I'm going to show you two slightly different versions of a C file. Here is the first version of the file:'''"+ file_current_code_repo +"'''. Here is the second version of the C file:'''"+ MUTANT +"'''." +"INSTRUCTION: If the first version of the file will always do exactly the same thing as the second version, just respond with '{yes}'. However, if the two versions of the file are not equivalent, respond with '{no}', and give an explanation of how execution of the first version can produce a different behaviour to execution of the second version."
    PROMPT2 = INSTRUCT_2
    response = client.models.generate_content(model="gemini-2.5-pro", contents=PROMPT2)
    # response_gpt = client_gpt.responses.create(model="gpt-5", input=[original_repo, MUTANT, INSTRUCT_2])
    file_content_eq = response.text
    output_dir = "equivalency"
    equi_ans = os.path.join(output_dir, f"equi_LLM_ans_(latest)_{current_file}.c")
    os.makedirs(output_dir, exist_ok=True)
    with open(equi_ans, 'w', encoding='utf-8') as file:
        file.write(file_content_eq)

    return file_content_eq



# PROMPT3 = current_code_repo + CANDI_MUTANT + INIT_TEST_CASES + INSTRUCT_3
# response3 = client.models.generate_content(
#     model="gemini-2.5-pro", 
#     contents=PROMPT3
# )
# file_content3 = response3.text
# output_dir = "new_test_case"
# new_tests = os.path.join(output_dir, f"new_test_cases{trial_index}.c")
# os.makedirs(output_dir, exist_ok=True)
# with open(new_tests, 'w', encoding='utf-8') as file:
#     file.write(file_content3)

def sec_test_gen(current_file: str, existing_test_case: str, mutant: str):
    base_dir = 'current_code_repo'
    testcases_dir = 'testcases'
    test_case_filename = f'{existing_test_case}.c'
    test_case_filename_path = os.path.join(base_dir, testcases_dir, test_case_filename)
    with open(test_case_filename_path, 'r') as file:
        file_existing_tests = file.read()
    code_repo_filename = f'{current_file}.c'
    code_repo_filename_path = os.path.join(base_dir, code_repo_filename)
    with open(code_repo_filename_path, 'r') as file:
        file_current_code_repo = file.read()
    MUTANT_filename_path = f'{mutant}'
    # MUTANT_filename_path = os.path.join(base_dir, MUTANT_filename)
    with open(MUTANT_filename_path, 'r') as file:
        file_MUTANT = file.read()
    header_filename = f'{current_file}.h'
    header_filename_path = os.path.join(base_dir, header_filename)
    with open(header_filename_path, 'r') as file:
        file_header = file.read()


    INSTRUCT_3 = "What follows is two versions of a C file under test. An original correct file and a mutated version of that file that contains one mutant per C function, each of which represents a bug. Each bug is delimited by the comment pair `// MUTANT <START>' and `// MUTANT <END>'. The original C file and its mutant are followed by a set of existing test cases that contains unit tests for the original correct file under test. This is the original version of the file under test:'''{" +file_header+file_current_code_repo+ "}'''."+" This is the mutated version of the file under test:'''{" +file_MUTANT+". Here is the existing test suite:'''{" +file_existing_tests+"}'''."+" Write an extended version of the test class that contains extra test cases that MUST FAIL on the mutant version of the file, but MUST PASS on the correct version." +"[DO NOT ADD ANY NEW HELPER FUNCTIONS OR IMPORT MODULES IN THE TEST CASE FILE. DO NOT INCLUDE MARKDOWN CODEBLOCKS (```c...```) AT THE START AND END OF THE FILE.]"
    PROMPT3 = INSTRUCT_3
    response = client._models.generate_content(model="gemini-2.5-pro", contents=PROMPT3)
    # response_gpt = client_gpt.responses.create(model="gpt-4o", input=[current_code_repo, MUTANT, EXISTING_TEST_CASES, INSTRUCT_3])
    file_new_test_cases = response.text
    # output_dir = "new_test_case"
    new_tests = os.path.join(base_dir, testcases_dir, f"new_(latest)_{existing_test_case}.c")
    os.makedirs(output_dir, exist_ok=True)
    with open(new_tests, 'w', encoding='utf-8') as file:
        file.write(file_new_test_cases)

    return





def main():
    # loading dataset SecVulEval and reducing it using global variables.

    # Now we summarize the first issue
    summary = summarizer(security_issues_1)
    current_file = "my_functions"
    existing_test_case = "test_my_functions"

    # we now create the mutant for the file under test and the existing test cases.
    # candidate_mutant = mutator(summary, CONTEXT, current_file, existing_test_case)

    # we now check for the equivalency
    equi_checker = eqChecker("current_code_repo\mutant_(latest)_my_functions.c", current_file)

    # we now create the new testcases
    if (equi_checker[1] == 'n'):
        sec_test_gen(current_file, existing_test_case, "current_code_repo\mutant_(latest)_my_functions.c")
    else:
        print ("Equivalent mutant generated. We discard it and go out of the iteration for this file under test.")

    




if __name__ == "__main__":
    # This block checks if the script is being run as the main program.
    main()