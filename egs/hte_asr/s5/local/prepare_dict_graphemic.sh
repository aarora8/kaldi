#!/usr/bin/env bash

graphemic_dir=data/local/graphemic/
dst_dir=$graphemic_dir/dict_nosp
silence_phones=$dst_dir/silence_phones.txt
optional_silence=$dst_dir/optional_silence.txt
nonsil_phones=$dst_dir/nonsilence_phones.txt

mkdir -p $dst_dir
echo "Preparing phone lists"
echo SIL > $silence_phones
echo SIL > $optional_silence

local/create_graphemic_lexicon.py data/local/lexicon.txt $nonsil_phones $graphemic_dir/lexicon.txt

(echo '!SIL SIL'; echo '<UNK> SIL'; echo '<Noise/> SIL'; ) |\
cat - $graphemic_dir/lexicon.txt | sort | uniq >$dst_dir/lexicon.txt
echo "Lexicon text file saved as: $dst_dir/lexicon.txt"

exit 0
