#!/usr/bin/env python3
import sys
import os
import shutil
import re

# 1. SETUP: Import your existing eqChecker without changing it
# We append the current directory to sys.path to ensure we can import it
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    # This imports the module and initializes the global API clients (client, client_gpt) ONCE.
    import eqChecker
except ImportError:
    print("Error: Could not import 'eqChecker.py'. Make sure it is in the same folder.")
    sys.exit(1)

import re

def remove_c_comments(text):
    """
    Removes C-style /* ... */ and // ... comments using regex.
    Note: This is a heuristic. It handles most cases but might break on 
    weird string literals containing comment markers (e.g. printf("//")).
    For bucketing, this acceptable because it is deterministic.
    """
    pattern = r'''
        # Match /* ... */ style comments
        /\*.*?\*/
        |
        # Match // ... style comments
        //.*?$
    '''
    # flags=re.VERBOSE | re.MULTILINE | re.DOTALL allows matching newlines in /* */
    regex = re.compile(pattern, re.VERBOSE | re.MULTILINE | re.DOTALL)
    return regex.sub("", text)

def get_file_signature(filepath):
    """
    Generates a 'Logical Fingerprint'. 
    Files with different fingerprints are structurally different 
    and thus 99.9% likely to be non-equivalent.
    """
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        raw_content = f.read()

    # 1. Strip comments
    code_only = remove_c_comments(raw_content)

    # 2. Normalize whitespace (remove newlines, tabs, extra spaces)
    #    This ensures that:
    #       if(x){y;} 
    #    is treated exactly the same as:
    #       if ( x ) {
    #           y;
    #       }
    normalized_code = " ".join(code_only.split())

    # 3. HEURISTIC A: Token Length (Better than line count)
    # We use the length of the code string without whitespace/comments.
    # We round it to create a "fuzzy" bucket to handle minor variable name changes.
    # e.g., Round to nearest 10 characters.
    length_metric = len(normalized_code) // 10 

    # 4. HEURISTIC B: Structural Keywords (The strong filter)
    # We count how many times these specific keywords appear.
    # If file A has 2 'for' loops and file B has 0, they are not equivalent.
    # We look for whole words only.
    keywords = ['if', 'else', 'for', 'while', 'switch', 'return', 'void', 'int']
    
    counts = []
    for kw in keywords:
        # Regex to match whole word only (so 'while' doesn't match 'while_loop_var')
        count = len(re.findall(r'\b' + re.escape(kw) + r'\b', code_only))
        counts.append(count)
    
    # 5. Create the Bucket Key
    # The key is a tuple: (keyword_counts_tuple, approximate_length)
    # files in the same bucket must have EXACTLY same number of control structures
    # and ROUGHLY same code mass.
    signature = (tuple(counts), length_metric)
    
    return signature, raw_content

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 smart_driver.py <input_folder>")
        sys.exit(1)

    input_folder = os.path.abspath(sys.argv[1])
    
    # Create output directories as per your logic
    base_name = os.path.basename(input_folder)
    # Handle case where input_folder ends in slash
    if not base_name: base_name = os.path.basename(input_folder[:-1])
    
    output_dir_copy = os.path.join(input_folder, f"non-eq-{base_name}")
    eq_checker_log_dir = os.path.join(input_folder, "eq_checker_output")
    
    os.makedirs(output_dir_copy, exist_ok=True)
    os.makedirs(eq_checker_log_dir, exist_ok=True)

    # 1. Find all C files
    c_files = []
    for f in os.listdir(input_folder):
        full_path = os.path.join(input_folder, f)
        if os.path.isfile(full_path) and f.endswith(".c"):
            c_files.append(full_path)
            
    c_files.sort()
    total_files = len(c_files)
    print(f"Found {total_files} .c files. Organizing buckets...")

    # 2. Bucket files to avoid N^2 comparisons
    # Bucket structure: { line_count: [(filepath, content), ...] }
    buckets = {}
    
    for fpath in c_files:
        sig, content = get_file_signature(fpath)
        if sig not in buckets:
            buckets[sig] = []
        buckets[sig].append((fpath, content))

    unique_files = [] # List of file paths we decided to keep

    # 3. Process buckets
    print(f"Created {len(buckets)} buckets based on code length.")
    
    comparisons_made = 0
    saved_comparisons = 0

    for sig in sorted(buckets.keys()):
        candidates = buckets[sig]
        
        # 'keepers' are the unique files within THIS bucket
        keepers_in_bucket = [] 

        for (curr_path, curr_content) in candidates:
            is_unique = True
            
            # Compare current file ONLY against already accepted keepers in this bucket
            for (keeper_path, keeper_content) in keepers_in_bucket:
                
                # OPTIMIZATION A: Exact Text Match (Free)
                if curr_content == keeper_content:
                    print(f"[Fast Match] {os.path.basename(curr_path)} == {os.path.basename(keeper_path)}")
                    is_unique = False
                    break
                
                # OPTIMIZATION B: LLM Check (Expensive)
                print(f"[LLM Check] Comparing {os.path.basename(curr_path)} vs {os.path.basename(keeper_path)}...")
                
                # Call the imported function directly
                # Note: Your eqChecker returns the raw string response from LLM
                try:
                    response = eqChecker.eqChecker(
                        mutant_filename_path=curr_path, 
                        current_filename_path=keeper_path, 
                        output_directory=eq_checker_log_dir
                    )
                    comparisons_made += 1
                    
                    if "{yes}" in response.lower():
                        print(f"   -> EQUIVALENT. Discarding {os.path.basename(curr_path)}")
                        is_unique = False
                        break
                    else:
                        print("   -> Unique so far.")
                        
                except Exception as e:
                    print(f"Error calling eqChecker: {e}")
                    # If error, assume unique to be safe? Or fail? 
                    # Let's assume unique to preserve data.
                    pass

            if is_unique:
                keepers_in_bucket.append((curr_path, curr_content))
                unique_files.append(curr_path)

        # Update stats
        n = len(candidates)
        # theoretical N^2/2 vs actual comparisons
        saved_comparisons += ((n * (n-1)) // 2) - comparisons_made

    # 4. Copy results
    print(f"\nProcessing complete.")
    print(f"Original files: {total_files}")
    print(f"Unique files:   {len(unique_files)}")
    print(f"LLM Calls made: {comparisons_made}")
    
    for f in unique_files:
        shutil.copy(f, output_dir_copy)
        
    print(f"Unique files copied to: {output_dir_copy}")

if __name__ == "__main__":
    main()