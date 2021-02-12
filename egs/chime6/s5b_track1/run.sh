#!/usr/bin/env bash
#
# Based mostly on the TED-LIUM and Switchboard recipe
#
# Copyright  2017  Johns Hopkins University (Author: Shinji Watanabe and Yenda Trmal)
# Apache 2.0
#

# Begin configuration section.
nj=96
decode_nj=20
stage=0
nnet_stage=-10
decode_stage=1
decode_only=false
num_data_reps=4
foreground_snrs="20:10:15:5:0"
background_snrs="20:10:15:5:0"
enhancement=gss # gss or beamformit
multiarray=True
bss_iterations=20
context_samples=240000
# End configuration section
. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh

if [ $decode_only == "true" ]; then
  stage=16
fi

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
  enhancement=${enhancement}
fi

if [[ ${enhancement} == *beamformit* ]]; then
  enhanced_dir=${enhanced_dir}
  enhancement=${enhancement}
fi

test_sets="dev_${enhancement}"
train_set=train_worn_simu_u400k

# This script also needs the phonetisaurus g2p, srilm, beamformit
./local/check_tools.sh || exit 1

###########################################################################
# We first generate the synchronized audio files across arrays and
# corresponding JSON files. Note that this requires sox v14.4.2,
# which is installed via miniconda in ./local/check_tools.sh
###########################################################################

#if [ $stage -le 0 ]; then
#  local/generate_chime6_data.sh \
#    --cmd "$train_cmd" \
#    ${chime5_corpus} \
#    ${chime6_corpus}
#fi

###########################################################################
# We prepare dict and lang in stages 1 to 3.
###########################################################################

if [ $stage -le 1 ]; then
  echo "$0:  prepare data..."
  # dev worn is needed for the LM part
  for dataset in train dev; do
    for mictype in worn; do
      local/prepare_data.sh --mictype ${mictype} \
          ${audio_dir}/${dataset} ${json_dir}/${dataset} \
          data/${dataset}_${mictype}
      utils/validate_data_dir.sh --no-feats data/${dataset}_${mictype}
    done
  done
fi

if [ $stage -le 2 ]; then
  echo "$0:  prepare data..."
  # skip u03 and u04 as they are missing
  for mictype in u01 u02 u05 u06; do
    local/prepare_data.sh --mictype ${mictype} \
        ${audio_dir}/train ${json_dir}/train data/train_${mictype}
    utils/validate_data_dir.sh --no-feats data/train_${mictype} || exit 1
  done
fi

if [ $stage -le 3 ]; then
  echo "$0:  train lm ..."
  local/prepare_dict.sh data/local/dict_nosp

  utils/prepare_lang.sh \
    data/local/dict_nosp "<unk>" data/local/lang_nosp data/lang_nosp

  local/train_lms_srilm.sh \
    --train-text data/train_worn/text --dev-text data/dev_worn/text \
    --oov-symbol "<unk>" --words-file data/lang_nosp/words.txt \
    data/ data/srilm
fi

##########################################################################################
## In stages 3 to 8, we augment and fix train data for our training purpose. point source
## noises are extracted from chime corpus. Here we use 400k utterances from array microphones,
## its augmentation and all the worn set utterances in train.
##########################################################################################

if [ $stage -le 4 ]; then
  # remove possibly bad sessions (P11_S03, P52_S19, P53_S24, P54_S24)
  # see http://spandh.dcs.shef.ac.uk/chime_challenge/data.html for more details
  utils/copy_data_dir.sh data/train_worn data/train_worn_org # back up
  grep -v -e "^P11_S03" -e "^P52_S19" -e "^P53_S24" -e "^P54_S24" data/train_worn_org/text > data/train_worn/text
  utils/fix_data_dir.sh data/train_worn
fi

#if [ $stage -le 5 ]; then
#  echo "$0:  enhance data with gss ..."
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
#fi

enhanced_dir=/export/c12/aarora8/CHiME_gss/enhanced_multiarray
if [ $stage -le 6 ]; then
  echo "$0:  enhance data with gss ..."

  # multi-array GSS with 24 microphones
  # we are not using S12 since GSS fails for some utterence for this session
  multiarray=True
