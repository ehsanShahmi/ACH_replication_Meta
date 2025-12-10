from datasets import load_dataset
import subprocess
from pathlib import Path
import sys
import unittest
import io
import pandas as pd
import os

def cluster_issues(issue_dataset: pd.DataFrame) -> pd.DataFrame:
    # 1. Explode the list so each item gets its own row
    exploded_df = issue_dataset.explode('cwe_list')
    # 2. Group by the individual items
    result = exploded_df.groupby('cwe_list')['commit_message'].apply(list).reset_index()
    result['count'] = result['commit_message'].str.len()
    # counts = issue_dataset.groupby(issue_dataset['cwe_list'].apply(tuple))['commit_message'].size().reset_index(name='count')
    # print (result)


    # # 1. Filter the DataFrame to get the row for 'CWE-863'
    # target_row = result[result['cwe_list'] == 'CWE-863']
    # # 2. Check if it exists to avoid errors
    # if not target_row.empty:
    #     # Extract the actual list of messages (using .iloc[0] to get the first match)
        # messages = target_row['commit_message'].iloc[0]
    # # 3. Print each message clearly
    #     print(f"Found {len(messages)} messages for CWE-683:\n")
    #     for i, msg in enumerate(messages, 1):
    #         print(f"{i}. {msg}\n{'-'*40}")
    # else:
    #     print("Category 'CWE-683' not found in the results.")   

    return result



def load_issues(issue_dataset: pd.DataFrame, output_dir: str='./output_issues'):

    # Ensure the output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"Created output directory: {output_dir}")

    # # Iterate through the series using the index
    # for index, message in issues.items():
    #     # Define a unique filename using the index or row number
    #     filename = f"issue_{index}.txt"
    #     file_path = os.path.join(output_dir, filename)
        
    #     # Open and write the message to the file
    #     try:
    #         with open(file_path, 'w', encoding='utf-8') as f:
    #             f.write(str(message)) # Ensure it's treated as a string
    #         # print(f"Saved issue {index} to {file_path}")
    #     except IOError as e:
    #         print(f"Error saving file {file_path}: {e}")

    for index, row in issue_dataset.iterrows():
        # Generate the filename from the CWE ID (e.g., "CWE-119.txt")
        cwe_id = str(row['cwe_list']).strip()
        filename = f"{cwe_id}.txt"
        file_path = os.path.join(output_dir, filename)
        # Get the list of messages for this CWE
        messages = row['commit_message']
        with open(file_path, "w", encoding="utf-8") as f:
            for msg in messages:
                f.write("A new commit message starts here: ")
                # 3. Clean the message: Remove \n and \t from the content
                # We replace them with a space to prevent words from sticking together
                clean_msg = msg.replace("\n", " ").replace("\t", " ")
                # 4. Write to file
                # We add a single newline char at the end to keep messages on separate lines
                f.write(clean_msg + "\n")

    print(f"Successfully created {len(issue_dataset)} cluster files in '{output_dir}/'")



def main ():
    filename = "secVulEval_dataset/train-00000-of-00001.parquet"
    secVulEvalfull = pd.read_parquet(filename)
    secVulEval = secVulEvalfull[secVulEvalfull['is_vulnerable'] != False].reset_index(drop=True)
    secVulEval = secVulEval[secVulEval['project'] == 'linux'].reset_index(drop=True)

    # We clustered the issues according to the CWE types
    secVulEval = cluster_issues(secVulEval)

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
    load_issues(secVulEval, './security_issue_cluster')


if __name__ == "__main__":
    # This block checks if the script is being run as the main program.
    main()