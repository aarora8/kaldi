#!/bin/bash

set -e -o pipefail

stage=0
nj=30
train_set=train
nnet3_affix=    # affix for exp dirs, e.g. it was _cleaned in tedlium.
affix=_1d.cnn8.100  #affix for TDNN+LSTM directory e.g. "1a" or "1b", in case we change the configuration.
chain_model_dir=exp/chain${nnet3_affix}/cnn_e2eali_1b
common_egs_dir=
reporting_email=

# chain options
train_stage=-10
xent_regularize=0.1
# training chunk-options
chunk_width=340,300,200,100
num_leaves=500
tdnn_dim=450
lang_decode=lang_test

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

ali_dir=exp/chain/e2e_ali_train.semisup50k
lat_dir=exp/chain${nnet3_affix}/e2e_${train_set}_lats_chain
dir=exp/chain${nnet3_affix}/cnn_chainali${affix}
train_data_dir=data/${train_set}
tree_dir=exp/chain${nnet3_affix}/tree_e2e
dropout_schedule='0,0@0.20,0.2@0.50,0'
# the 'lang' directory is created by this script.
# If you create such a directory with a non-standard topology
# you should probably name it differently.
lang=data/lang_chain2
for f in $train_data_dir/feats.scp \
    $ali_dir/ali.1.gz $ali_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 1 ]; then
  echo "$0: creating lang directory $lang with chain-type topology"
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  if [ -d $lang ]; then
    if [ $lang/L.fst -nt data/lang/L.fst ]; then
      echo "$0: $lang already exists, not overwriting it; continuing"
    else
      echo "$0: $lang already exists and seems to be older than data/lang..."
      echo " ... not sure what to do.  Exiting."
      exit 1;
    fi
  else
    cp -r data/lang $lang
    silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
    nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
    # Use our special topology... note that later on may have to tune this
    # topology.
    steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
  fi
fi

if [ $stage -le 2 ]; then
  # Get the alignments as lattices (gives the chain training more freedom).
  # use the same num-jobs as the alignments
  steps/nnet3/align_lats.sh --nj $nj --cmd "$cmd" \
                            --acoustic-scale 1.0 \
                            --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0' \
                            $train_data_dir data/lang $chain_model_dir $lat_dir
  echo "" >$lat_dir/splice_opts
fi

#if [ $stage -le 3 ]; then
#  # Build a tree using our new topology.  We know we have alignments for the
#  # speed-perturbed data (local/nnet3/run_ivector_common.sh made them), so use
#  # those.  The num-leaves is always somewhat less than the num-leaves from
#  # the GMM baseline.
#   if [ -f $tree_dir/final.mdl ]; then
#     echo "$0: $tree_dir/final.mdl already exists, refusing to overwrite it."
#     exit 1;
#  fi
#  steps/nnet3/chain/build_tree.sh \
#    --frame-subsampling-factor 4 \
#    --alignment-subsampling-factor 1 \
#    --context-opts "--context-width=2 --central-position=1" \
#    --cmd "$cmd" $num_leaves $train_data_dir \
#    $lang $ali_dir $tree_dir
#fi

if [ $stage -le 4 ]; then
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)
  common1="required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=36"
  common2="required-time-offsets= height-offsets=-2,-1,0,1,2 num-filters-out=70"
  common3="required-time-offsets= height-offsets=-1,0,1 num-filters-out=100"
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
  conv-relu-batchnorm-dropout-layer name=cnn8 height-in=10 height-out=10 time-offsets=-4,0,4 $common3
  relu-batchnorm-dropout-layer name=tdnn1 input=Append(-4,-2,0,2,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-dropout-layer name=tdnn2 input=Append(-4,0,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-dropout-layer name=tdnn3 input=Append(-4,0,4) dim=$tdnn_dim dropout-proportion=0.0
  relu-batchnorm-layer name=prefinal-chain dim=$tdnn_dim target-rms=0.5 $tdnn_opts
  output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5 $output_opts
  relu-batchnorm-layer name=prefinal-xent input=tdnn3 dim=$tdnn_dim target-rms=0.5 $tdnn_opts
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5 $output_opts
EOF

  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

chunk_width=340,300,200,100
if [ $stage -le 5 ]; then
  steps/nnet3/chain/train.py --stage $train_stage \
    --egs.dir "$comb_egs_dir" \
    --egs.chunk-width=$chunk_width \
    --cmd "$cmd" \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00001 \
    --chain.apply-deriv-weights=true \
    --chain.frame-subsampling-factor=4 \
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
    --feat-dir $train_data_dir \
    --tree-dir $tree_dir \
    --lat-dir $lat_dir \
    --dir $dir || exit 1;

fi

if [ $stage -le 6 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 data/$lang_decode $dir $dir/graph
fi

if [ $stage -le 7 ]; then
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --frames-per-chunk 340 --nj 45 --cmd "$cmd" \
      $dir/graph data/test_5k $dir/decode_test.5k
fi
exit 0;