#  for dset in S03 S04 S05 S06 S07 S08 S13 S16 S17 S18 S19 S20 S22 S23 S24; do
#    local/run_gss.sh \
#      --cmd "$train_cmd --max-jobs-run $gss_nj" --nj 160 \
#      --multiarray $multiarray \
#      ${dset} \
#      ${enhanced_dir}_$multiarray \
#      ${enhanced_dir}_$multiarray || exit 1
#  done
  local/prepare_data.sh --mictype gss --arrayid True ${enhanced_dir}_$multiarray/audio/train ${json_dir}/train data/train_gss_multiarray_$multiarray
  utils/fix_data_dir.sh data/train_gss_multiarray_$multiarray
  utils/validate_data_dir.sh --no-feats data/train_gss_multiarray_$multiarray || exit 1

  # multi-array GSS with 12 microphones
#  for dset in S03 S04 S05 S06 S07 S08 S13 S16 S17 S18 S19 S20 S22 S23 S24; do
#    local/run_gss.sh \
#      --cmd "$train_cmd --max-jobs-run $gss_nj" --nj 160 \
#      ${dset} \
#      ${enhanced_dir} \
#      ${enhanced_dir} || exit 1
#  done
  local/prepare_data.sh --mictype gss --arrayid default ${enhanced_dir}/audio/train ${json_dir}/train data/train_gss_multiarray
  utils/fix_data_dir.sh data/train_gss_multiarray
  utils/validate_data_dir.sh --no-feats data/train_gss_multiarray || exit 1

  # multi-array GSS with 24 microphones
  # we are not using S12 since GSS fails for some utterence for this session
#  for dset in S03 S04 S05 S06 S07 S08 S13 S16 S17 S18 S19 S20 S22 S23 S24; do
#    local/run_gss.sh \
#      --cmd "$train_cmd --max-jobs-run $gss_nj" --nj 160 \
#      --context_samples $context_samples \
#      ${dset} \
#      ${enhanced_dir}_$context_samples \
#      ${enhanced_dir}_$context_samples || exit 1
#  done
  local/prepare_data.sh --mictype gss --arrayid $context_samples ${enhanced_dir}_$context_samples/audio/train ${json_dir}/train data/train_gss_multiarray_$context_samples
  utils/fix_data_dir.sh data/train_gss_multiarray_$context_samples
  utils/validate_data_dir.sh --no-feats data/train_gss_multiarray_$context_samples

#  for dset in S03 S04 S05 S06 S07 S08 S13 S16 S17 S18 S19 S20 S22 S23 S24; do
#    local/run_gss.sh \
#      --cmd "$train_cmd --max-jobs-run $gss_nj" --nj 160 \
#      --bss_iterations $bss_iterations \
#      ${dset} \
#      ${enhanced_dir}_$bss_iterations \
#      ${enhanced_dir}_$bss_iterations || exit 1
#  done
  local/prepare_data.sh --mictype gss --arrayid $bss_iterations ${enhanced_dir}_$bss_iterations/audio/train ${json_dir}/train data/train_gss_multiarray_$bss_iterations
  utils/fix_data_dir.sh data/train_gss_multiarray_$bss_iterations
  utils/validate_data_dir.sh --no-feats data/train_gss_multiarray_$bss_iterations || exit 1
fi

if [ $stage -le 7 ]; then
  utils/combine_data.sh data/train_uall data/train_u01 data/train_u02 data/train_u05 data/train_u06
  utils/subset_data_dir.sh data/train_uall 400000 data/train_u400k

  utils/combine_data.sh data/train_gss_multiarray_all data/train_gss_multiarray data/train_gss_multiarray_True data/train_gss_multiarray_$context_samples data/train_gss_multiarray_$bss_iterations

  utils/combine_data.sh data/${train_set} data/train_worn data/train_u400k  data/train_gss_multiarray_all
fi

