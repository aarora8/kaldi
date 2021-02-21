#!/usr/bin/env python3
import sys
import os
import argparse
from collections import namedtuple

# chain_directory = '/Users/ashisharora/data_prep_siamese/'
# suffix_list='1,2'

def find_minimum(csid_list):
    min_index = -1
    min_val = 10000
    for index,csid in enumerate(csid_list):
        if int(csid.total_errors) < min_val:
            min_val = int(csid.total_errors)
            min_index = index
    return min_index


def make_diar_data(chain_directory, suffix_list, audio_type, output_path):
    if not os.path.exists(output_path):
        os.makedirs(output_path)

    folder_suffix = [str(item) for item in suffix_list.strip().split(',')]
    per_utt_path_list = []
    for suffix in folder_suffix:
        per_utt_path_list.append(chain_directory + '/decode_dev_' + suffix + '/scoring_kaldi/wer_details/per_utt' )

    csid_dict = dict()
    if audio_type == 'single_microphone':
        csid = namedtuple('csid', 'uttid arrray_id channel_id total_words total_errors correct substitute insert delete')
    else:
        csid = namedtuple('csid', 'uttid arrray_id total_words total_errors correct substitute insert delete')

    for path in per_utt_path_list:
        for line in open(path):
            line = line.strip().split(" ")
            # get only csid lines
            if "csid" not in line[1]:
                continue

            utt_id = line[0]
            utt_id_filtered = utt_id
            utt_id_filtered = utt_id_filtered.replace("CH1", "")
            utt_id_filtered = utt_id_filtered.replace("CH2", "")
            utt_id_filtered = utt_id_filtered.replace("CH3", "")
            utt_id_filtered = utt_id_filtered.replace("CH4", "")
            utt_id_filtered = utt_id_filtered.replace("U01", "")
            utt_id_filtered = utt_id_filtered.replace("U02", "")
            utt_id_filtered = utt_id_filtered.replace("U03", "")
            utt_id_filtered = utt_id_filtered.replace("U04", "")
            utt_id_filtered = utt_id_filtered.replace("U05", "")
            utt_id_filtered = utt_id_filtered.replace("U06", "")

            if audio_type == 'single_microphone':
                # P05_S02_U01_DINING.CH1-0291234-0292406
                arrray_id = utt_id.strip().split('_')[2]
                channel_id = utt_id.strip().split('.')[1].split('-')[0]

                total_errors = int(line[3]) + int(line[4]) + int(line[5])
                total_words = int(line[2]) + int(line[3]) + int(line[5])
                csid_element = csid(
                    uttid=utt_id,
                    arrray_id=arrray_id,
                    channel_id=channel_id,
                    total_words=total_words,
                    total_errors=total_errors,
                    correct=int(line[2]),
                    substitute=int(line[3]),
                    insert=int(line[4]),
                    delete=int(line[5])
                )
            else:
                # P05_S02.U01-0004060-0004382
                # P01_S01.U05-0000192-0001278
                arrray_id = utt_id.strip().split('.')[1].split('-')[0]
                total_errors = int(line[3]) + int(line[4]) + int(line[5])
                total_words = int(line[2]) + int(line[3]) + int(line[5])
                csid_element = csid(
                    uttid=utt_id,
                    arrray_id=arrray_id,
                    total_words=total_words,
                    total_errors=total_errors,
                    correct=int(line[2]),
                    substitute=int(line[3]),
                    insert=int(line[4]),
                    delete=int(line[5])
                )

            if utt_id_filtered not in csid_dict:
                csid_dict[utt_id_filtered] = list()
            csid_dict[utt_id_filtered].append(csid_element)

    all_utterance_words = 0
    all_utterance_errors = 0
    for utt_key in sorted(csid_dict.keys()):
        csid_list = csid_dict[utt_key]
        min_index = find_minimum(csid_list)
        if min_index == -1:
            print("ERROR")
        print(csid_list[min_index].arrray_id)
        all_utterance_words += int(csid_list[min_index].total_words)
        all_utterance_errors += int(csid_list[min_index].total_errors)
        # print(csid_list[min_index].channel_id)
    print(all_utterance_words)
    print(all_utterance_errors)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        fromfile_prefix_chars='@',
        description='Get best WER from list of channles/arrays for each utterance')

    parser.add_argument('chain_directory', help="Path to the basefolder of the decode directory")
    parser.add_argument('suffix_list', help='delimited list input (decoding folder suffixes)', type=str)
    parser.add_argument("audio_type", type=str,
                        choices=["single_microphone", "microphone_array"], default="single_microphone")
    parser.add_argument('output_path', help="Path to generate data directory")
    args = parser.parse_args()

    make_diar_data(**vars(args))
