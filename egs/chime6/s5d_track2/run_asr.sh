#!/usr/bin/env bash
# Begin configuration section.
nj=8
stage=0
sad_stage=0
score_sad=true
diarizer_stage=0
decode_diarize_stage=0
score_stage=0

enhancement=beamformit

# option to use the new RTTM reference for sad and diarization
use_new_rttm_reference=true
if $use_new_rttm_reference == "true"; then
  git clone https://github.com/nateanl/chime6_rttm
fi

# chime5 main directory path
# please change the path accordingly
chime5_corpus=/export/corpora4/CHiME5
# chime6 data directories, which are generated from ${chime5_corpus},
# to synchronize audio files across arrays and modify the annotation (JSON) file accordingly
chime6_corpus=${PWD}/CHiME6
json_dir=${chime6_corpus}/transcriptions
audio_dir=${chime6_corpus}/audio

enhanced_dir=enhanced
enhanced_dir=$(utils/make_absolute.sh $enhanced_dir) || exit 1

# training data
train_set=train_worn_simu_u400k
test_sets="dev_${enhancement}_dereverb eval_${enhancement}_dereverb"

. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh
. ./conf/sad.conf

# This script also needs the phonetisaurus g2p, srilm, beamformit
./local/check_tools.sh || exit 1

#######################################################################
# Perform SAD on the dev/eval data
#######################################################################
dir=exp/segmentation${affix}
sad_work_dir=exp/sad${affix}_${nnet_type}/
sad_nnet_dir=$dir/tdnn_${nnet_type}_sad_1a
#######################################################################
# Decode diarized output using trained chain model
#######################################################################
if [ $stage -le 5 ]; then
  for datadir in ${test_sets}; do
    local/decode_diarized.sh --nj $nj --cmd "$decode_cmd" --stage $decode_diarize_stage \
      exp/${datadir}_${nnet_type}_seg_diarization data/$datadir data/lang \
      exp/chain_${train_set}_cleaned_rvb exp/nnet3_${train_set}_cleaned_rvb \
      data/${datadir}_diarized || exit 1
  done
fi

#######################################################################
# Score decoded dev/eval sets
#######################################################################
if [ $stage -le 6 ]; then
  # final scoring to get the challenge result
  # please specify both dev and eval set directories so that the search parameters
  # (insertion penalty and language model weight) will be tuned using the dev set
  local/score_for_submit.sh --stage $score_stage \
      --dev_decodedir exp/chain_${train_set}_cleaned_rvb/tdnn1b_sp/decode_dev_beamformit_dereverb_diarized_2stage \
      --dev_datadir dev_beamformit_dereverb_diarized_hires \
      --eval_decodedir exp/chain_${train_set}_cleaned_rvb/tdnn1b_sp/decode_eval_beamformit_dereverb_diarized_2stage \
      --eval_datadir eval_beamformit_dereverb_diarized_hires
fi
exit 0;