if [ $stage -le 8 ]; then
  # Split speakers up into 3-minute chunks.  This doesn't hurt adaptation, and
  # lets us use more jobs for decoding etc.
  for dset in ${train_set}; do
    utils/copy_data_dir.sh data/${dset} data/${dset}_nosplit
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 180 data/${dset}_nosplit data/${dset}
  done
fi

##################################################################################
# Now make 13-dim MFCC features. We use 13-dim fetures for GMM-HMM systems.
##################################################################################

if [ $stage -le 9 ]; then
  # Now make MFCC features.
  # mfccdir should be some place with a largish disk where you
  # want to store MFCC features.
  echo "$0:  make features..."
  for x in ${train_set}; do
    steps/make_mfcc.sh --nj 60 --cmd "$train_cmd" data/$x
    steps/compute_cmvn_stats.sh data/$x
    utils/fix_data_dir.sh data/$x
  done
fi

###################################################################################
# Stages 8 to 13 train monophone and triphone models. They will be used for
# generating lattices for training the chain model
###################################################################################

if [ $stage -le 10 ]; then
  # make a subset for monophone training
  utils/subset_data_dir.sh --shortest data/${train_set} 100000 data/${train_set}_100kshort
  utils/subset_data_dir.sh data/${train_set}_100kshort 30000 data/${train_set}_30kshort
fi

if [ $stage -le 11 ]; then
  # Starting basic training on MFCC features
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
		      data/${train_set}_30kshort data/lang_nosp exp/mono
fi

if [ $stage -le 12 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang_nosp exp/mono exp/mono_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
			2500 30000 data/${train_set} data/lang_nosp exp/mono_ali exp/tri1
fi

if [ $stage -le 13 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang_nosp exp/tri1 exp/tri1_ali

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
			  4000 50000 data/${train_set} data/lang_nosp exp/tri1_ali exp/tri2
fi

LM=data/srilm/best_3gram.gz
if [ $stage -le 14 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/${train_set} data/lang_nosp exp/tri2
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict_nosp exp/tri2/pron_counts_nowb.txt \
    exp/tri2/sil_counts_nowb.txt \
    exp/tri2/pron_bigram_counts_nowb.txt data/local/dict

  echo "$0:  prepare new lang with pronunciation and silence modeling..."
  utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang_tmp
  # Compiles G for chime6 trigram LM (since we use data/lang for decoding also,
  # we need to generate G.fst in data/lang)
  utils/format_lm.sh \
		data/lang_tmp $LM data/local/dict_nosp/lexicon.txt data/lang
fi

if [ $stage -le 15 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/${train_set} data/lang exp/tri2 exp/tri2_ali

  steps/train_sat.sh --cmd "$train_cmd" \
		     5000 100000 data/${train_set} data/lang exp/tri2_ali exp/tri3
fi

#######################################################################
# Perform data cleanup for training data.
#######################################################################

if [ $stage -le 16 ]; then
  # The following script cleans the data and produces cleaned data
  steps/cleanup/clean_and_segment_data.sh --nj ${nj} --cmd "$train_cmd" \
    --segmentation-opts "--min-segment-length 0.3 --min-new-segment-length 0.6" \
    data/${train_set} data/lang exp/tri3 exp/tri3_cleaned data/${train_set}_cleaned
fi

##########################################################################
# CHAIN MODEL TRAINING
# skipping decoding here and performing it in step 16
##########################################################################

if [ $stage -le 17 ]; then
  # chain TDNN
  local/chain/run_cnn_tdnn.sh --nj ${nj} \
    --stage 13 \
    --train-set ${train_set}_cleaned \
    --test-sets "$test_sets" \
    --gmm tri3_cleaned --nnet3-affix _${train_set}_cleaned_rvb
fi

##########################################################################
# DECODING is done in the local/decode.sh script. This script performs
# enhancement, fixes test sets performs feature extraction and 2 stage decoding
##########################################################################

if [ $stage -le 18 ]; then
  local/decode.sh --stage 1 \
    --enhancement $enhancement \
    --train_set "$train_set"
fi

exit 0;
