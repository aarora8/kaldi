#!/bin/bash

stage=0
train_discriminative=false  # by default, don't do the GMM-based discriminative
                            # training.

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh


# This setup was modified from egs/swbd/s5b, with the following changes:
# 1. added more training data for early stages
# 2. removed SAT system (and later stages) on the 100k utterance training data
# 3. reduced number of LM rescoring, only sw1_tg and sw1_fsh_fg remain
# 4. mapped swbd transcription to fisher style, instead of the other way around

set -e # exit on error
has_fisher=true

if [ $stage -le 0 ]; then
  local/swbd1_data_download.sh /export/corpora3/LDC/LDC97S62
  # local/swbd1_data_download.sh /mnt/matylda2/data/SWITCHBOARD_1R2 # BUT,
fi

if [ $stage -le 1 ]; then
  # prepare SWBD dictionary first since we want to find acronyms according to pronunciations
  # before mapping lexicon and transcripts
  local/swbd1_prepare_dict.sh
fi

if [ $stage -le 2 ]; then
  # Prepare Switchboard data. This command can also take a second optional argument
  # which specifies the directory to Switchboard documentations. Specifically, if
  # this argument is given, the script will look for the conv.tab file and correct
  # speaker IDs to the actual speaker personal identification numbers released in
  # the documentations. The documentations can be found here:
  # https://catalog.ldc.upenn.edu/docs/LDC97S62/
  # Note: if you are using this link, make sure you rename conv_tab.csv to conv.tab
  # after downloading.
  # Usage: local/swbd1_data_prep.sh /path/to/SWBD [/path/to/SWBD_docs]
  local/swbd1_data_prep.sh /export/corpora3/LDC/LDC97S62
  # local/swbd1_data_prep.sh /home/dpovey/data/LDC97S62
  # local/swbd1_data_prep.sh /data/corpora0/LDC97S62
  # local/swbd1_data_prep.sh /mnt/matylda2/data/SWITCHBOARD_1R2 # BUT,
  # local/swbd1_data_prep.sh /exports/work/inf_hcrc_cstr_general/corpora/switchboard/switchboard1

  utils/prepare_lang.sh data/local/dict_nosp \
                        "<unk>"  data/local/lang_nosp data/lang_nosp
fi

if [ $stage -le 3 ]; then
  # Now train the language models. We are using SRILM and interpolating with an
  # LM trained on the Fisher transcripts (part 2 disk is currently missing; so
  # only part 1 transcripts ~700hr are used)

  # If you have the Fisher data, you can set this "fisher_dir" variable.
  fisher_dirs="/export/corpora3/LDC/LDC2004T19/fe_03_p1_tran/ /export/corpora3/LDC/LDC2005T19/fe_03_p2_tran/"
  # fisher_dirs="/exports/work/inf_hcrc_cstr_general/corpora/fisher/transcripts" # Edinburgh,
  # fisher_dirs="/mnt/matylda2/data/FISHER/fe_03_p1_tran /mnt/matylda2/data/FISHER/fe_03_p2_tran" # BUT,
  local/swbd1_train_lms.sh data/local/train/text \
                           data/local/dict_nosp/lexicon.txt data/local/lm $fisher_dirs
fi

if [ $stage -le 4 ]; then
  # Compiles G for swbd trigram LM
  LM=data/local/lm/sw1.o3g.kn.gz
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
                         data/lang_nosp $LM data/local/dict_nosp/lexicon.txt data/lang_nosp_sw1_tg

  # Compiles const G for swbd+fisher 4gram LM, if it exists.
  LM=data/local/lm/sw1_fsh.o4g.kn.gz
  [ -f $LM ] || has_fisher=false
  if $has_fisher; then
    utils/build_const_arpa_lm.sh $LM data/lang_nosp data/lang_nosp_sw1_fsh_fg
  fi
fi


if [ $stage -le 5 ]; then
  # Data preparation and formatting for eval2000 (note: the "text" file
  # is not very much preprocessed; for actual WER reporting we'll use
  # sclite.

  # local/eval2000_data_prep.sh /data/corpora0/LDC2002S09/hub5e_00 /data/corpora0/LDC2002T43
  # local/eval2000_data_prep.sh /mnt/matylda2/data/HUB5_2000/ /mnt/matylda2/data/HUB5_2000/2000_hub5_eng_eval_tr
  # local/eval2000_data_prep.sh /exports/work/inf_hcrc_cstr_general/corpora/switchboard/hub5/2000 /exports/work/inf_hcrc_cstr_general/corpora/switchboard/hub5/2000/transcr
  local/eval2000_data_prep.sh /export/corpora2/LDC/LDC2002S09/hub5e_00 /export/corpora2/LDC/LDC2002T43
fi

