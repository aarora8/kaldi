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

if [ $stage -le 0 ]; then
  echo "$0:  prepare data..."
  # dev worn is needed for the LM part
  for dataset in dev eval; do
    for mictype in u01 u02 u05 u06; do
      local/prepare_data.sh --mictype ${mictype} \
          ${audio_dir}/${dataset} ${json_dir}/${dataset} \
          data/${dataset}_${mictype}
      utils/validate_data_dir.sh --no-feats data/${dataset}_${mictype}
    done
  done

  for dataset in dev eval; do
    for mictype in u01 u02 u05 u06; do
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_ch1
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_ch2
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_ch3
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_ch4
 
      cp data/${dataset}_${mictype}_ch1/utt2spk data/${dataset}_${mictype}_ch1/utt2spk_temp
      cp data/${dataset}_${mictype}_ch2/utt2spk data/${dataset}_${mictype}_ch2/utt2spk_temp
      cp data/${dataset}_${mictype}_ch3/utt2spk data/${dataset}_${mictype}_ch3/utt2spk_temp
      cp data/${dataset}_${mictype}_ch4/utt2spk data/${dataset}_${mictype}_ch4/utt2spk_temp

      grep '.CH1-' data/${dataset}_${mictype}_ch1/utt2spk_temp > data/${dataset}_${mictype}_ch1/utt2spk
      grep '.CH2-' data/${dataset}_${mictype}_ch2/utt2spk_temp > data/${dataset}_${mictype}_ch2/utt2spk
      grep '.CH3-' data/${dataset}_${mictype}_ch3/utt2spk_temp > data/${dataset}_${mictype}_ch3/utt2spk
      grep '.CH4-' data/${dataset}_${mictype}_ch4/utt2spk_temp > data/${dataset}_${mictype}_ch4/utt2spk

      utils/fix_data_dir.sh data/${dataset}_${mictype}_ch1
      utils/fix_data_dir.sh data/${dataset}_${mictype}_ch2
      utils/fix_data_dir.sh data/${dataset}_${mictype}_ch3
      utils/fix_data_dir.sh data/${dataset}_${mictype}_ch4

      rm -r data/${dataset}_${mictype}
    done
  done
fi

if [ $stage -le 1 ]; then
  echo "$0:  enhance data..."
#  if [ ! -d pb_chime5/ ]; then
#    local/install_pb_chime5.sh
#  fi
#
#  if [ ! -f pb_chime5/cache/chime6.json ]; then
#    (
#    cd pb_chime5
#    miniconda_dir=$HOME/miniconda3/
#    export PATH=$miniconda_dir/bin:$PATH
#    export CHIME6_DIR=$chime6_corpus
#    make cache/chime6.json
#    )
#  fi
#
#  for dset in dev eval; do
#    for reference_array in U01 U02 U05 U06; do
#      local/run_gss.sh \
#        --cmd "$train_cmd" --nj 100 \
#        --multiarray False \
#         --reference_array $reference_array \
#        ${dset} \
#        ${enhanced_dir}_$reference_array \
#        ${enhanced_dir}_$reference_array || exit 1
#    done
#  done

  enhanced_dir=/export/c12/aarora8/CHiME_gss/s5_track1/enhanced_multiarray
  for dset in dev eval; do
    for reference_array in U01 U02 U05 U06; do
      local/prepare_data.sh --mictype gss --arrayid $reference_array \
        ${enhanced_dir}_$reference_array/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_$reference_array
      utils/fix_data_dir.sh data/${dset}_gss_$reference_array
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_$reference_array || exit 1
    done
  done
fi

if [ $stage -le 2 ]; then
  echo "$0:  enhance data..."
#  for dset in dev eval; do
#      local/run_gss.sh \
#        --cmd "$train_cmd" --nj 100 \
#        --multiarray False \
#        ${dset} ${enhanced_dir}_reference \
#        ${enhanced_dir}_reference || exit 1
#    done

  enhanced_dir=/export/c12/aarora8/CHiME_gss/s5d_track1/enhanced_multiarray
  for dset in dev eval; do
      local/prepare_data.sh --mictype gss --arrayid reference \
        ${enhanced_dir}_reference/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_reference
      utils/fix_data_dir.sh data/${dset}_gss_reference
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_reference
  done
fi

if [ $stage -le 3 ]; then
  echo "$0:  enhance data..."
