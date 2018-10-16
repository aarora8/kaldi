#!/bin/bash

min_lmwt=7
max_lmwt=17
word_ins_penalty=0.0,0.5,1.0

set -e
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

dir=$1
best_lmwt=$(cat $dir/scoring_kaldi/wer_details/lmwt)
best_wip=$(cat $dir/scoring_kaldi/wer_details/wip)
local/paragraph_decoding.py $dir/scoring_kaldi/penalty_$best_wip/$best_lmwt.txt

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  LMWT=$min_lmwt:$max_lmwt \
      local/paragraph_decoding.py $dir/scoring_kaldi/penalty_$wip/LMWT.txt \| \
      compute-wer --text --mode=present \
      ark:$dir/scoring_kaldi/test_filt.txt  ark,p:- ">&" $dir/wer_LMWT_$wip || exit 1;

  done
