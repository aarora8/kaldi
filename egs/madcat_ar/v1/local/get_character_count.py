#!/usr/bin/env python3

# Copyright  2018  Ashish Arora

import argparse
import os

parser = argparse.ArgumentParser(description="""Creates the list of characters and words in lexicon""")
parser.add_argument('dir', type=str, help='output path')
args = parser.parse_args()

### main ###
text_path = os.path.join('data', 'train_unsup', 'text.old')
text_fh = open(text_path, 'r', encoding='utf-8')

character_path = os.path.join('data', 'local', 'dict', 'nonsilence_phones.txt')
character_fh = open(character_path, 'r', encoding='utf-8')
char_data = character_fh.read().strip().split("\n")
char_dict = dict()
for key_val in char_data:
  key_val = key_val.split(" ")
  char_dict[key_val[0]] = 0

with open(text_path, 'r', encoding='utf-8') as f:
    for line in f:
        line_vect = line.strip().split(' ')
        for i in range(1, len(line_vect)):
            characters = list(line_vect[i])
            for char in characters:
                if char not in char_dict.keys():
                    char_dict[char] = 0
                char_dict[char] += 1 

with open(os.path.join(args.dir, 'char_count.txt'), 'w', encoding='utf-8') as fp:
    for key in sorted(char_dict):
        fp.write(key + " " + str(char_dict[key]) + "\n")
