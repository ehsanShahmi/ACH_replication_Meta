'''
Why this works better-->>

Scalability (The 20% Ratio): Research into automatic summarization often targets a compression rate (tau) of 15% to 30% as the optimal balance between brevity and information retention. If you have 200 commit messages, this script will return the top 40, giving you a comprehensive overview rather than a tiny snippet.

Alternative Heuristic (Square Root): If your files are massive (e.g., 1,000+ messages), 20% (200 sentences) might still be too long. In that specific case, you can swap the formula to int(math.sqrt(total_sentences)). This scales much more aggressively (1000 input 31 output).

Why Luhn fits Commit Logs: Since your file contains a list of distinct commit messages rather than a cohesive story, standard "narrative" summarizers (like TextRank) might struggle to find flow. Luhn is frequency-based; it will simply pick the sentences containing the most frequent "significant" words (e.g., "overflow", "fix", "leak"). This effectively acts as a filter for the most representative types of bugs in that cluster.

'''

import os
import sys
from sumy.parsers.plaintext import PlaintextParser
from sumy.nlp.tokenizers import Tokenizer
from sumy.summarizers.luhn import LuhnSummarizer
from sumy.nlp.stemmers import Stemmer
from sumy.utils import get_stop_words
import nltk
# nltk.download('punkt_tab')


def luhn_summarize(text, ratio=0.2):
    """
    Summarizes text to a specific ratio (default 20% of original length).
    """
    # 1. Parse the text first to count available sentences
    parser = PlaintextParser.from_string(text, Tokenizer("english"))
    total_sentences = len(parser.document.sentences)
    if total_sentences == 0:
        return []
    # 2. Dynamic Calculation: Use 20% of total, but ensure at least 1 sentence
    # For massive logs (>100 lines), you might prefer square root: int(math.sqrt(total_sentences))
    sentence_count = max(1, int(total_sentences * ratio))
    # 3. Initialize Summarizer
    summarizer = LuhnSummarizer(Stemmer("english"))
    summarizer.stop_words = get_stop_words("english")
    # 4. Generate Summary
    summary = summarizer(parser.document, sentence_count)
    return summary


def summarizer(input_string: str) -> str:
    # Pass the ratio here (e.g., 0.2 for 20%)
    summary = luhn_summarize(input_string, 0.4)
    # Join with spaces (or newlines for better readability)
    summary_as_string = " ".join(str(element) for element in summary)
    return summary_as_string


if __name__ == "__main__":
    # This block checks if the script is being run as the main program.
    # file_path = os.path.join('.', 'security_issues', 'issue_0.txt')
    file_path = sys.argv[1]
    with open(file_path, 'r') as file:
        # The .read() method reads the entire content of the file into a single string
        input = file.read()
    summarized_input = summarizer(input)
    
    print (summarized_input)