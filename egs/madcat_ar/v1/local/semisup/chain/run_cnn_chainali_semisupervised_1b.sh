#!/bin/bash

set -e -o pipefail
stage=0   # Start from -1 for supervised seed system training
train_stage=-100
nj=70
test_nj=30

# The following 3 options decide the output directory for semi-supervised 
# chain system
# dir=${exp_root}/chain${chain_affix}/tdnn${tdnn_affix}
exp_root=exp/semisup_100k
chain_affix=    # affix for chain dir
tdnn_affix=_semisup  # affix for semi-supervised chain system

# Datasets-Expects supervised_set and unsupervised_set
supervised_set=train
unsupervised_set=train_unsup

# Input seed system
sup_chain_dir=exp/chain/cnn_e2eali_1b  # supervised chain system
sup_lat_dir=exp/chain/e2e_train_lats  # Seed model options
sup_tree_dir=exp/chain/tree_e2e  # tree directory for supervised chain system

# Semi-supervised options
supervision_weights=1.0,1.0   # Weights for supervised, unsupervised data egs.
                              # Can be used to scale down the effect of unsupervised data
                              # by using a smaller scale for it e.g. 1.0,0.3
lm_weights=3,2  # Weights on phone counts from supervised, unsupervised data for denominator FST creation

sup_egs_dir=   # Supply this to skip supervised egs creation
unsup_egs_dir=  # Supply this to skip unsupervised egs creation
unsup_egs_opts=  # Extra options to pass to unsupervised egs creation
# Neural network opts
xent_regularize=0.1
tdnn_dim=550
# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh
lang_decode=data/lang_test
dropout_schedule='0,0@0.20,0.2@0.50,0'
dir=$exp_root/chain$chain_affix/tdnn$tdnn_affix
if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

graphdir=$sup_chain_dir/graph_unsup
for f in data/$supervised_set/feats.scp \
  data/$unsupervised_set/feats.scp \
  $sup_lat_dir/lat.1.gz $sup_tree_dir/ali.1.gz \
  $lang_decode/G.fst; do
  if [ ! -f $f ]; then
    echo "$0: Could not find file $f"
    exit 1
  fi
done

