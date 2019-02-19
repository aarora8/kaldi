#!/bin/bash
# Copyright 2017    Hossein Hadian
#           2018    Ashish Arora
set -e
stage=0
nj=70
# download_dir{1,2,3} points to the database path on the JHU grid. If you have not
# already downloaded the database you can set it to a local directory
# This corpus can be purchased here:
# https://catalog.ldc.upenn.edu/{LDC2012T15,LDC2013T09/,LDC2013T15/}
download_dir1=/export/corpora/LDC/LDC2012T15/data
download_dir2=/export/corpora/LDC/LDC2013T09/data
download_dir3=/export/corpora/LDC/LDC2013T15/data
writing_condition1=/export/corpora/LDC/LDC2012T15/docs/writing_conditions.tab
writing_condition2=/export/corpora/LDC/LDC2013T09/docs/writing_conditions.tab
writing_condition3=/export/corpora/LDC/LDC2013T15/docs/writing_conditions.tab
data_splits_dir=data/download/data_splits
images_scp_dir=data/local
overwrite=false
subset=true
augment=false
use_extra_corpus_text=true
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh
. ./utils/parse_options.sh  # e.g. this parses the above options
                            # if supplied.
./local/check_tools.sh

mkdir -p data/{train,test,dev}/data
mkdir -p data/local/{train,test,dev}
if [ $stage -le 0 ]; then

  if [ -f data/train/text ] && ! $overwrite; then
    echo "$0: Not processing, probably script have run from wrong stage"
    echo "Exiting with status 1 to avoid data corruption"
    exit 1;
  fi

  echo "$0: preparing data...$(date)"
  local/prepare_data.sh --data_splits $data_splits_dir --download_dir1 $download_dir1 \
                         --download_dir2 $download_dir2 --download_dir3 $download_dir3 \
                         --use_extra_corpus_text $use_extra_corpus_text

  for set in test train dev; do
    data_split_file=$data_splits_dir/madcat.$set.raw.lineid
    local/extract_lines.sh --nj $nj --cmd $cmd --data_split_file $data_split_file \
        --download_dir1 $download_dir1 --download_dir2 $download_dir2 \
        --download_dir3 $download_dir3 --writing_condition1 $writing_condition1 \
        --writing_condition2 $writing_condition2 --writing_condition3 $writing_condition3 \
        --data data/local/$set --subset $subset --augment $augment || exit 1
  done

  echo "$0: Processing data..."
  for set in dev train test; do
    local/process_data.py $download_dir1 $download_dir2 $download_dir3 \
      $data_splits_dir/madcat.$set.raw.lineid data/$set $images_scp_dir/$set/images.scp \
      $writing_condition1 $writing_condition2 $writing_condition3 --augment $augment --subset $subset
    image/fix_data_dir.sh data/${set}
  done

fi

if [ $stage -le 1 ]; then
  echo "$0: Obtaining image groups. calling get_image2num_frames $(date)."
  image/get_image2num_frames.py data/train
  image/get_allowed_lengths.py --frame-subsampling-factor 4 10 data/train

  for set in test dev train; do
    echo "$0: Extracting features and calling compute_cmvn_stats for dataset:  $set. $(date)"
    local/extract_features.sh --nj $nj --cmd $cmd --feat-dim 40 data/$set
    steps/compute_cmvn_stats.sh data/$set || exit 1;
  done
  echo "$0: Fixing data directory for train dataset $(date)."
  utils/fix_data_dir.sh data/train
fi

if [ $stage -le 2 ]; then
  echo "$0: Preparing BPE..."
  cut -d' ' -f2- data/train/text | utils/lang/bpe/reverse.py | \
    utils/lang/bpe/prepend_words.py | \
    utils/lang/bpe/learn_bpe.py -s 700 > data/local/bpe.txt

  for set in test train dev; do
    cut -d' ' -f1 data/$set/text > data/$set/ids
    cut -d' ' -f2- data/$set/text | utils/lang/bpe/reverse.py | \
      utils/lang/bpe/prepend_words.py | \
      utils/lang/bpe/apply_bpe.py -c data/local/bpe.txt \
      | sed 's/@@//g' > data/$set/bpe_text

    mv data/$set/text data/$set/text.old
    paste -d' ' data/$set/ids data/$set/bpe_text > data/$set/text
    rm -f data/$set/bpe_text data/$set/ids
  done
