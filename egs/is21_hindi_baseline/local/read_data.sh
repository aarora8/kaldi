#!/bin/bash

if [ -e array_wer_1.txt ]; then
  rm array_wer_1.txt 
  rm array_wer_2.txt
fi

#while read -r line; do
#    recording_id=$(echo "$line" | cut -f1 -d " ")
#    path=$(echo "$line" | cut -f2 -d " ")
#    echo " $recording_id corpus/data/$1/$path" >> array_wer_1.txt
#done < data/$1/wav.scp
#
#while read -r line; do
#    recording_id=$(echo "$line" | cut -f1 -d " ")
#    path=$(echo "$line" | cut -f2 -d " ")
#    echo " $recording_id corpus/data/$2/$path" >> array_wer_2.txt
#done < data/$2/wav.scp

while read -r line; do
    recording_id=$(echo "$line" | cut -f1 -d " ")
    echo "$recording_id" >> array_wer_3.txt
done < /export/b09/mwiesner/LFMMI_EBM2/LFMMI_EBM/codeswitch_hindi/vocab_test_counts
