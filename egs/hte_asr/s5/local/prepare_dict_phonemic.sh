#!/usr/bin/env bash

phonemic_dir=data/local/phonemic/
dst_dir=$phonemic_dir/dict_nosp
silence_phones=$dst_dir/silence_phones.txt
optional_silence=$dst_dir/optional_silence.txt
nonsil_phones=$dst_dir/nonsilence_phones.txt

mkdir -p $dst_dir
echo "Preparing phone lists"
echo SIL > $silence_phones
echo SIL > $optional_silence

local/get_phones_from_lexicon.py data/local/lexicon.txt $nonsil_phones $phonemic_dir/lexicon.txt

(echo '!SIL SIL'; echo '<UNK> SIL'; echo '<Noise/> SIL'; ) |\
cat - $phonemic_dir/lexicon.txt | sort | uniq >$dst_dir/lexicon.txt
echo "Lexicon text file saved as: $dst_dir/lexicon.txt"

exit 0
