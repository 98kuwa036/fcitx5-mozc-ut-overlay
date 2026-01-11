#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import csv
import re
import sys
import unicodedata

# Mozc 辞書用定数
POS_ID = 1847
DEFAULT_COST = 8000
RE_PARENTHESES = re.compile(r'[（\(].*?[）\)]')

def kata_to_hira(text):
    normalized = unicodedata.normalize('NFKC', text)
    result = []
    for ch in normalized:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F3:
            result.append(chr(code - 0x60))
        elif ch == 'ヵ': result.append('か')
        elif ch == 'ヶ': result.append('け')
        elif ch == 'ヴ': result.append('ゔ')
        else: result.append(ch)
    return "".join(result)

def clean_field(text):
    text = RE_PARENTHESES.sub('', text)
    if '以下に掲載がない場合' in text: return ''
    return text.strip().replace(' ', '').replace('　', '')

def process_csv(ken_all_path, jigyosyo_path, output_path):
    entries = set()
    # 住所データ
    try:
        with open(ken_all_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 9: continue
                yomi = [clean_field(row[i]) for i in range(3, 6)]
                word = [clean_field(row[i]) for i in range(6, 9)]
                if all(yomi) and all(word):
                    entries.add((kata_to_hira("".join(yomi)), "".join(word)))
    except Exception: pass
    # 事業所データ
    try:
        with open(jigyosyo_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 3: continue
                yomi, word = clean_field(row[1]), clean_field(row[2])
                if yomi and word: entries.add((kata_to_hira(yomi), word))
    except Exception: pass
    with open(output_path, 'w', encoding='utf-8') as f:
        for yomi, word in sorted(entries):
            if not yomi or not word: continue
            f.write(f"{yomi}\t{POS_ID}\t{POS_ID}\t{DEFAULT_COST}\t{word}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ken_all")
    parser.add_argument("jigyosyo")
    parser.add_argument("-o", "--output", default="mozcdic-ut-place-names.txt")
    args = parser.parse_args()
    process_csv(args.ken_all, args.jigyosyo, args.output)
