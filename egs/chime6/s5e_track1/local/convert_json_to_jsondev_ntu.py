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
    output_json_file = args.output_json_dir + '/' + 'ntu.json' 
    output = []
    print(output_json_file)
    with open(output_json_file, 'w') as jfile:
        utt_dict = {
                    'LKC2': '/export/c06/aarora8/kaldi/egs/chime6/s5e_track1/LKC_S2/LKC2.wav'
                   }
        output.append(utt_dict)
        json.dump(output, jfile, sort_keys = True, indent=4)

if __name__ == '__main__':
    main()
