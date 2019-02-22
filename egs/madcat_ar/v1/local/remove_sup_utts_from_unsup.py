#!/usr/bin/env python3

import argparse
import os
import numpy as np
import sys
import re
import io

parser = argparse.ArgumentParser(description="""Removes dev/test set lines
                                                from the LOB corpus. Reads the
                                                corpus from stdin, and writes it to stdout.""")
parser.add_argument('sup_text_path', type=str,
                    help='dev transcription location.')
parser.add_argument('unsup_text_path', type=str,
                    help='test transcription location.')
args = parser.parse_args()

def read_utterances(text_file_path):
    utterance_dict = dict()
    with open(text_file_path, 'r', encoding="utf8") as in_file:
        for line in in_file:
            words = line.strip().split()
            transcript = ' '.join(words[1:])
            utterance_dict[words[0]] = transcript
    return utterance_dict

def get_unique_utterances():
    unique_utt_transcription_dict = dict()
    for utt_id, transcript in unsup_utterance_dict.items():
        if transcript not in list(sup_utterance_dict.values()):
            unique_utt_transcription_dict[utt_id] = transcript
    return unique_utt_transcription_dict

### main ###
sup_utterance_dict = read_utterances(args.sup_text_path)
unsup_utterance_dict = read_utterances(args.unsup_text_path)
unique_utt_transcription_dict = get_unique_utterances()

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf8")
for k, v in unique_utt_transcription_dict.items():
    sys.stdout.write(k + "\n")
    #print('{}'.format(k))
    #print('{} {}'.format(k, v))
