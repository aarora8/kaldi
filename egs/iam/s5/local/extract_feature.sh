#!/bin/bash

nj=4
cmd=run.pl
compress=true

echo "$0 $@"

. utils/parse_options.sh || exit 1;

data=$1
height=$2
featdir=$data/data
logdir=$data/log
mkdir -p $logdir

# make $featdir an absolute pathname
featdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $featdir ${PWD}`

if [ -f $data/feats.scp ]; then
    mkdir -p $data/.backup
    echo "$0: moving $data/feats.scp to $data/.backup"
    mv $data/feats.scp $data/.backup
fi

scp=$data/images.scp
split_scps=""
for n in $(seq $nj); do
    split_scps="$split_scps $logdir/images.$n.scp"
done

utils/split_scp.pl $scp $split_scps || exit 1;


# add ,p to the input rspecifier so that we can just skip over
# utterances that have bad wave data.

$cmd JOB=1:$nj $logdir/extract_feature.JOB.log \
  local/make_feature_vect_deslant.py $logdir --job JOB --scale-size $height \| \
    copy-feats --compress=$compress --compression-method=7 ark:- \
    ark,scp:$featdir/images.JOB.ark,$featdir/images.JOB.scp \
    || exit 1;

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $featdir/images.$n.scp || exit 1;
done > $data/feats.scp || exit 1

nf=`cat $data/feats.scp | wc -l`
nu=`cat $data/utt2spk | wc -l`
if [ $nf -ne $nu ]; then
    echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
    echo "consider using utils/fix_data_dir.sh $data"
fi
