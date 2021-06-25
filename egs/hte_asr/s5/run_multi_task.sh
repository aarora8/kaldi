#!/bin/bash

. ./cmd.sh
. ./path.sh

# Train systems,
nj=30 # number of parallel jobs,
stage=0
. utils/parse_options.sh
set -euo pipefail

if [ $stage -le 1 ]; then
  cp -r corpora_data/data .
  cp -r corpora_data/data/train data/phonemic/
  cp -r corpora_data/data/dev data/phonemic/
  local/prepare_dict_phonemic.sh
  utils/prepare_lang.sh data/local/phonemic/dict_nosp '<UNK>' data/local/phonemic/lang_nosp data/phonemic/lang_nosp
  utils/validate_lang.pl data/phonemic/lang_nosp
fi

if [ $stage -le 2 ]; then
  cp -r corpora_data/data/train data/graphemic/
  cp -r corpora_data/data/dev data/graphemic/
  local/prepare_dict_graphemic.sh
  utils/prepare_lang.sh data/local/graphemic/dict_nosp '<UNK>' data/local/graphemic/lang_nosp data/graphemic/lang_nosp
  utils/validate_lang.pl data/graphemic/lang_nosp
fi

if [ $stage -le 3 ] ; then
  local/prepare_lm.sh

  utils/format_lm.sh  data/phonemic/lang_nosp/ data/local/lm/lm.gz \
    data/local/phonemic/lexicon.txt  data/phonemic/lang_nosp_test

  utils/format_lm.sh  data/graphemic/lang_nosp/ data/local/lm/lm.gz \
    data/local/graphemic/lexicon.txt  data/graphemic/lang_nosp_test
fi

for dataset in phonemic graphemic; do

  data_dir=data/$dataset/
  exp_dir=exp/$dataset/
  mkdir -p $exp_dir

  if [ $stage -le 4 ]; then
    steps/make_mfcc.sh --nj 75 --cmd "$train_cmd" $data_dir/train
    steps/compute_cmvn_stats.sh $data_dir/train
    utils/fix_data_dir.sh $data_dir/train
  fi
  
  # monophone training
  if [ $stage -le 5 ]; then
    utils/subset_data_dir.sh $data_dir/train 15000 $data_dir/train_15k
    steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
      $data_dir/train_15k $data_dir/lang_nosp_test $exp_dir/mono
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
      $data_dir/train $data_dir/lang_nosp_test $exp_dir/mono $exp_dir/mono_ali
  fi
  
  # context-dep. training with delta features.
  if [ $stage -le 6 ]; then
    steps/train_deltas.sh --cmd "$train_cmd" \
      5000 80000 $data_dir/train $data_dir/lang_nosp_test $exp_dir/mono_ali $exp_dir/tri1
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
      $data_dir/train $data_dir/lang_nosp_test $exp_dir/tri1 $exp_dir/tri1_ali
  fi
  
  if [ $stage -le 7 ]; then
    steps/train_lda_mllt.sh --cmd "$train_cmd" \
      --splice-opts "--left-context=3 --right-context=3" \
      5000 80000 $data_dir/train $data_dir/lang_nosp_test $exp_dir/tri1_ali $exp_dir/tri2
    steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
      $data_dir/train $data_dir/lang_nosp_test $exp_dir/tri2 $exp_dir/tri2_ali
  fi
  
  if [ $stage -le 8 ]; then
    steps/train_sat.sh --cmd "$train_cmd" \
      5000 80000 $data_dir/train $data_dir/lang_nosp_test $exp_dir/tri2_ali $exp_dir/tri3
    steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
      $data_dir/train $data_dir/lang_nosp_test $exp_dir/tri3 $exp_dir/tri3_ali
  fi
done

if [ $stage -le 14 ]; then
  echo ============================================================================
  echo "              augmentation, i-vector extraction, and chain model training"
  echo ============================================================================
  local/chain/run_tdnn_mt.sh
fi
