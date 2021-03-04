#!/usr/bin/env bash

min_lmwt=7
max_lmwt=17
word_ins_penalty=0.0,0.5,1.0

set -e
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

decode_dir=$1
test_para=$decode_dir/scoring_kaldi/test_filt_para.txt

cat $decode_dir/scoring_kaldi/test_filt.txt | \
  local/combine_line_txt_to_paragraph.py > $test_para

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for LMWT in $(seq $min_lmwt $max_lmwt); do
      mkdir -p $decode_dir/para/penalty_$wip
      cat $decode_dir/scoring_kaldi/penalty_$wip/$LMWT.txt | \
      local/combine_line_txt_to_paragraph.py > $decode_dir/para/penalty_$wip/$LMWT.txt
  done
done

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for LMWT in $(seq $min_lmwt $max_lmwt); do
      compute-wer --text --mode=present \
      ark:$test_para ark:$decode_dir/para/penalty_$wip/$LMWT.txt &> $decode_dir/para/wer_${LMWT}_${wip} || exit 1;
  done
done

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  for lmwt in $(seq $min_lmwt $max_lmwt); do
    # adding /dev/null to the command list below forces grep to output the filename
    grep WER $decode_dir/para/wer_${lmwt}_${wip} /dev/null
  done
done | utils/best_wer.sh  >& $decode_dir/para/best_wer

mkdir -p $decode_dir/para/scoring_kaldi/
best_wer_file=$(awk '{print $NF}' $decode_dir/para/best_wer)
best_wip=$(echo $best_wer_file | awk -F_ '{print $NF}')
best_lmwt=$(echo $best_wer_file | awk -F_ '{N=NF-1; print $N}')

mkdir -p $decode_dir/para/scoring_kaldi/wer_details
echo $best_lmwt > $decode_dir/para/scoring_kaldi/wer_details/lmwt # record best language model weight
echo $best_wip > $decode_dir/para/scoring_kaldi/wer_details/wip # record best word insertion penalty

$cmd $decode_dir/para/scoring_kaldi/stats1.log \
  cat $decode_dir/para/penalty_$best_wip/$best_lmwt.txt \| \
  align-text --special-symbol="'***'" ark:$decode_dir/scoring_kaldi/test_filt_para.txt ark:- ark,t:- \|  \
  utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" \| tee $decode_dir/para/scoring_kaldi/wer_details/per_utt \|\
   utils/scoring/wer_per_spk_details.pl data/test/utt2spk \> $decode_dir/para/scoring_kaldi/wer_details/per_spk || exit 1;

$cmd $decode_dir/para/scoring_kaldi/stats2.log \
  cat $decode_dir/para/scoring_kaldi/wer_details/wer_details/per_utt \| \
  utils/scoring/wer_ops_details.pl --special-symbol "'***'" \| \
  sort -b -i -k 1,1 -k 4,4rn -k 2,2 -k 3,3 \> $decode_dir/para/scoring_kaldi/wer_details/ops || exit 1;

