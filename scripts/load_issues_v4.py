'''
This script loads issues in separate files according to CWE types. 
It pairs vulnerable functions with their specific fixed versions using 'fixed_func_idx'.
It also generates a CSV summary of unique issue counts per CWE.
Filenames now include the original dataset index.
'''

from datasets import load_dataset
import pandas as pd
import os
from typing import Dict, List

def save_issues_by_cwe(filtered_df: pd.DataFrame, full_df: pd.DataFrame, base_output_dir: str = './security_issues_FINAL_v6') -> None:
    """
    Processes the dataset to pair vulnerable rows with their specific fix using fixed_func_idx,
    categorizes them by CWE, saves text files with a specific header and index in filename.
    """
    print(f"Starting to process issues and save to base directory: '{base_output_dir}'")
    
    processed_records = []
    summary_data = []

    # 1. Iterate through the filtered (linux) dataframe
    for idx, row_vuln in filtered_df.iterrows():
        if row_vuln['is_vulnerable'] == True:
            fix_idx = row_vuln['fixed_func_idx']
            
            if pd.notnull(fix_idx):
                try:
                    # Look up the corrected function in the full dataset
                    row_fix = full_df.loc[int(fix_idx)]
                    
                    # Construct the unique triplet string
                    formatted_content = (
                        "The vulnerable issue:\n" + str(row_vuln['commit_message']).strip() + 
                        "\n\n\n\nThe vulnerable function:\n" + str(row_vuln['func_body']).strip() + 
                        "\n\n\n\nThe corrected function:\n" + str(row_fix['func_body']).strip()
                    )
                    
                    # Store the CWE list, the content, AND the original index
                    processed_records.append({
                        'cwe_list': row_vuln['cwe_list'],
                        'content': formatted_content,
                        'orig_idx': idx
                    })
                except (KeyError, ValueError):
                    continue

    if not processed_records:
        print("No vulnerable records found to process.")
        return

    # 2. Convert to DataFrame and explode by CWE
    processed_df = pd.DataFrame(processed_records)
    exploded_df = processed_df.explode('cwe_list')
    
    # Group by CWE and collect pairs of (content, index)
    cwe_clusters = exploded_df.groupby('cwe_list').apply(
        lambda x: list(zip(x['content'], x['orig_idx']))
    ).reset_index(name='content_pairs')

    # 3. Save files and collect summary counts
    for index, row in cwe_clusters.iterrows():
        cwe_id = str(row['cwe_list']).strip()
        cwe_folder_path = os.path.join(base_output_dir, cwe_id)
        
        if not os.path.exists(cwe_folder_path):
            os.makedirs(cwe_folder_path)

        # Ensure unique triplets, but keep the index associated with the first occurrence
        seen_content = {}
        unique_pairs = []
        for content, o_idx in row['content_pairs']:
            if content not in seen_content:
                seen_content[content] = True
                unique_pairs.append((content, o_idx))

        unique_count = len(unique_pairs)
        print(f"Saving {unique_count} unique pairs for category '{cwe_id}'...")
        
        summary_data.append({'CWE_ID': cwe_id, 'Unique_Issue_Count': unique_count})
        
        for i, (content, o_idx) in enumerate(unique_pairs, 1):
            # Filename now includes the original index: e.g., CWE-119_issue_1_idx0.txt
            filename = f"{cwe_id}_issue_{i}_idx{o_idx}.txt"
            file_path = os.path.join(cwe_folder_path, filename)
            
            header_sentence = f"This issue file has {cwe_id}. Your task is to create this {cwe_id} type in your file under test similar to the following entire context.\n\n"
            
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(header_sentence + content)
            except IOError as e:
                print(f"Error writing file {file_path}: {e}")

    # 4. Save the summary CSV
    summary_df = pd.DataFrame(summary_data)
    csv_path = os.path.join(base_output_dir, "cwe_issue_summary.csv")
    summary_df.to_csv(csv_path, index=False)

    print(f"\nSummary report saved to: {csv_path}")
    print(f"Successfully created files in '{base_output_dir}/'")

def main():
    filename = "secVulEval_dataset/train-00000-of-00001.parquet"
    
    if not os.path.exists(filename):
        print(f"File not found: {filename}")
        return

    # Load full dataset
    secVulEvalfull = pd.read_parquet(filename)
    
    # Filter for linux (preserving original index for fixed_func_idx lookup and filename)
    secVulEvallinux = secVulEvalfull[secVulEvalfull['project'] == 'linux']

    save_issues_by_cwe(secVulEvallinux, secVulEvalfull)

if __name__ == "__main__":
    main()