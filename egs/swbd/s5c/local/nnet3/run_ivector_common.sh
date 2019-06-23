#!/bin/bash

. ./cmd.sh
set -e
stage=1
train_stage=-10
generate_alignments=true
speed_perturb=true

. ./path.sh
. ./utils/parse_options.sh

mkdir -p exp/nnet3
train_set=train_nodup

if [ -e data/rt03 ]; then maybe_rt03=rt03; else maybe_rt03= ; fi

if $speed_perturb; then
  if [ $stage -le 1 ]; then
    # Although the nnet will be trained by high resolution data, we still have
    # to perturb the normal data to get the alignments _sp stands for
    # speed-perturbed
    echo "$0: preparing directory for speed-perturbed data"
    utils/data/perturb_data_dir_speed_3way.sh --always-include-prefix true \
           data/${train_set} data/${train_set}_sp

    echo "$0: creating MFCC features for low-resolution speed-perturbed data"
    mfccdir=mfcc_perturbed
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 50 \
                       data/${train_set}_sp exp/make_mfcc/${train_set}_sp $mfccdir
    steps/compute_cmvn_stats.sh data/${train_set}_sp exp/make_mfcc/${train_set}_sp $mfccdir
    utils/fix_data_dir.sh data/${train_set}_sp
  fi

  if [ $stage -le 2 ] && $generate_alignments; then
    # obtain the alignment of the perturbed data
    steps/align_fmllr.sh --nj 100 --cmd "$train_cmd" \
      data/${train_set}_sp data/lang exp/tri4 exp/tri4_ali_nodup_sp
  fi
  train_set=${train_set}_sp
fi

if [ $stage -le 3 ]; then
  mfccdir=mfcc_hires
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $mfccdir/storage ]; then
    date=$(date +'%m_%d_%H_%M')
    utils/create_split_dir.pl /export/b{11,12,13,14}/$USER/kaldi-data/mfcc/swbd-$date/s5b/$mfccdir/storage $mfccdir/storage
  fi

  # the 100k_nodup directory is copied seperately, as
  # we want to use exp/tri2_ali_100k_nodup for lda_mllt training
  # the main train directory might be speed_perturbed
  for dataset in $train_set train_100k_nodup; do
    utils/copy_data_dir.sh data/$dataset data/${dataset}_hires

    utils/data/perturb_data_dir_volume.sh data/${dataset}_hires

    steps/make_mfcc.sh --nj 70 --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" data/${dataset}_hires exp/make_hires/$dataset $mfccdir;
    steps/compute_cmvn_stats.sh data/${dataset}_hires exp/make_hires/${dataset} $mfccdir;

    # Remove the small number of utterances that couldn't be extracted for some
    # reason (e.g. too short; no such file).
    utils/fix_data_dir.sh data/${dataset}_hires;
  done

  for dataset in eval2000 train_dev $maybe_rt03; do
    # Create MFCCs for the eval set
    utils/copy_data_dir.sh data/$dataset data/${dataset}_hires
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 10 --mfcc-config conf/mfcc_hires.conf \
        data/${dataset}_hires exp/make_hires/$dataset $mfccdir;
    steps/compute_cmvn_stats.sh data/${dataset}_hires exp/make_hires/$dataset $mfccdir;
    utils/fix_data_dir.sh data/${dataset}_hires  # remove segments with problems
  done

  # Take the first 30k utterances (about 1/8th of the data) this will be used
  # for the diagubm training
  utils/subset_data_dir.sh --first data/${train_set}_hires 30000 data/${train_set}_30k_hires
  utils/data/remove_dup_utts.sh 200 data/${train_set}_30k_hires data/${train_set}_30k_nodup_hires  # 33hr
fi

exit 0;
