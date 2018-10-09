#!/usr/bin/env python3

""" This script reads xml file and creates the following files :text, utt2spk, images.scp.
    It also creates line images from page image and stores it into
    data/local/rimes_data/train/lines.
  Eg. local/process_data.py data/local/rimes_data/train train
  Eg. text file: writer000000_train2011-0_000001 Je vous adresse ce courrier afin
      utt2spk file: writer000000_train2011-0_000001 writer000000
      images.scp file: writer000000_train2011-0_000001 \
      data/local/rimes_data/train/lines/train2011-0_000001.png
"""

import argparse
import xml.dom.minidom as minidom
from PIL import Image
import os
parser = argparse.ArgumentParser(description="""Creates line images from page image.""")
parser.add_argument('database_path', type=str,
                    help='Path to the downloaded (and extracted) mdacat data')
parser.add_argument('dataset', type=str,
                    help='Subset of data to process.')
args = parser.parse_args()

def dilate_polygon(points, amount_increase):
    """ Increases size of polygon given as a list of tuples.
        Assumes points in polygon are given in CCW
    """
    expanded_points = []
    for index, point in enumerate(points):
        prev_point = points[(index - 1) % len(points)]
        next_point = points[(index + 1) % len(points)]
        prev_edge = np.subtract(point, prev_point)
        next_edge = np.subtract(next_point, point)

        prev_normal = ((1 * prev_edge[1]), (-1 * prev_edge[0]))
        prev_normal = np.divide(prev_normal, np.linalg.norm(prev_normal))
        next_normal = ((1 * next_edge[1]), (-1 * next_edge[0]))
        next_normal = np.divide(next_normal, np.linalg.norm(next_normal))

        bisect = np.add(prev_normal, next_normal)
        bisect = np.divide(bisect, np.linalg.norm(bisect))

        cos_theta = np.dot(next_normal, bisect)
        hyp = amount_increase / cos_theta

        new_point = np.around(point + hyp * bisect)
        new_point = new_point.astype(int)
        new_point = new_point.tolist()
        new_point = tuple(new_point)
        expanded_points.append(new_point)
    return expanded_points

def get_line_images_from_page_image(file_name, left, right, top, bottom, line_id):
    image_path = os.path.join(data_path, file_name)
    im = Image.open(image_path)
    box = (left, top, right, bottom)
    region = im.crop(box)
    base_name = os.path.splitext(os.path.basename(file_name))[0]
    line_image_file_name = base_name + '_' +  str(line_id).zfill(6) + '.png'
    imgray = region.convert('L')
    image_path = os.path.join(data_path, 'lines', line_image_file_name)
    imgray.save(image_path)
    return base_name, image_path

def write_kaldi_process_data_files(image_path, base_name, line_id, text):
    writer_id = str(base_name.split('-')[1])
    writer_id = str(writer_id).zfill(6)
    writer_id = 'writer' + writer_id
    utt_id = writer_id + '_' + base_name + '_' +  str(line_id).zfill(6)
    text_fh.write(utt_id + ' ' + text + '\n')
    utt2spk_fh.write(utt_id + ' ' + writer_id + '\n')
    image_fh.write(utt_id + ' ' + image_path + '\n')

### main ###
data_path = args.database_path
text_file = os.path.join('data', args.dataset, 'text')
text_fh = open(text_file, 'w', encoding='utf-8')
utt2spk_file = os.path.join('data', args.dataset, 'utt2spk')
utt2spk_fh = open(utt2spk_file, 'w', encoding='utf-8')
image_file = os.path.join('data', args.dataset, 'images.scp')
image_fh = open(image_file, 'w', encoding='utf-8')

xml_path = args.database_path + '/rimes_2011.xml'
doc = minidom.parse(xml_path)
single_page = doc.getElementsByTagName('SinglePage')
for page in single_page:
    file_name = page.getAttribute('FileName')
    line = page.getElementsByTagName('Line')
    line_id = 0
    for node in line:
        line_id += 1
        bottom = int(node.getAttribute('Bottom'))
        left = int(node.getAttribute('Left'))
        right = int(node.getAttribute('Right'))
        top = int(node.getAttribute('Top'))
        text = node.getAttribute('Value')
        text_vect = text.split() # this is to avoid non-utf-8 spaces
        text = " ".join(text_vect)
        base_name, image_path = get_line_images_from_page_image(file_name, left, right, top, bottom, line_id)
        write_kaldi_process_data_files(image_path, base_name, line_id, text)
