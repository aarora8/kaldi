#!/usr/bin/env python3

import argparse
import os
import numpy as np
import sys
import re
import io

parser = argparse.ArgumentParser(description="""Removes dev/test set lines
                                                corpus from stdin, and writes it to stdout.""")
parser.add_argument('text_file_path', type=str,
                    help='transcription location.')
args = parser.parse_args()

def read_utterances(text_file_path):
    utterance_dict = dict()
    with open(text_file_path, 'r', encoding="utf8") as in_file:
        for line in in_file:
            words = line.strip().split()
            transcript = ' '.join(words[1:])
            utterance_dict[words[0]] = transcript
    return utterance_dict

def get_unique_utterances(utterance_dict):
    unique_utt_transcription_dict = dict()
    for utt_id, transcript in utterance_dict.items():
        if transcript not in list(unique_utt_transcription_dict.values()):
            unique_utt_transcription_dict[utt_id] = transcript
    return unique_utt_transcription_dict

### main ###
utterance_dict = read_utterances(args.text_file_path)
unique_utt_transcription_dict = get_unique_utterances(utterance_dict)

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf8")
for k, v in unique_utt_transcription_dict.items():
    sys.stdout.write(k + "\n")
    #print('{}'.format(k))
    #print('{} {}'.format(k, v))
