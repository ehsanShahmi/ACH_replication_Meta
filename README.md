# Security Hardening Paper [project name to be declared later on]

In this repository, we store all the files and folders related to our paper "Security Hardening." The repo is arranged in such a was so that replication can be carried out by the research community of software engineering. For replication purposes, we need to follow theses below steps one-by-one:


## 🧩 Setup Instructions

### 1. Create and activate a virtual environment
```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 3. Setup the dataset **SecVulEval** for security issues:
First run the script to load the dataset having the security issues. For this run the following command:
```bash
python3 ./scripts/load_issues.py
```
This will create a folder in the root directory named "**security_issues**". This folder will have all the security issues stored in separate text files, e.g. "**issue_0.txt**".


## 🔧 Project Steps

### 1. Make scripts permissible
Run the following command from the project root directory to make any scripts permissible.
```bash
chmod +x ./scripts/any_script
```
Please do not 'cd' into the scripts folder. Run the permission command from the root folder.