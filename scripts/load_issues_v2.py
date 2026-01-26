'''
This script loads the issues from the SecVulEval. Only the issues are stored in separate folders according to the CWE types.
'''


from datasets import load_dataset
import subprocess
from pathlib import Path
import sys
import unittest
import io
import pandas as pd
import os
from openpyxl.workbook import Workbook
from typing import Dict, List

def save_issues_by_cwe(issue_dataset: pd.DataFrame, base_output_dir: str = './security_issues_FINAL') -> None:
    """
    Reads an issue dataset, categorizes commit messages by their individual CWE IDs, 
    and saves each unique message as a numbered text file within a dedicated 
    folder for that CWE ID.

    Args:
        issue_dataset: A pandas DataFrame with 'cwe_list' (list of strings) 
                       and 'commit_message' (string) columns.
        base_output_dir: The base directory where all CWE folders will be created.
    """
    print(f"Starting to process issues and save to base directory: '{base_output_dir}'")
    
    # 1. Cluster the data by exploding the list and grouping messages (from cluster_issues function)
    # This transforms the original data into a format where each row is a unique CWE ID 
    # and a list of *all* associated commit messages (duplicates included initially).
    exploded_df = issue_dataset.explode('cwe_list')
    cwe_clusters = exploded_df.groupby('cwe_list')['commit_message'].apply(list).reset_index(name='all_messages')
    
    # 2. Iterate through each CWE category and save the files (modified from load_issues function)
    for index, row in cwe_clusters.iterrows():
        cwe_id = str(row['cwe_list']).strip()
        
        # Define the specific folder path for this CWE (e.g., './issues/cwe19/')
        cwe_folder_path = os.path.join(base_output_dir, cwe_id)
        
        # Ensure the output directory exists
        if not os.path.exists(cwe_folder_path):
            os.makedirs(cwe_folder_path)
            print(f"Created directory: {cwe_folder_path}")

        # Get the list of messages and deduplicate them while preserving order
        raw_messages = row['all_messages']
        unique_messages = list(dict.fromkeys(raw_messages))

        print(f"Processing {len(unique_messages)} unique messages for category '{cwe_id}'...")
        
        # 3. Save each unique message as an individual file
        for i, msg in enumerate(unique_messages, 1):
            # Filename format: "cwe19_issue_1.txt"
            filename = f"{cwe_id}_issue_{i}.txt"
            file_path = os.path.join(cwe_folder_path, filename)
            
            # Clean the message: Remove newlines and tabs for single-line storage
            # clean_msg = msg.replace("\n", " ").replace("\t", " ")

            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(msg + "\n")
            except IOError as e:
                print(f"Error writing file {file_path}: {e}")

    print(f"\nSuccessfully created files for {len(cwe_clusters)} categories in '{base_output_dir}/'")





def main ():
    filename = "secVulEval_dataset/train-00000-of-00001.parquet"
    secVulEvalfull = pd.read_parquet(filename)
    secVulEval = secVulEvalfull[secVulEvalfull['is_vulnerable'] != False].reset_index(drop=True)
    secVulEval = secVulEval[secVulEval['project'] == 'linux'].reset_index(drop=True)

    save_issues_by_cwe(secVulEval)


if __name__ == "__main__":
    # This block checks if the script is being run as the main program.
    main()