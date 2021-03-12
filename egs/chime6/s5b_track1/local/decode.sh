#!/usr/bin/env bash
#
# Based mostly on the TED-LIUM and Switchboard recipe
#
# Copyright  2017  Johns Hopkins University (Author: Shinji Watanabe and Yenda Trmal)
# Apache 2.0
#
# This script only performs recognition experiments with evaluation data
# This script can be run from run.sh or standalone. 
# To run it standalone, you can download a pretrained chain ASR model using:
# wget http://kaldi-asr.org/models/12/0012_asr_v1.tar.gz
# Once it is downloaded, extract using: tar -xvzf 0012_asr_v1.tar.gz
# and copy the contents of the {data/ exp/} directory to your {data/ exp/}

# Begin configuration section.
decode_nj=20
gss_nj=60
stage=0
enhancement=gss        # for a new enhancement method,
                       # change this variable and stage 4

# training data
train_set=train_worn_simu_u400k
#GSS parameters
multiarray=True
bss_iterations=20
context_samples=240000
# End configuration section
. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh


set -e # exit on error

chime5_corpus=/export/corpora4/CHiME5
chime6_corpus=${PWD}/CHiME6
json_dir=${chime6_corpus}/transcriptions
audio_dir=${chime6_corpus}/audio
enhanced_dir=enhanced
enhanced_dir=${enhanced_dir}_multiarray
enhancement=${enhancement}_multiarray
enhanced_dir=$(utils/make_absolute.sh $enhanced_dir) || exit 1
test_sets="dev_${enhancement} eval_${enhancement}"
./local/check_tools.sh || exit 1

if [ $stage -le 1 ]; then
  echo "$0:  enhance data..."
  if [ ! -d pb_chime5/ ]; then
    local/install_pb_chime5.sh
  fi

  if [ ! -f pb_chime5/cache/chime6.json ]; then
    (
    cd pb_chime5
    miniconda_dir=$HOME/miniconda3/
    export PATH=$miniconda_dir/bin:$PATH
    export CHIME6_DIR=$chime6_corpus
    make cache/chime6.json
    )
  fi

  for dset in dev; do
      local/run_gss_rttm.sh \
        --cmd "$train_cmd" --nj 100 \
        --multiarray outer_array_mics \
        ${dset} ${enhanced_dir}_outer_array_mics \
        ${enhanced_dir}_outer_array_mics || exit 1
  done

  for dset in dev eval; do
      local/prepare_data.sh --mictype gss --arrayid outer_array_mics \
        ${enhanced_dir}_outer_array_mics/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_outer_array_mics
      utils/fix_data_dir.sh data/${dset}_gss_outer_array_mics
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_outer_array_mics
  done
fi


if [ $stage -le 2 ]; then
  for dset in dev eval; do
    for suffix in gss_outer_array_mics; do
      utils/copy_data_dir.sh data/${dset}_${suffix} data/${dset}_${suffix}_orig
      utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_${suffix}_orig data/${dset}_${suffix}
      if [ ! -s data/${dset}_${suffix}_hires/feats.scp ]; then
        utils/copy_data_dir.sh data/${dset}_${suffix} data/${dset}_${suffix}_hires
        steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 80 --cmd "$train_cmd" data/${dset}_${suffix}_hires
        steps/compute_cmvn_stats.sh data/${dset}_${suffix}_hires
        utils/fix_data_dir.sh data/${dset}_${suffix}_hires
      fi
    done
  done
fi


if [ $stage -le 3 ]; then
  for suffix in gss_outer_array_mics; do
    local/chain/run_cnn_tdnn.sh --stage 16 --enhancement $suffix
  done
fi