fi

if [ $stage -le 3 ]; then
  echo "$0:Preparing dictionary and lang..."
  local/prepare_dict.sh
  utils/prepare_lang.sh --num-sil-states 4 --num-nonsil-states 8 --sil-prob 0.0 --position-dependent-phones false \
                        data/local/dict "<sil>" data/lang/temp data/lang
  utils/lang/bpe/add_final_optional_silence.sh --final-sil-prob 0.5 data/lang
fi

if [ $stage -le 4 ]; then
  utils/subset_data_dir.sh --speakers data/train 300000 data/train_sup || exit 1
  utils/subset_data_dir.sh data/train_sup 10000 data/train_sup10k || exit 1
  utils/subset_data_dir.sh --spk-list <(utils/filter_scp.pl --exclude data/train_sup/spk2utt data/train/spk2utt) data/train data/train_unsup10k

  cp data/train/allowed_lengths.txt data/train_sup10k/allowed_lengths.txt
  cp data/train/allowed_lengths.txt data/train_unsup10k/allowed_lengths.txt
  cp data/train/allowed_lengths.txt data/train_sup/allowed_lengths.txt

  utils/subset_data_dir.sh --speakers data/train_unsup10k 100000 data/train_unsup10k_100k
  cp data/train/allowed_lengths.txt data/train_unsup10k_100k/allowed_lengths.txt

  utils/subset_data_dir.sh data/test 2000 data/test_2k2
fi

if [ $stage -le 5 ]; then
  utils/combine_data.sh data/semisup10k_100k \
    data/train_sup10k data/train_unsup10k_100k || exit 1
fi

if [ $stage -le 6 ]; then
  echo "$0: Calling the flat-start chain recipe... $(date)."
  local/chain/run_e2e_cnn.sh --train-set train_sup10k --nj 30
fi

if [ $stage -le 7 ]; then
  echo "$0: Aligning the training data using the e2e chain model..."
  steps/nnet3/align.sh --nj 50 --cmd "$cmd" \
                       --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0 --acoustic-scale=1.0' \
                       data/train_sup10k data/lang exp/chain/e2e_cnn_1a exp/chain/e2e_ali_train
fi

if [ $stage -le 8 ]; then
  echo "$(date) stage 5: Building a tree and training a regular chain model using the e2e alignments..."
  local/chain/run_cnn_e2eali.sh --train-set train_sup10k --nj 50
fi

lang_decode=data/lang_test
decode_e2e=false
if [ $stage -le 9 ]; then
  echo "$0: Estimating a language model for decoding..."
  mkdir -p data/local/pocolm_ex250k
  utils/filter_scp.pl --exclude data/train_unsup10k_100k/utt2spk \
    data/train/text > data/local/pocolm_ex250k/text.tmp

  local/train_lm.sh
  utils/format_lm.sh data/lang data/local/local_lm/data/arpa/6gram_unpruned.arpa.gz \
                     data/local/dict/lexicon.txt $lang_decode
fi

if [ $stage -le 10 ] && $decode_e2e; then
  echo "$0: $(date) stage 10: decoding end2end setup..."
  utils/mkgraph.sh --self-loop-scale 1.0 $lang_decode \
    exp/chain/e2e_cnn_1a/ exp/chain/e2e_cnn_1a/graph || exit 1;

  steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 --nj 30 --cmd "$cmd" \
    exp/chain/e2e_cnn_1a/graph data/test_2k2 exp/chain/e2e_cnn_1a/decode_test || exit 1;
fi

lat_dir=exp/chain/e2e_train_sup10k_lats
if [ $stage -le 11 ]; then
  local/semisup/chain/run_cnn_chainali_semisupervised_1b.sh \
    --supervised-set train_sup10k \
    --unsupervised-set train_unsup10k_100k \
    --sup-chain-dir exp/chain/cnn_e2eali_1b \
    --sup-lat-dir exp/chain/e2e_train_sup10k_lats \
    --sup-tree-dir exp/chain/tree_e2e \
    --tdnn-affix _1b_tol1_beam4 \
    --exp-root exp/semisup_56k || exit 1
fi
