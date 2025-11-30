from datasets import load_dataset
import subprocess
from pathlib import Path
import sys
import unittest
import io
import pandas as pd
import os


def load_issues(issue_dataset: pd.DataFrame, output_dir: str='./output_issues'):
    # print (issue_dataset.shape)
    issues = issue_dataset['commit_message']
    # print (type(issues))

    # Ensure the output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"Created output directory: {output_dir}")
    # Iterate through the series using the index
    for index, message in issues.items():
        # Define a unique filename using the index or row number
        filename = f"issue_{index}.txt"
        file_path = os.path.join(output_dir, filename)
        
        # Open and write the message to the file
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(str(message)) # Ensure it's treated as a string
            # print(f"Saved issue {index} to {file_path}")
        except IOError as e:
            print(f"Error saving file {file_path}: {e}")



def main ():
    filename = "secVulEval_dataset/train-00000-of-00001.parquet"
    secVulEvalfull = pd.read_parquet(filename)
    secVulEval = secVulEvalfull[secVulEvalfull['is_vulnerable'] != False].reset_index(drop=True)
    secVulEval = secVulEval[secVulEval['project'] == 'linux'].reset_index(drop=True)

    # This below is a sample to test the script using a dataFrame.
    # data = {
    #     'commit_message': [
    #         "Fix: Resolve authentication bug in login page.\nAdded validation logic.",
    #         "Feature: Implement dark mode toggle.\nUses CSS variables.",
    #         "Refactor: Clean up unused imports in utility files."
    #     ],
    #     'other_data': [1, 2, 3]
    # }
    # df = pd.DataFrame(data)

    # load issues in separate files
    load_issues(secVulEval, './security_issues')


if __name__ == "__main__":
    # This block checks if the script is being run as the main program.
    main()