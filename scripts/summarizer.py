import os
import sys
from sumy.parsers.plaintext import PlaintextParser
from sumy.nlp.tokenizers import Tokenizer
from sumy.summarizers.luhn import LuhnSummarizer
from sumy.nlp.stemmers import Stemmer
from sumy.utils import get_stop_words
import nltk
# nltk.download('punkt_tab')


def luhn_summarize(text, sentence_count=2):
    # Parse the input text
    parser = PlaintextParser.from_string(text, Tokenizer("english"))
    # Initialize summarizer with stemmer
    summarizer = LuhnSummarizer(Stemmer("english"))
    summarizer.stop_words = get_stop_words("english")
    # Generate summary
    summary = summarizer(parser.document, sentence_count)
    return summary


def summarizer(input_string: str) -> str:
    summary = luhn_summarize(input_string, 3)
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