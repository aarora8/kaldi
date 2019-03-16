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
subset=false
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

  image/get_image2num_frames.py data/dev
  image/get_allowed_lengths.py --frame-subsampling-factor 4 10 data/dev

  for set in dev; do
    echo "$0: Extracting features and calling compute_cmvn_stats for dataset:  $set. $(date)"
    local/extract_features.sh --nj $nj --cmd $cmd --feat-dim 40 data/$set
    steps/compute_cmvn_stats.sh data/$set || exit 1;
  done
  echo "$0: Fixing data directory for train dataset $(date)."
  utils/fix_data_dir.sh data/dev
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

# training language model
lang_decode=data/lang_test
if [ $stage -le 4 ]; then
  echo "$0: Estimating a language model for decoding..."
  local/train_lm.sh
  utils/format_lm.sh data/lang data/local/local_lm/data/arpa/6gram_big.arpa.gz \
                     data/local/dict/lexicon.txt $lang_decode
  utils/build_const_arpa_lm.sh data/local/local_lm/data/arpa/6gram_unpruned.arpa.gz \
                               data/lang data/lang_rescore_6g
fi

if [ $stage -le 5 ]; then
  echo "$0:Preparing supervised and unsupervised data..."
  local/get_unique_utterances.py data/train/text.old > data/train/uttlist.full
  head -40000 data/train/uttlist.full > data/train/uttlist.40k
  utils/subset_data_dir.sh --utt-list data/train/uttlist.40k data/train data/train_unsup
  tail +40000 data/train/uttlist.full > data/train/uttlist.tail.80k
  utils/subset_data_dir.sh --utt-list data/train/uttlist.tail.80k data/train data/train_LM

  utils/subset_data_dir.sh data/dev 4000 data/train_sup4k
  local/get_unique_utterances.py data/train_sup4k/text.old > data/train_sup4k/uttlist
  utils/subset_data_dir.sh --utt-list data/train_sup4k/uttlist data/train_sup4k data/train_sup

  local/remove_sup_utts_from_unsup.py data/train_sup/text.old data/train_unsup/text.old > data/local/unsup_uttlist
  utils/subset_data_dir.sh --utt-list data/local/unsup_uttlist data/train_unsup data/train_unsup_unique

  cp data/train/allowed_lengths.txt data/train_unsup_unique/allowed_lengths.txt
  cp data/dev/allowed_lengths.txt data/train_sup/allowed_lengths.txt

  utils/subset_data_dir.sh data/test 5000 data/test_5k
fi

if [ $stage -le 6 ]; then
  echo "$0: Estimating a language model for decoding..."
  local/train_lm.unsup.sh
  utils/format_lm.sh data/lang data/local/local_lm/data/arpa/6gram_unpruned.train80k.arpa.gz \
                     data/local/dict/lexicon.txt data/lang_decode_unsup 
fi

if [ $stage -le 7 ]; then
  utils/combine_data.sh data/semisup \
    data/train_sup data/train_unsup_unique || exit 1
fi

train_set=train_sup
# training flat-start system
if [ $stage -le 8 ]; then
  echo "$0: Calling the flat-start chain recipe... $(date)."
  local/chain/run_e2e_cnn_1a.sh --train-set train_sup
fi

# alignments are used in tree
if [ $stage -le 9 ]; then
  echo "$0: Aligning the training data using the e2e chain model..."
  steps/nnet3/align.sh --nj 50 --cmd "$cmd" \
                       --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0 --acoustic-scale=1.0' \
                       data/train_sup data/lang_e2e exp/chain/e2e_cnn_1a_$train_set exp/chain/flatstartali_$train_set
fi

# training e2eali system
if [ $stage -le 10 ]; then
  echo "$(date) stage 5: Building a tree and training a regular chain model using the e2e alignments..."
  local/chain/run_cnn_e2eali_1a.sh --train-set train_sup --stage 4
fi

# no need for alignments, use same tree from end2endali
if [ $stage -le 11 ]; then
  echo "$0: Aligning the training data using the e2e chain model..."
  steps/nnet3/align.sh --nj 50 --cmd "$cmd" \
                       --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0 --acoustic-scale=1.0' \
                       data/train_sup data/lang_chain exp/chain/cnn_e2eali_1a_$train_set exp/chain/e2eali_$train_set
fi

# training baseline system
if [ $stage -le 12 ]; then
  echo "$0: chain model using the chainali alignments..."
  local/chain/run_cnn_chainali_1a.sh --stage 2 --train-set train_sup
fi

# training oracle system
train_set=semisup
if [ $stage -le 13 ]; then
  echo "$(date) stage 5: Building a tree and training a regular chain model using the e2e alignments..."
  local/chain/run_cnn_chainali_oracle_1a.sh --train-set semisup --stage 2
fi

# training semi-supervised system
train_set=train_sup
if [ $stage -le 14 ]; then
  local/chain/run_cnn_chainali_semisupervised_1a.sh \
    --supervised-set train_sup \
    --unsupervised-set train_unsup_unique \
    --sup-chain-dir exp/chain/cnn_chainali_1a_$train_set \
    --sup-lat-dir exp/chain/chainali_${train_set}_lats \
    --sup-tree-dir exp/chain/tree_e2eali_${train_set} \
    --tdnn-affix _1a_tol1_beam4 \
    --exp-root exp/semisup.unsup40k || exit 1
fi
