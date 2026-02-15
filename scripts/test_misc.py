# import os

# def count_files(directory):
#     total_files = 0
#     for root, dirs, files in os.walk(directory):
#         total_files += len(files)
#     return total_files

# # Point this to your CWEval benchmark folder
# cweval_dir = "./CWEval/benchmark/core/go"
# print(f"Total files: {count_files(cweval_dir)}")
# # ```[[1](https://www.google.com/url?sa=E&q=https%3A%2F%2Fvertexaisearch.cloud.google.com%2Fgrounding-api-redirect%2FAUZIYQFxUvUhtNHKWjpOUIYkXSaz8V-8hnc_LOdhZkbL48shjrblCRwu4PiUoWXEPrM6YATzXraebE3QlzeSjrAzP3UkSHzTrCNmQ0YplG39aWB6dkWlYMipU4PdQOHS)]


# import os
# from pathlib import Path
# import csv

# def count_files_simple(root_folder, output_csv="file_counts.csv"):
#     """Count files and save to CSV without pandas."""
#     root_path = Path(root_folder)
    
#     if not root_path.exists() or not root_path.is_dir():
#         print(f"Error: Invalid directory '{root_folder}'")
#         return
    
#     results = []
#     total_files = 0
    
#     print(f"Scanning: {root_folder}")
#     print("-" * 50)
    
#     # Get all subdirectories
#     subdirs = sorted([d for d in root_path.iterdir() if d.is_dir()])
    
#     for subdir in subdirs:
#         file_count = 0
#         file_list = []
        
#         for item in subdir.iterdir():
#             if item.is_file():
#                 file_count += 1
#                 file_list.append(item.name)
        
#         results.append({
#             'Subdirectory': subdir.name,
#             'File Count': file_count,
#             'File Names': ', '.join(file_list[:10]) + ('...' if len(file_list) > 10 else ''),
#             'Full Path': str(subdir)
#         })
        
#         total_files += file_count
#         print(f"{subdir.name}: {file_count} files")
    
#     # Save to CSV
#     with open(output_csv, 'w', newline='', encoding='utf-8') as csvfile:
#         if results:
#             fieldnames = results[0].keys()
#             writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            
#             writer.writeheader()
#             for row in results:
#                 writer.writerow(row)
            
#             # Write total
#             writer.writerow({
#                 'Subdirectory': 'TOTAL',
#                 'File Count': total_files,
#                 'File Names': '',
#                 'Full Path': 'All Subdirectories'
#             })
    
#     print("-" * 50)
#     print(f"Total subdirectories: {len(subdirs)}")
#     print(f"Total files: {total_files}")
#     print(f"Results saved to: {output_csv}")
    
#     return results

# # Usage
# if __name__ == "__main__":
#     # Install pandas if needed: pip install pandas openpyxl
#     count_files_simple("./security_issues_FINAL", "security_issues_counts.csv")

import ollama

def test_gemma_12b():
    print("--- Testing Gemma 3 12B-it ---")
    
    # Use 'gemma3:12b' as the model name
    stream = ollama.chat(
        model='gemma3:12b',
        messages=[
            {'role': 'system', 'content': 'You are a helpful coding assistant.'},
            {'role': 'user', 'content': 'Explain the difference between a list and a tuple in Python.'}
        ],
        stream=True,
    )

    print("Response: ", end="", flush=True)
    for chunk in stream:
        # Print each part of the message as it arrives
        print(chunk['message']['content'], end='', flush=True)
    print("\n------------------------------")

if __name__ == "__main__":
    try:
        test_gemma_12b()
    except Exception as e:
        print(f"Error: {e}")
        print("Ensure Ollama is running (ollama serve) and the model is pulled.")
