#!/usr/bin/env python3
# Apache 2.0.

"""This script converts an train json
        into Chime6 dev json format
Usage: convert_json_to_jsondev.py Chime6/transcription/train/
       Chime6/transcription/train_new/"""

import json
from glob import glob
import os
import argparse

def get_args():
    parser = argparse.ArgumentParser(
        description="""This script converts an train json
        into Chime6 dev json format""")
    parser.add_argument("output_json_dir", type=str,
                        help="""output json file.
                        The format of the new train json file is
                        <end_time> <start_time> <words> <speaker> """
                        """<ref> <location> <session_id>""")
    args = parser.parse_args()

    return args


def main():
    args = get_args()
    output_json_file = args.output_json_dir + '/' + 'ntu_json' 
    output = []
    print(output_json_file)
    with open(output_json_file, 'w') as jfile:
        utt_dict = {"end_time": 'ashish',
                       "start_time": 'ashish',
                       "words": 'ashish',
                       "speaker": 'ashish',
                       "ref": 'ashish',
                       "location": 'ashish',
                       "session_id": 'ashish',
                       "session_1": '[ch1.wav, ch2.wav, ...]',
                       "LKC2": '[LKC2_SS21_U1850720G_Tr2.wav, LKC2_SS22_U1850810F_Tr1.wav, LKC2_SS23_U1850370J_L.wav, LKC2_SS24_U1850200D_R.wav, LKC2_SS25_U1850031F_Tr3.wav, LKC2_SS26_U1850911E_Tr4.wav]'
                       }
        output.append(utt_dict)
        json.dump(output, jfile, sort_keys = True, indent=4)

if __name__ == '__main__':
    main()