if [ $stage -le 6 ]; then
  # prepare the rt03 data.  Note: this isn't 100% necessary for this
  # recipe, not all parts actually test using rt03.
  local/rt03_data_prep.sh /export/corpora/LDC/LDC2007S10
fi


if [ $stage -le 7 ]; then
  # Now make MFCC features.
  # mfccdir should be some place with a largish disk where you
  # want to store MFCC features.
  if [ -e data/rt03 ]; then maybe_rt03=rt03; else maybe_rt03= ; fi
  mfccdir=mfcc
  for x in train eval2000 $maybe_rt03; do
    steps/make_mfcc.sh --nj 20 --cmd "$train_cmd" \
                       data/$x exp/make_mfcc/$x $mfccdir
    steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
    utils/fix_data_dir.sh data/$x
  done
fi

if [ $stage -le 8 ]; then
  # Use the first 4k sentences as dev set.  Note: when we trained the LM, we used
  # the 1st 10k sentences as dev set, so the 1st 4k won't have been used in the
  # LM training data.   However, they will be in the lexicon, plus speakers
  # may overlap, so it's still not quite equivalent to a test set.
  utils/subset_data_dir.sh --first data/train 4000 data/train_dev # 5hr 6min
  n=$[`cat data/train/segments | wc -l` - 4000]
  utils/subset_data_dir.sh --last data/train $n data/train_nodev

  # Now-- there are 260k utterances (313hr 23min), and we want to start the
  # monophone training on relatively short utterances (easier to align), but not
  # only the shortest ones (mostly uh-huh).  So take the 100k shortest ones, and
  # then take 30k random utterances from those (about 12hr)
  utils/subset_data_dir.sh --shortest data/train_nodev 100000 data/train_100kshort
  utils/subset_data_dir.sh data/train_100kshort 30000 data/train_30kshort

  # Take the first 100k utterances (just under half the data); we'll use
  # this for later stages of training.
  utils/subset_data_dir.sh --first data/train_nodev 100000 data/train_100k
  utils/data/remove_dup_utts.sh 200 data/train_100k data/train_100k_nodup  # 110hr

  # Finally, the full training set:
  utils/data/remove_dup_utts.sh 300 data/train_nodev data/train_nodup  # 286hr
fi

if [ $stage -le 9 ]; then
  ## Starting basic training on MFCC features
  steps/train_mono.sh --nj 20 --cmd "$train_cmd" \
                      data/train_30kshort data/lang_nosp exp/mono
fi

if [ $stage -le 10 ]; then
  steps/align_si.sh --nj 20 --cmd "$train_cmd" \
                    data/train_100k_nodup data/lang_nosp exp/mono exp/mono_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
                        3200 30000 data/train_100k_nodup data/lang_nosp exp/mono_ali exp/tri1

fi


if [ $stage -le 11 ]; then
  steps/align_si.sh --nj 20 --cmd "$train_cmd" \
                    data/train_100k_nodup data/lang_nosp exp/tri1 exp/tri1_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
                        4000 70000 data/train_100k_nodup data/lang_nosp exp/tri1_ali exp/tri2
fi

if [ $stage -le 12 ]; then
  # The 100k_nodup data is used in the nnet2 recipe.
  steps/align_si.sh --nj 20 --cmd "$train_cmd" \
                    data/train_100k_nodup data/lang_nosp exp/tri2 exp/tri2_ali_100k_nodup

  # From now, we start using all of the data (except some duplicates of common
  # utterances, which don't really contribute much).
  steps/align_si.sh --nj 20 --cmd "$train_cmd" \
                    data/train_nodup data/lang_nosp exp/tri2 exp/tri2_ali_nodup

  # Do another iteration of LDA+MLLT training, on all the data.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          6000 140000 data/train_nodup data/lang_nosp exp/tri2_ali_nodup exp/tri3
fi


if [ $stage -le 13 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" data/train_nodup data/lang_nosp exp/tri3
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
                                  data/local/dict_nosp exp/tri3/pron_counts_nowb.txt exp/tri3/sil_counts_nowb.txt \
                                  exp/tri3/pron_bigram_counts_nowb.txt data/local/dict

  utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang
  LM=data/local/lm/sw1.o3g.kn.gz
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
                         data/lang $LM data/local/dict/lexicon.txt data/lang_sw1_tg
  LM=data/local/lm/sw1_fsh.o4g.kn.gz
  if $has_fisher; then
    utils/build_const_arpa_lm.sh $LM data/lang data/lang_sw1_fsh_fg
  fi
fi

if [ $stage -le 14 ]; then
  # Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
  steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
                       data/train_nodup data/lang exp/tri3 exp/tri3_ali_nodup


  steps/train_sat.sh  --cmd "$train_cmd" \
                      11500 200000 data/train_nodup data/lang exp/tri3_ali_nodup exp/tri4
fi
