#!/usr/bin/env bash
# Begin configuration section.
nj=4
stage=0
decode_diarize_stage=4
enhancement=gss_multiarray

# training data
train_set=train_worn_simu_u400k
test_sets="dev_${enhancement}"

. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh
./local/check_tools.sh || exit 1

if [ $stage -le 0 ]; then
  echo "$0 download pre-train ASR model"
  wget http://kaldi-asr.org/models/12/0012_asr_v1.tar.gz
  tar -xvzf 0012_asr_v1.tar.gz
  
fi

if [ $stage -le 1 ]; then
  echo "$0 perform decoding using the rttm from diarization and enhanced GSS wav files"
  for datadir in ${test_sets}; do
    local/decode_diarized.sh --nj $nj --cmd "$decode_cmd" --stage $decode_diarize_stage \
      local/rttm data/$datadir data/lang \
      exp/chain_${train_set}_cleaned_rvb exp/nnet3_${train_set}_cleaned_rvb \
      data/${datadir}_diarized || exit 1
  done
fi
exit 0;