if [ ! -f $graphdir/HCLG.fst ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 $lang_decode $sup_chain_dir $graphdir
fi

# Decode unsupervised data and write lattices in non-compact
if [ $stage -le 5 ]; then
  steps/nnet3/decode_semisup.sh --num-threads 4 --nj 45 --cmd "$cmd" --beam 15 \
            --frames-per-chunk 340 \
            --acwt 1.0 --post-decode-acwt 10.0 --write-compact false \
            --scoring-opts "--min-lmwt 10 --max-lmwt 10" --word-determinize false \
            $graphdir data/$unsupervised_set $sup_chain_dir/decode_$unsupervised_set
fi

# Get best path alignment and lattice posterior of best path alignment to be
if [ $stage -le 8 ]; then
  steps/best_path_weights.sh --cmd "${cmd}" --acwt 0.1 \
    data/$unsupervised_set \
    $sup_chain_dir/decode_$unsupervised_set \
    $sup_chain_dir/best_path_$unsupervised_set
fi

frame_subsampling_factor=4
if [ -f $sup_chain_dir/frame_subsampling_factor ]; then
  frame_subsampling_factor=$(cat $sup_chain_dir/frame_subsampling_factor)
fi
cmvn_opts=$(cat $sup_chain_dir/cmvn_opts) || exit 1

diff $sup_tree_dir/tree $sup_chain_dir/tree || { echo "$0: $sup_tree_dir/tree and $sup_chain_dir/tree differ"; exit 1; }

# Train denominator FST using phone alignments from
# supervised and unsupervised data
if [ $stage -le 10 ]; then
  steps/nnet3/chain/make_weighted_den_fst.sh --num-repeats $lm_weights --cmd "$cmd" \
    --lm_opts '--ngram-order=2 --no-prune-ngram-order=1 --num-extra-lm-states=1000' \
    $sup_tree_dir $sup_chain_dir/best_path_$unsupervised_set \
    $dir
fi

if [ $stage -le 11 ]; then
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $sup_tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)
  common1="required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=36"
  common2="required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=70"
  common3="required-time-offsets= height-offsets=-1,0,1 num-filters-out=70"
  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=40 name=input
  conv-relu-batchnorm-dropout-layer name=cnn1 height-in=40 height-out=40 time-offsets=-3,-2,-1,0,1,2,3 $common1 dropout-proportion=0.0
  conv-relu-batchnorm-dropout-layer name=cnn2 height-in=40 height-out=20 time-offsets=-2,-1,0,1,2 $common1 height-subsample-out=2 dropout-proportion=0.0
  conv-relu-batchnorm-dropout-layer name=cnn3 height-in=20 height-out=20 time-offsets=-4,-2,0,2,4 $common2
  conv-relu-batchnorm-dropout-layer name=cnn4 height-in=20 height-out=20 time-offsets=-4,-2,0,2,4 $common2
  conv-relu-batchnorm-dropout-layer name=cnn5 height-in=20 height-out=10 time-offsets=-4,-2,0,2,4 $common2 height-subsample-out=2
  conv-relu-batchnorm-dropout-layer name=cnn6 height-in=10 height-out=10 time-offsets=-4,0,4 $common3
  conv-relu-batchnorm-dropout-layer name=cnn7 height-in=10 height-out=10 time-offsets=-4,0,4 $common3
  relu-batchnorm-dropout-layer name=tdnn1 input=Append(-4,-2,0,2,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-dropout-layer name=tdnn2 input=Append(-4,0,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-dropout-layer name=tdnn3 input=Append(-4,0,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-layer name=prefinal-chain dim=$tdnn_dim target-rms=0.5
  output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5
  relu-batchnorm-layer name=prefinal-xent input=tdnn3 dim=$tdnn_dim target-rms=0.5
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5

  # We use separate outputs for supervised and unsupervised data
  # so we can properly track the train and valid objectives.
  output name=output-0 input=output.affine
  output name=output-1 input=output.affine
  output name=output-0-xent input=output-xent.log-softmax
  output name=output-1-xent input=output-xent.log-softmax
EOF

  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

# Get values for $model_left_context, $model_right_context
. $dir/configs/vars

left_context=$model_left_context
right_context=$model_right_context

egs_left_context=$(perl -e "print int($left_context + $frame_subsampling_factor / 2)")
egs_right_context=$(perl -e "print int($right_context + $frame_subsampling_factor / 2)")

if [ -z "$sup_egs_dir" ]; then
  sup_egs_dir=$dir/egs_$supervised_set
  frames_per_eg=$(cat $sup_chain_dir/egs/info/frames_per_eg)

  if [ $stage -le 12 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $sup_egs_dir/storage ]; then
      utils/create_split_dir.pl \
       /export/b0{5,6,7,8}/$USER/kaldi-data/egs/fisher_english-$(date +'%m_%d_%H_%M')/s5c/$sup_egs_dir/storage $sup_egs_dir/storage
    fi
    mkdir -p $sup_egs_dir/
    touch $sup_egs_dir/.nodelete # keep egs around when that run dies.

    echo "$0: generating egs from the supervised data"
    steps/nnet3/chain/get_egs.sh --cmd "$cmd" \
               --left-tolerance 1 --right-tolerance 1 \
               --left-context $egs_left_context --right-context $egs_right_context \
               --frame-subsampling-factor $frame_subsampling_factor \
               --alignment-subsampling-factor 1 \
               --frames-overlap-per-eg 0 \
               --frames-per-eg $frames_per_eg \
               --frames-per-iter 2000000 \
               --cmvn-opts "$cmvn_opts" \
               --generate-egs-scp true \
               data/${supervised_set} $dir \
               $sup_lat_dir $sup_egs_dir
  fi
else
  frames_per_eg=$(cat $sup_egs_dir/info/frames_per_eg)
fi

unsup_frames_per_eg=340,300,200,100  # Using a frames-per-eg of 150 for unsupervised data
                         # was found to be better than allowing smaller chunks
                         # (160,140,110,80) like for supervised system
lattice_lm_scale=0.5  # lm-scale for using the weights from unsupervised lattices when
                      # creating numerator supervision
lattice_prune_beam=4.0  # beam for pruning the lattices prior to getting egs
                        # for unsupervised data
tolerance=1   # frame-tolerance for chain training

unsup_lat_dir=$sup_chain_dir/decode_$unsupervised_set
if [ -z "$unsup_egs_dir" ]; then
  unsup_egs_dir=$dir/egs_$unsupervised_set

  if [ $stage -le 13 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $unsup_egs_dir/storage ]; then
      utils/create_split_dir.pl \
       /export/b0{5,6,7,8}/$USER/kaldi-data/egs/fisher_english-$(date +'%m_%d_%H_%M')/s5c/$unsup_egs_dir/storage $unsup_egs_dir/storage
    fi
    mkdir -p $unsup_egs_dir
    touch $unsup_egs_dir/.nodelete # keep egs around when that run dies.

    echo "$0: generating egs from the unsupervised data"
    steps/nnet3/chain/get_egs.sh \
      --cmd "$cmd" --alignment-subsampling-factor 1 \
      --left-tolerance $tolerance --right-tolerance $tolerance \
      --left-context $egs_left_context --right-context $egs_right_context \
      --frames-per-eg $unsup_frames_per_eg --frames-per-iter 2000000 \
      --frame-subsampling-factor $frame_subsampling_factor \
      --cmvn-opts "$cmvn_opts" --lattice-lm-scale $lattice_lm_scale \
      --lattice-prune-beam "$lattice_prune_beam" \
      --deriv-weights-scp $sup_chain_dir/best_path_$unsupervised_set/weights.scp \
      --generate-egs-scp true $unsup_egs_opts \
      data/$unsupervised_set $dir \
      $unsup_lat_dir $unsup_egs_dir
  fi
fi

comb_egs_dir=$dir/comb_egs
if [ $stage -le 14 ]; then
  steps/nnet3/chain/multilingual/combine_egs.sh --cmd "$cmd" \
    --block-size 64 \
    --lang2weight $supervision_weights 2 \
    $sup_egs_dir $unsup_egs_dir $comb_egs_dir
  touch $comb_egs_dir/.nodelete # keep egs around when that run dies.
fi

if [ $train_stage -le -4 ]; then
  # This is to skip stages of den-fst creation, which was already done.
  train_stage=-4
fi

chunk_width=340,300,200,100
if [ $stage -le 15 ]; then
  steps/nnet3/chain/train.py --stage $train_stage \
    --egs.dir "$comb_egs_dir" \
    --egs.chunk-width=$chunk_width \
    --cmd "$cmd" \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00001 \
    --chain.apply-deriv-weights=true \
    --chain.frame-subsampling-factor=$frame_subsampling_factor \
    --chain.alignment-subsampling-factor=1 \
    --chain.left-tolerance 1 \
    --chain.right-tolerance 1 \
    --chain.lm-opts="--ngram-order=2 --no-prune-ngram-order=1 --num-extra-lm-states=900" \
    --trainer.srand=0 \
    --trainer.optimization.shrink-value=1.0 \
    --trainer.num-chunk-per-minibatch=32,16 \
    --trainer.optimization.momentum=0.0 \
    --trainer.frames-per-iter=2000000 \
    --trainer.max-param-change=2.0 \
    --trainer.num-epochs 2 \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.optimization.num-jobs-initial 6 \
    --trainer.optimization.num-jobs-final 8 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --egs.opts="--frames-overlap-per-eg 0 --constrained true" \
    --cleanup.remove-egs false \
    --feat-dir data/$supervised_set \
    --tree-dir $sup_tree_dir \
    --lat-dir $sup_lat_dir \
    --dir $dir || exit 1;

fi

if [ $stage -le 17 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 $lang_decode $dir $dir/graph
fi

if [ $stage -le 18 ]; then
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --frames-per-chunk 340 --nj 45 --cmd "$cmd" \
      $dir/graph data/test_5k $dir/decode_test.5k
fi
exit 0;

