#!/bin/bash
set -e -o pipefail
stage=0
nj=70
train_set=train
train_stage=-10
chunk_width=340,300,200,100
num_leaves=500
tdnn_dim=450
lang_decode=data/lang_test
lang_rescore=data/lang_rescore_6g
dropout_schedule='0,0@0.20,0.2@0.50,0'
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

affix=_1a_oracle_${train_set}
chain_model_dir=exp/chain/cnn_chainali_1a_train_sup
#ali_dir=exp/chain/chainali_$train_set
lat_dir=exp/chain/chainali_${train_set}_lats
dir=exp/chain/cnn_chainali${affix}
train_data_dir=data/${train_set}
#use chainali tree
tree_dir=exp/chain/tree_chainali_${train_set}
tree_dir=exp/chain/tree_chainali_train_sup
# the 'lang' directory is created by this script.
# If you create such a directory with a non-standard topology
# you should probably name it differently.
lang=data/lang_chain
xent_regularize=0.1
lm_weights=3,2  # Weights on phone counts from supervised, unsupervised data for denominator FST creation
for f in $train_data_dir/feats.scp; do
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
                            ${train_data_dir} data/lang $chain_model_dir $lat_dir
  cp exp/chain/chainali_train_sup_lats/splice_opts $lat_dir/splice_opts
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

# Get best path alignment and lattice posterior of best path alignment to be
if [ $stage -le 4 ]; then
  steps/best_path_weights.sh --cmd "${cmd}" --acwt 0.1 \
    data/train_unsup_unique \
    $lat_dir \
    $chain_model_dir/best_path_train_unsup_unique
fi

# Train denominator FST using phone alignments from
# supervised and unsupervised data
if [ $stage -le 5 ]; then
  steps/nnet3/chain/make_weighted_den_fst.sh --num-repeats $lm_weights --cmd "$cmd" \
    --lm_opts '--ngram-order=2 --no-prune-ngram-order=1 --num-extra-lm-states=1000' \
    $tree_dir $chain_model_dir/best_path_train_unsup_unique \
    $dir
fi

if [ $stage -le 6 ]; then
  echo "$0: creating neural net configs using the xconfig parser";
  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
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
EOF

  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs
fi

if [ $train_stage -le -4 ]; then
  # This is to skip stages of den-fst creation, which was already done.
  train_stage=-4
fi

if [ $stage -le 7 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/iam-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi
  steps/nnet3/chain/train.py --stage=$train_stage \
    --cmd "$cmd" \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights true \
    --egs.dir "$common_egs_dir" \
    --chain.xent-regularize $xent_regularize \
    --chain.frame-subsampling-factor 4 \
    --chain.alignment-subsampling-factor 1 \
    --trainer.num-chunk-per-minibatch 32,16 \
    --trainer.frames-per-iter 1500000 \
    --trainer.num-epochs 4 \
    --trainer.optimization.momentum 0 \
    --trainer.optimization.num-jobs-initial 5 \
    --trainer.optimization.num-jobs-final 8 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.optimization.shrink-value 1.0 \
    --trainer.max-param-change 2.0 \
    --trainer.dropout-schedule $dropout_schedule \
    --cleanup.remove-egs false \
    --feat-dir data/${train_set} \
    --tree-dir $tree_dir \
    --lat-dir=$lat_dir \
    --chain.left-tolerance 1 \
    --chain.right-tolerance 1 \
    --egs.chunk-width=$chunk_width \
    --egs.opts="--frames-overlap-per-eg 0 --constrained false" \
    --dir $dir  || exit 1;
fi

if [ $stage -le 8 ]; then
  # The reason we are using data/lang here, instead of $lang, is just to
  # emphasize that it's not actually important to give mkgraph.sh the
  # lang directory with the matched topology (since it gets the
  # topology file from the model).  So you could give it a different
  # lang directory, one that contained a wordlist and LM of your choice,
  # as long as phones.txt was compatible.
  utils/mkgraph.sh \
    --self-loop-scale 1.0 $lang_decode \
    $dir $dir/graph || exit 1;
fi

if [ $stage -le 9 ]; then
  frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
  for decode_set in test.5k; do
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --nj $nj --cmd "$cmd" \
      $dir/graph data/$decode_set $dir/decode_$decode_set || exit 1;
  done
  steps/lmrescore_const_arpa.sh --cmd "$cmd" $lang_decode $lang_rescore \
                                data/$decode_set $dir/decode_${decode_set}{,_rescored} || exit 1
fi

echo "Done. Date: $(date). Results:"
local/chain/compare_wer.sh $dir
