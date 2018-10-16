#!/usr/bin/env python3

""" This script creates paragraph level decoding text file. It reads 
    the line level decoding text file and combines them to get
    paragraph level decoding.
  Eg. local/paragraph_decoding.py exp/chain/cnn_e2eali_1d/decode_test/scoring_kaldi
  Eg. Input:  writer000000_eval2011-0_000001  Comme indiqué dans
              writer000000_eval2011-0_000002  habitation n° DVT 36
              writer000000_eval2011-0_000003  de mon domicile
      Output: writer000000_eval2011-0 Comme indiqué dans habitation n° DVT 36 de mon domicile
"""

import argparse
import os
parser = argparse.ArgumentParser(description="""Creates line images from page image.""")
parser.add_argument('line_decoding_path', type=str,
                    help='Path to the line level decoding text file')
args = parser.parse_args()

### main ###
in_txt_path = os.path.join(args.line_decoding_path)

in_txt_path_vect = in_txt_path.strip().split('/')
lmwt = in_txt_path_vect[-1].split('.')[0]
wip = in_txt_path_vect[-2].split('_')[-1]
out_dir_path = "/".join(in_txt_path_vect[:-1])

text_file = os.path.join(out_dir_path, str(lmwt) + '.para.txt')
text_fh = open(text_file, 'w', encoding='utf-8')
id_file = os.path.join(out_dir_path, str(lmwt) + '.id.txt')
id_fh = open(id_file, 'w', encoding='utf-8')

paragraph_txt_dict = dict()
with open(in_txt_path, encoding='utf-8') as f:
    for line in f:
        line_vect = line.strip().split(' ')
        line_id = int(line_vect[0].split('_')[-1])
        paragraph_id = line_vect[0].split('-')[-1]
        paragraph_id = int(paragraph_id.split('_')[0])
        line_text = " ".join(line_vect[1:])
        if paragraph_id not in paragraph_txt_dict.keys():
            paragraph_txt_dict[paragraph_id] = dict()
        paragraph_txt_dict[paragraph_id][line_id] = line_text


para_txt_dict = dict()
for para_id in sorted(paragraph_txt_dict.keys()):
    para_txt = ""
    id_txt = ""
    for line_id in sorted(paragraph_txt_dict[para_id]):
        text = paragraph_txt_dict[para_id][line_id]
        para_txt = para_txt + " " + text
        id_txt = id_txt + " " + str(line_id)
    para_txt_dict[para_id] = para_txt
    utt_id = 'writer' + str(para_id).zfill(6) + '_' + 'eval2011-' + str(para_id)
    text_fh.write(utt_id + ' ' + para_txt + '\n')
    id_fh.write(utt_id + ' ' + id_txt + '\n')
