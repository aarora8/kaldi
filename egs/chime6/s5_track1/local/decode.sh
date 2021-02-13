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

# chime5 main directory path
# please change the path accordingly
chime5_corpus=/export/corpora4/CHiME5
# chime6 data directories, which are generated from ${chime5_corpus},
# to synchronize audio files across arrays and modify the annotation (JSON) file accordingly
chime6_corpus=${PWD}/CHiME6
json_dir=${chime6_corpus}/transcriptions
audio_dir=${chime6_corpus}/audio

enhanced_dir=enhanced
if [[ ${enhancement} == *gss* ]]; then
  enhanced_dir=${enhanced_dir}_multiarray
  enhancement=${enhancement}_multiarray
fi

if [[ ${enhancement} == *beamformit* ]]; then
  enhanced_dir=${enhanced_dir}
  enhancement=${enhancement}
fi

enhanced_dir=$(utils/make_absolute.sh $enhanced_dir) || exit 1
test_sets="dev_${enhancement}"

./local/check_tools.sh || exit 1

if [ $stage -le 2 ] && [[ ${enhancement} == *gss* ]]; then
  for dset in ${test_sets}; do
    utils/copy_data_dir.sh data/${dset} data/${dset}_orig
  done

  for dset in ${test_sets}; do
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_orig data/${dset}
  done
fi

if [ $stage -le 2 ] && [[ ${enhancement} == *beamformit* ]]; then
  echo "$0: fix data..."
  for dset in ${test_sets}; do
    utils/copy_data_dir.sh data/${dset} data/${dset}_nosplit
    mkdir -p data/${dset}_nosplit_fix
    for f in segments text wav.scp; do
      if [ -f data/${dset}_nosplit/$f ]; then
        cp data/${dset}_nosplit/$f data/${dset}_nosplit_fix
      fi
    done
    awk -F "_" '{print $0 "_" $3}' data/${dset}_nosplit/utt2spk > data/${dset}_nosplit_fix/utt2spk
    utils/utt2spk_to_spk2utt.pl data/${dset}_nosplit_fix/utt2spk > data/${dset}_nosplit_fix/spk2utt
  done

  for dset in ${test_sets}; do
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_nosplit_fix data/${dset}
  done
fi

if [ $stage -le 3 ]; then
  for data in $test_sets; do
    if [ ! -s data/${data}_hires/feats.scp ]; then
      utils/copy_data_dir.sh data/$data data/${data}_hires
      steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 80 --cmd "$train_cmd" data/${data}_hires
      steps/compute_cmvn_stats.sh data/${data}_hires
      utils/fix_data_dir.sh data/${data}_hires
    fi
  done
fi
