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
client = genai.Client()
def luhn_summarize(text, sentence_count=2):
    # Parse the input text
    parser = PlaintextParser.from_string(text, Tokenizer("english"))
    # Initialize summarizer with stemmer
    summarizer = LuhnSummarizer(Stemmer("english"))
    summarizer.stop_words = get_stop_words("english")
    # Generate summary
    summary = summarizer(parser.document, sentence_count)
    return summary






# We load the dataset containing the security issues (Basim's SecVulEval dataset)
secVulEvalfull = pd.read_parquet("hf://datasets/arag0rn/SecVulEval/data/train-00000-of-00001.parquet")

# We load only the part of the dataset with vulnerabilites. no need for the fixed patches of that dataset. 
# Also, we take only the linux commit messages, since linux issues are provided in clearer ways.
secVulEval = secVulEvalfull[secVulEvalfull['is_vulnerable'] != False].reset_index(drop=True)
secVulEval = secVulEval[secVulEval['project'] == 'linux'].reset_index(drop=True)
# Now secVulEval contains the vulnerable part of the dataset with linux issues only - not the patched functions.
# print (secVulEval) # viewing the issues. There are 2793 issues in total.

# We here take the FIRST instance of this dataset. We take the "commit message" as the first security issue.
security_issues = secVulEval['commit_message']
security_issue = security_issues[0]
# print (security_issue)

# After loading, now we try to make a summary of it. This can either be done using an LLM, manually or by using libraries.
issue_summary = luhn_summarize(security_issue, 3)
# SUMMARY = "".join(issue_summary)
# # print (issue_summary)
# # for sentence in issue_summary:
# #     SUMMARY = SUMMARY + sentence
# print (SUMMARY)
SUMMARY = "A patch to the Linux kernel's NetLabel subsystem has fixed two critical bugs in the handling of Commercial IP Security Options (CIPSO) tags. The corrected flaws included an 'off-by-one' error that could cause a system crash and an array initialization bug that led to unpredictable security failures. By resolving these issues, the patch strengthens the overall security and stability of the system, ensuring reliable enforcement of network security policies."

# We now load our current code repo here. 
# The 'trial_index' is JUST A TEST.
trial_index = secVulEval.index[secVulEval['idx'] == 55][0]
commit_messages = secVulEval['commit_message']
func_bodies = secVulEval['func_body']
project_urls = secVulEval['project_url']
filepaths = secVulEval['filepath']
current_code_repo = project_urls[trial_index] + '/tree/master/' + filepaths[trial_index]
# print ('\n'+file_under_test+'\n')



# We create test cases, that passes and builds on the current_code_repo. THIS WILL NOT BE DONE AND COMMENTED LATER ON.
# INSTRUCT_0 = "Generate a buildable C code for 5 test cases using the standard unit test format for C against the following file, having the following security issue summary and context. Take help from the provided file URL. DO NOT output any suggestions or instructions. DO NOT include the include the function under test in this C code. The test cases MUST BE BUILDABLE AND PASSABLE ON THE FILE UNDER TEST."
# PROMPT0 = current_code_repo + INSTRUCT_0
# response0 = client.models.generate_content(
#     model="gemini-2.5-pro", 
#     contents=PROMPT0
# )
# INIT_TEST_CASES = f"init_testSuites\init_testSuite{trial_index}.c"
# file_content = response0.text
# with open(INIT_TEST_CASES, 'w', encoding='utf-8') as file:
#     file.write(file_content)



# We manually tested the existing test cases which pass.
# We now create the mutant_repo
INSTRUCT_1 = "Here is a file under test (as an URL) and a test suite of 5 test cases for the file under test. Write a new version of this file in which each function is replaced by a new version of that function that contains a typical bug that introduces a SECURITY violation. Delimit the mutated part using the comment-pair '// MUTANT <START>' and '// MUTANT <END>'. [Comment out any suggestions in the mutant file.]"
INIT_TEST_CASES = f"init_testSuites\init_testSuite{trial_index}.c"
CONTEXT = "The provided text describes a security vulnerability within the Linux kernel's NetLabel framework, which manages security labels for network traffic. " \
"The issue was specifically in the handling of the CIPSO protocol, a standard for conveying security information in network packets. " \
"A core function, netlbl_cipsov4_add_common(), which processes security configurations, contained two critical bugs: an 'off-by-one' error that created a buffer overflow vulnerability, and a failure to properly initialize a data array. These flaws could lead to system instability and create security holes by allowing security policies to be compromised by random data. A patch was created to fix these bugs, securing the integrity of Linux systems using CIPSO for network security."
# PROMPT1 = SUMMARY + CONTEXT + INIT_TEST_CASES + current_code_repo + INSTRUCT_1
# response1 = client.models.generate_content(
#     model="gemini-2.5-pro", 
#     contents=PROMPT1
# )
# security_Mutants = f"mutants\mutant{trial_index}.c"
# file_content1 = response1.text
# with open(security_Mutants, 'w', encoding='utf-8') as file:
#     file.write(file_content1)
# CANDI_MUTANT = response1.text

CANDI_MUTANT = f"mutants\mutant{trial_index}.c"
INSTRUCT_2 = "I'm going to show you two slightly different versions of a C file. Here is the first version of the file:"+ current_code_repo +"Here is the second version of the C file:"+ CANDI_MUTANT +"If the first version of the file always do exactly the same thing as the second version, just respond with '{yes}'. However, if the two versions of the file are not equivalent, respond with '{no}', and give an explanation of how execution of the first version can produce a different behaviour to execution of the second version."
PROMPT2 = current_code_repo + CANDI_MUTANT + INSTRUCT_2
# response2 = client.models.generate_content(
#     model="gemini-2.5-pro", 
#     contents=PROMPT2
# )

# file_content2 = response2.text
output_dir = "equivalency"
equi_ans = os.path.join(output_dir, f"equi_LLM_ans{trial_index}.c")
# os.makedirs(output_dir, exist_ok=True) # This is the key line
# with open(equi_ans, 'w', encoding='utf-8') as file:
#     file.write(file_content2)

# Equi_Checker_ANS = response2.text

INSTRUCT_3 = "What follows is two versions of a C file under test. An original correct file and a mutated version of that file that contains one mutant per C Function, each of which represents a bug. Each bug is delimited by the comment pair ‘// MUTANT <START>’ and ‘// MUTANT <END>’. The original C file and its mutant are followed by a set of existing test cases that contains unit tests for the original correct file under test. This is the original version of the file under test:" + current_code_repo+ ". This is the mutated version of the file under test:" +CANDI_MUTANT+". Here is the existing test suite:" +INIT_TEST_CASES+". Write an extended version of the test suite that contains three more extra test cases that will fail on the mutant version of the file, but would pass on the correct version."
PROMPT3 = current_code_repo + CANDI_MUTANT + INIT_TEST_CASES + INSTRUCT_3
response3 = client.models.generate_content(
    model="gemini-2.5-pro", 
    contents=PROMPT3
)
file_content3 = response3.text
output_dir = "new_test_case"
new_tests = os.path.join(output_dir, f"new_test_cases{trial_index}.c")
os.makedirs(output_dir, exist_ok=True)
with open(new_tests, 'w', encoding='utf-8') as file:
    file.write(file_content3)