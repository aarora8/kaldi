#!/usr/bin/env bash

min_lmwt=7
max_lmwt=17
word_ins_penalty=0.0,0.5,1.0

set -e
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

decode_dir=$1
test_para=$decode_dir/scoring/test_filt_para.txt

cat $decode_dir/scoring/test_filt.txt | \
  local/combine_line_txt_to_paragraph.py > $test_para

for LMWT in $(seq $min_lmwt $max_lmwt); do
    mkdir -p $decode_dir/para/
    cat $decode_dir/scoring/$LMWT.txt | \
    local/combine_line_txt_to_paragraph.py > $decode_dir/para/$LMWT.txt
done

for LMWT in $(seq $min_lmwt $max_lmwt); do
    compute-wer --text --mode=present \
    ark:$test_para ark:$decode_dir/para/$LMWT.txt &> $decode_dir/para/wer_${LMWT} || exit 1;
done

for lmwt in $(seq $min_lmwt $max_lmwt); do
  # adding /dev/null to the command list below forces grep to output the filename
  grep WER $decode_dir/para/wer_${lmwt} /dev/null
done | utils/best_wer.sh  >& $decode_dir/para/best_wer
