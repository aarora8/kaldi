#!/bin/bash

# This script prepares the training and test data for MADCAT Arabic dataset 
# (i.e text, images.scp, utt2spk and spk2utt). It calls process_data.py.

#  Eg. local/prepare_data.sh
#  Eg. text file: LDC0001_000404_NHR_ARB_20070113.0052_11_LDC0001_00z2 ﻮﺠﻫ ﻮﻌﻘﻟ ﻍﺍﺮﻗ ﺢﺗّﻯ ﺎﻠﻨﺧﺎﻋ
#      utt2spk file: LDC0001_000397_NHR_ARB_20070113.0052_11_LDC0001_00z1 LDC0001
#      images.scp file: LDC0009_000000_arb-NG-2-76513-5612324_2_LDC0009_00z0
#      data/local/lines/1/arb-NG-2-76513-5612324_2_LDC0009_00z0.tif

stage=0
download_dir=/export/corpora5/handwriting_ocr/RIMES
data=data/local/rimes_data
. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;

mkdir -p data/{train,test,val}
if [ -d $data ]; then
  echo "$0: Not downloading lines images as it is already there."
else
  mkdir -p $data/{train,test}/lines
  tar -xf $download_dir/training_2011.tar -C $data/train || exit 1;
  tar -xf $download_dir/eval_2011.tar -C $data/test || exit 1;
  cp -r $download_dir/training_2011.xml $data/train/rimes_2011.xml
  cp -r $download_dir/eval_2011_annotated.xml $data/test/rimes_2011.xml
fi

if [ $stage -le 0 ]; then
  echo "$0: Processing train and test data... $(date)."
  local/process_data.py $data/train train --augment true || exit 1
  local/process_data.py $data/test  test || exit 1
  for dataset in test train; do
    echo "$0: Fixing data directory for dataset: $dataset $(date)."
    image/fix_data_dir.sh data/$dataset
  done
fi
