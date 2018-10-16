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
test_para=$dir/scoring_kaldi/test_filt_para.txt

cat $dir/scoring_kaldi/test_filt.txt | \
  local/combine_line_txt_to_paragraph.py > $test_para

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for LMWT in $(seq $min_lmwt $max_lmwt); do
      mkdir -p $dir/para/penalty_$wip
      cat $dir/scoring_kaldi/penalty_$wip/$LMWT.txt | \
      local/combine_line_txt_to_paragraph.py > $dir/para/penalty_$wip/$LMWT.txt
  done
done

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for LMWT in $(seq $min_lmwt $max_lmwt); do
      compute-wer --text --mode=present \
      ark:$test_para ark:$dir/para/penalty_$wip/$LMWT.txt > $dir/para/wer_${LMWT}_${wip} || exit 1;
  done
done

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for lmwt in $(seq $min_lmwt $max_lmwt); do
    # adding /dev/null to the command list below forces grep to output the filename
    grep WER $dir/para/wer_${lmwt}_${wip} /dev/null
  done
done | utils/best_wer.sh  >& $dir/para/best_wer || exit 1
