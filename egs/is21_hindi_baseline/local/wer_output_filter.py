#!/usr/bin/env python3

# 2021 Dongji Gao
# Apache 2.0.

import argparse
import sys

# creates a dictionary that maps Hindi-English words.
def get_filter_dict(trans_book, delimiter):
    filter_dict = dict()

    with open(trans_book, 'r') as tb:
        for line in tb.readlines():
            word, orig_word = line.rstrip().split(delimiter)
            if word in filter_dict:
                print("Word '{}' appears more than once in file {}, please check".format(word, trans_book),
                    file=sys.stderr)
            else:
                filter_dict[word] = orig_word

    return filter_dict
            
# replace hindi word in the utterance with english word or viseversa
def filter(filter_dict):
    for line in sys.stdin:
        output_list = list()
        for word in line.rstrip().split():
            if word in filter_dict:
                output_list.append(filter_dict[word])
            else:
                output_list.append(word)
        print(" ".join(output_list))
        
def analysis():
    pass

def main():
    # awk -F ',' '{ if (length($2) != 1) { print $0} }' is21_hindi_words-dev_set.csv > is21_hindi_english_devfiltered.csv
    delimiter = ','
    trans_book = 'corpus/is21_hindi_english_devfiltered.csv'
    filter_dict = get_filter_dict(trans_book, delimiter)
    filter(filter_dict)
    analysis()

if __name__ == "__main__":
    main()
