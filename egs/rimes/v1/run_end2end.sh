#!/bin/bash
# Copyright 2017    Hossein Hadian

set -e
stage=0
nj=50
overwrite=false
train_set=train_aug
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh
. ./utils/parse_options.sh  # e.g. this parses the above options
                            # if supplied.
if [ $stage -le 0 ]; then

  if [ -f data/train/text ] && ! $overwrite; then
    echo "$0: Not processing, probably script have run from wrong stage"
    echo "Exiting with status 1 to avoid data corruption"
    exit 1;
  fi

  echo "$0: Preparing data..."
  local/prepare_data.sh
fi

mkdir -p data/{train,test}/data
if [ $stage -le 1 ]; then
  echo "$(date) stage 1: getting allowed image widths for e2e training..."
  image/get_image2num_frames.py --feat-dim 40 data/train
  image/get_allowed_lengths.py --frame-subsampling-factor 4 10 data/train
  echo "$(date) Extracting features, creating feats.scp file"
  for set in train test; do
    local/extract_features.sh --nj $nj --cmd "$cmd" \
    --feat-dim 40 data/${set}
    steps/compute_cmvn_stats.sh data/${set} || exit 1;
  done
  utils/fix_data_dir.sh data/train
fi

if [ $stage -le 2 ]; then
  echo "$(date) stage 2: Performing augmentation, it will double training data"
  local/augment_data.sh --nj $nj --cmd "$cmd" --feat-dim 40 data/train data/$train_set data
  steps/compute_cmvn_stats.sh data/$train_set || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "$0: Preparing BPE..."
  # getting non-silence phones.
  cut -d' ' -f2- data/train/text | \
python3 <(
cat << "END"
import os, sys, io;
infile = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8');
output = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8');
phone_dict = dict();
for line in infile:
    line_vect = line.strip().split();
    for word in line_vect:
        for phone in word:
            phone_dict[phone] = phone;
for phone in phone_dict.keys():
      output.write(phone+ '\n');
END
   ) > data/local/phones.txt

  cut -d' ' -f2- data/train/text > data/local/train_data.txt
  cat data/local/phones.txt data/local/train_data.txt | \
    utils/lang/bpe/prepend_words.py | \
    utils/lang/bpe/learn_bpe.py -s 700 > data/local/bpe.txt
  for set in test train $train_set; do
    cut -d' ' -f1 data/$set/text > data/$set/ids
    cut -d' ' -f2- data/$set/text | \
      utils/lang/bpe/prepend_words.py | utils/lang/bpe/apply_bpe.py -c data/local/bpe.txt \
      | sed 's/@@//g' > data/$set/bpe_text
    mv data/$set/text data/$set/text.old
    paste -d' ' data/$set/ids data/$set/bpe_text > data/$set/text
  done
fi

if [ $stage -le 4 ]; then
  echo "$0: Estimating a language model for decoding..."
  local/train_lm.sh
fi

if [ $stage -le 5 ]; then
  echo "$0: Preparing dictionary and lang..."
  local/prepare_dict.sh
  utils/prepare_lang.sh --num-sil-states 4 --num-nonsil-states 8 --sil-prob 0.0 --position-dependent-phones false \
                        data/local/dict "<sil>" data/lang/temp data/lang
  utils/lang/bpe/add_final_optional_silence.sh --final-sil-prob 0.5 data/lang
  utils/format_lm.sh data/lang data/local/local_lm/data/arpa/3gram_unpruned.arpa.gz \
                     data/local/dict/lexicon.txt data/lang
fi

if [ $stage -le 6 ]; then
  echo "$0: Calling the flat-start chain recipe..."
  local/chain/run_e2e_cnn.sh --train_set $train_set
fi

if [ $stage -le 7 ]; then
  echo "$0: Aligning the training data using the e2e chain model..."
  steps/nnet3/align.sh --nj 50 --cmd "$cmd" \
                       --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0 --acoustic-scale=1.0' \
                       data/$train_set data/lang exp/chain/e2e_cnn_1b exp/chain/e2e_ali_train
fi

if [ $stage -le 8 ]; then
  echo "$0: Building a tree and training a regular chain model using the e2e alignments..."
  local/chain/run_cnn_e2eali.sh --train_set $train_set
fi
