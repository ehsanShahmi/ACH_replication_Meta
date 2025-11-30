# from datasets import load_dataset
from dotenv import load_dotenv
load_dotenv()
from google import genai
# from google.genai import types
# from sumy.parsers.plaintext import PlaintextParser
# from sumy.nlp.tokenizers import Tokenizer
# from sumy.summarizers.luhn import LuhnSummarizer
# from sumy.nlp.stemmers import Stemmer
# from sumy.utils import get_stop_words
# import nltk
# # nltk.download('punkt_tab')
# import pandas as pd
# import numpy as np
# import coverage as cv
# import os
# import subprocess
# from pathlib import Path
# import sys
# import unittest
# import io
import openai
client = genai.Client()

response = client.models.generate_content(
  model="gemini-2.5-pro", 
  contents="Write a realistic five-sentence bedtime story about a unicorn."
  )

print(response.text)
print (type(response.text))