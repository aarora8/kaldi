#!/usr/bin/env bash

# Copyright 2016 Johns Hopkins University (Author: Daniel Povey, Vijayaditya Peddinti)
#           2019 Vimal Manohar 
# Apache 2.0.

# This script does 2-stage decoding where the first stage is used to get 
# reliable frames for i-vector extraction.

set -e

# general opts
iter=
stage=0
nj=30
affix=  # affix for decode directory

# ivector opts
max_count=75  # parameter for extract_ivectors.sh
sub_speaker_frames=6000
ivector_scale=0.75
get_weights_from_ctm=true
weights_file=   # use weights from this archive (must be compressed using gunzip)
silence_weight=0.00001   # apply this weight to silence frames during i-vector extraction
ivector_dir=exp/nnet3

# decode opts
pass2_decode_opts="--min-active 1000"
lattice_beam=8
frames_per_chunk=50 # change for (B)LSTM
acwt=1.0 # important to change this when using chain models
post_decode_acwt=10.0 # important to change this when using chain models

graph_affix=

score_opts="--min-lmwt 6 --max-lmwt 13"

. ./cmd.sh
[ -f ./path.sh ] && . ./path.sh
. utils/parse_options.sh || exit 1;

if [ $# -ne 4 ]; then
  echo "Usage: $0 [options] <data-dir> <lang-dir> <graph-dir> <model-dir>"
  echo " Options:"
  echo "    --stage (0|1|2)   # start scoring script from part-way through."
  echo "e.g.:"
  echo "$0 data/dev data/lang exp/tri5a/graph_pp exp/nnet3/tdnn"
  exit 1;
fi

data=$1 # data directory 
lang=$2 # data/lang
graph=$3 #exp/tri5a/graph_pp
dir=$4 # exp/nnet3/tdnn

model_affix=`basename $dir`
ivector_affix=${affix:+_$affix}_chain_${model_affix}${iter:+_iter$iter}
affix=${affix:+_${affix}}${iter:+_iter${iter}}

if [ $stage -le 1 ]; then
  if [ ! -s ${data}_hires/feats.scp ]; then
    utils/copy_data_dir.sh $data ${data}_hires
    steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj $nj --cmd "$train_cmd" ${data}_hires
    steps/compute_cmvn_stats.sh ${data}_hires
    utils/fix_data_dir.sh ${data}_hires
  fi
fi

data_set=$(basename $data)
if [ $stage -le 2 ]; then
  echo "Extracting i-vectors, stage 1"
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
    ${data}_hires $ivector_dir/extractor \
    $ivector_dir/ivectors_${data_set}${ivector_affix}
fi

decode_dir=$dir/decode${graph_affix}_${data_set}${affix}
# generate the lattices
if [ $stage -le 3 ]; then
  echo "Generating lattices, stage 1"
  steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd" \
    --acwt $acwt --post-decode-acwt $post_decode_acwt \
    --frames-per-chunk "$frames_per_chunk" \
    --online-ivector-dir $ivector_dir/ivectors_${data_set}${ivector_affix} \
    $graph ${data}_hires ${decode_dir}
fi
exit 0
