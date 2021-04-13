#!/usr/bin/env bash
# Begin configuration section.
nj=8
stage=0
sad_stage=0
score_sad=true
diarizer_stage=0
decode_diarize_stage=0
score_stage=0
enhancement=gss_multiarray

# training data
train_set=train_worn_simu_u400k
test_sets="dev_${enhancement}"

. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh

# This script also needs the phonetisaurus g2p, srilm, beamformit
./local/check_tools.sh || exit 1

#######################################################################
# Decode diarized output using trained chain model
# echo "e.g.: $0 data/rttm data/dev data/lang_chain exp/chain_train_worn_simu_u400k_cleaned_rvb \
#                 exp/nnet3_train_worn_simu_u400k_cleaned_rvb data/dev_diarized"
# echo "Usage: $0 <rttm-dir> <in-data-dir> <lang-dir> <model-dir> <ivector-dir> <out-dir>"
#######################################################################
if [ $stage -le 0 ]; then
  for datadir in ${test_sets}; do
    local/decode_diarized.sh --nj $nj --cmd "$decode_cmd" --stage $decode_diarize_stage \
      data/$datadir data/$datadir data/lang \
      exp/chain_${train_set}_cleaned_rvb exp/nnet3_${train_set}_cleaned_rvb \
      data/${datadir}_diarized || exit 1
  done
fi
exit 0;
