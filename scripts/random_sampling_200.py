import os
import random
import pandas as pd

def sample_issues_with_exclusions(base_dir='./security_issues_FINAL_v3', total_sample_size=200, output_csv='sampled_issues.csv'):
    """
    Selects 200 samples ensuring:
    1. 'NVD-CWE-noinfo' and 'NVD-CWE-Other' are excluded.
    2. Every other CWE folder provides at least one issue.
    3. The rest are chosen randomly from the remaining pool.
    """
    
    if not os.path.exists(base_dir):
        print(f"Error: Directory '{base_dir}' not found.")
        return

    # 1. Define the CWE types to exclude
    exclude_list = ['NVD-CWE-noinfo', 'NVD-CWE-Other']
    
    # 2. Map out the files, skipping the excluded folders
    cwe_map = {}
    for folder in os.listdir(base_dir):
        # Skip if folder is in exclusion list or not a directory
        if folder in exclude_list:
            continue
            
        folder_path = os.path.join(base_dir, folder)
        if os.path.isdir(folder_path):
            files = [f for f in os.listdir(folder_path) if f.endswith('.txt')]
            if files:
                cwe_map[folder] = files

    all_valid_cwes = list(cwe_map.keys())
    num_cwes = len(all_valid_cwes)

    print(f"Total valid CWE categories (excluding {exclude_list}): {num_cwes}")

    if num_cwes > total_sample_size:
        print(f"Error: You have {num_cwes} CWEs, but only want {total_sample_size} samples.")
        return

    selected_samples = []
    remaining_pool = []

    # 3. Step A: Guarantee 1 sample from EVERY valid CWE type
    print(f"Selecting 1 guaranteed sample from each valid CWE...")
    for cwe in all_valid_cwes:
        files = cwe_map[cwe]
        chosen = random.choice(files)
        selected_samples.append({'CWE_Type': cwe, 'Filename': chosen})
        
        # Add the remaining files of this CWE to the general pool
        for f in files:
            if f != chosen:
                remaining_pool.append({'CWE_Type': cwe, 'Filename': f})

    # 4. Step B: Randomly select the remaining issues to reach 200
    needed = total_sample_size - len(selected_samples)
    print(f"Selecting {needed} more samples randomly from the valid population...")
    
    if needed > len(remaining_pool):
        print(f"Note: Not enough files to reach {total_sample_size}. Taking all available files.")
        additional_samples = remaining_pool
    else:
        additional_samples = random.sample(remaining_pool, needed)

    selected_samples.extend(additional_samples)

    # 5. Save results to CSV
    df = pd.DataFrame(selected_samples)
    
    # Sort by CWE Type and Filename for a clean report
    df = df.sort_values(by=['CWE_Type', 'Filename'])
    
    df.to_csv(output_csv, index=False)

    print(f"\nSuccess!")
    print(f"Total samples collected: {len(df)}")
    print(f"Excluded: {exclude_list}")
    print(f"Results saved to: {output_csv}")

if __name__ == "__main__":
    # Optional: random.seed(42) for reproducible results
    sample_issues_with_exclusions(
        base_dir='./security_issues_FINAL_v4', 
        total_sample_size=200, 
        output_csv='RQ_folder_MAIN/new_sampled_security_issues_v2.csv'
    )