#  for dset in dev eval; do
#      local/run_gss.sh \
#        --cmd "$train_cmd" --nj 100 \
#        --multiarray first_array_mics \
#        ${dset} ${enhanced_dir}_first_array_mics \
#        ${enhanced_dir}_first_array_mics || exit 1
#    done

  enhanced_dir=/export/c12/aarora8/CHiME_gss/s5d_track1/enhanced_multiarray
  for dset in dev eval; do
      local/prepare_data.sh --mictype gss --arrayid first_array_mics \
        ${enhanced_dir}_first_array_mics/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_first_array_mics
      utils/fix_data_dir.sh data/${dset}_gss_first_array_mics
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_first_array_mics
  done
fi

if [ $stage -le 4 ]; then
  echo "$0:  enhance data..."
#  for dset in dev eval; do
#      local/run_gss.sh \
#        --cmd "$train_cmd" --nj 100 \
#        --multiarray outer_array_mics \
#        ${dset} ${enhanced_dir}_outer_array_mics \
#        ${enhanced_dir}_outer_array_mics || exit 1
#  done

  enhanced_dir=/export/c12/aarora8/CHiME_gss/enhanced_multiarray
  for dset in dev eval; do
      local/prepare_data.sh --mictype gss --arrayid outer_array_mics \
        ${enhanced_dir}_outer_array_mics/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_outer_array_mics
      utils/fix_data_dir.sh data/${dset}_gss_outer_array_mics
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_outer_array_mics
  done
fi

enhanced_dir=enhanced_multiarray
if [ $stage -le 5 ]; then
  echo "$0:  enhance data..."
#  for dset in dev eval; do
#      local/run_gss.sh \
#        --cmd "$train_cmd" --nj 100 \
#        --multiarray True \
#        ${dset} ${enhanced_dir}_True \
#        ${enhanced_dir}_True || exit 1
#  done

  enhanced_dir=/export/c12/aarora8/CHiME_gss/s5_track1/enhanced_multiarray
  for dset in dev eval; do
      local/prepare_data.sh --mictype gss --arrayid True \
        ${enhanced_dir}_True/audio/${dset} ${json_dir}/${dset} \
        data/${dset}_gss_True
      utils/fix_data_dir.sh data/${dset}_gss_True
      utils/validate_data_dir.sh --no-feats data/${dset}_gss_True
  done
fi

if [ $stage -le 6 ]; then
  for dset in dev eval; do
    for suffix in gss_U01 gss_U02 gss_U06 gss_reference gss_first_array_mics gss_outer_array_mics; do
      utils/copy_data_dir.sh data/${dset}_${suffix} data/${dset}_${suffix}_orig
      utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_${suffix}_orig data/${dset}_${suffix}
    done
  done
fi

if [ $stage -le 7 ]; then
  for dset in dev eval; do
    for suffix in gss_U01 gss_U02 gss_U06 gss_reference gss_first_array_mics gss_outer_array_mics; do
      if [ ! -s data/${dset}_${suffix}_hires/feats.scp ]; then
        utils/copy_data_dir.sh data/${dset}_${suffix} data/${dset}_${suffix}_hires
        steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 80 --cmd "$train_cmd" data/${dset}_${suffix}_hires
        steps/compute_cmvn_stats.sh data/${dset}_${suffix}_hires
        utils/fix_data_dir.sh data/${dset}_${suffix}_hires
      fi
    done
  done
fi

chime6_corpus=${PWD}/CHiME6_new
json_dir=${chime6_corpus}/transcriptions
audio_dir=${chime6_corpus}/audio
if [ $stage -le 8 ]; then
  echo "$0:  prepare data..."
  for dataset in eval; do
    for mictype in worn; do
      local/prepare_data.sh --mictype ${mictype} \
          ${audio_dir}/${dataset} ${json_dir}/${dataset} \
          data/${dataset}_${mictype}
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_stereo
      grep "\.L-" data/${dataset}_${mictype}_stereo/text > data/${dataset}_${mictype}/text
      utils/fix_data_dir.sh data/${dataset}_${mictype}
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_orig
      utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dataset}_${mictype}_orig data/${dataset}_${mictype}
      utils/copy_data_dir.sh data/${dataset}_${mictype} data/${dataset}_${mictype}_hires
      steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --nj 80 --cmd "$train_cmd" data/${dataset}_${mictype}_hires
      steps/compute_cmvn_stats.sh data/${dataset}_${mictype}_hires
      utils/fix_data_dir.sh data/${dataset}_${mictype}_hires
    done
  done
fi
