'''
This script loads issues in separate files according to CWE types. 
BUT with issues, the fixed functions are also stored below each issue.
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


def save_issues_by_cwe(issue_dataset: pd.DataFrame, base_output_dir: str = './security_issues_FINAL_v3') -> None:
    """
    Processes the dataset to pair vulnerable rows with their immediate next-row fix,
    then categorizes and saves them by CWE ID.
    """
    print(f"Starting to process issues and save to base directory: '{base_output_dir}'")
    
    # List to hold the formatted data before grouping
    processed_records = []

    # 1. Iterate through the dataframe to find vulnerable rows and their next-row fix
    # We stop at len - 1 to ensure there is a "next row" to grab
    for i in range(len(issue_dataset) - 1):
        row_vuln = issue_dataset.iloc[i]
        
        # Check if the current row is the vulnerable one
        if row_vuln['is_vulnerable'] == True:
            row_fix = issue_dataset.iloc[i + 1]
            
            # Construct the specific string format requested
            formatted_content = (
                "The vulnerable issue:\n" + str(row_vuln['commit_message']).strip() + 
                "\n\n\n\nThe vulnerable function:\n" + str(row_vuln['func_body']).strip() + 
                "\n\n\n\nThe corrected function:\n" + str(row_fix['func_body']).strip()
            )
            
            # Store the CWE list and the formatted content
            processed_records.append({
                'cwe_list': row_vuln['cwe_list'],
                'content': formatted_content
            })

    # 2. Convert processed records to a DataFrame for easier grouping
    processed_df = pd.DataFrame(processed_records)
    
    # 3. Explode the CWE list and group
    exploded_df = processed_df.explode('cwe_list')
    cwe_clusters = exploded_df.groupby('cwe_list')['content'].apply(list).reset_index()

    # 4. Save to files
    for index, row in cwe_clusters.iterrows():
        cwe_id = str(row['cwe_list']).strip()
        cwe_folder_path = os.path.join(base_output_dir, cwe_id)
        
        if not os.path.exists(cwe_folder_path):
            os.makedirs(cwe_folder_path)

        unique_contents = list(dict.fromkeys(row['content']))
        print(f"Saving {len(unique_contents)} unique pairs for category '{cwe_id}'...")
        
        for i, content in enumerate(unique_contents, 1):
            filename = f"{cwe_id}_issue_{i}.txt"
            file_path = os.path.join(cwe_folder_path, filename)
            
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(content)
            except IOError as e:
                print(f"Error writing file {file_path}: {e}")

    print(f"\nSuccessfully created files in '{base_output_dir}/'")

def main():
    filename = "secVulEval_dataset/train-00000-of-00001.parquet"
    
    if not os.path.exists(filename):
        print(f"File not found: {filename}")
        return

    # Load and filter project
    secVulEvalfull = pd.read_parquet(filename)
    
    # Filter for linux and reset index is CRITICAL here so that [i+1] 
    # refers to the next linux record, not the original global index
    secVulEval = secVulEvalfull[secVulEvalfull['project'] == 'linux'].reset_index(drop=True)
    # print (secVulEval.shape)

    # save_issues_by_cwe(secVulEval)

if __name__ == "__main__":
    main()