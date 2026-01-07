#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import csv
import re
import sys
import unicodedata

# Mozc 辞書用定数 (IPADIC: 固有名詞-地名)
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
    return ''.join(result)

def clean_field(text):
    text = RE_PARENTHESES.sub('', text)
    if '以下に掲載がない場合' in text: return ''
    return text.strip().replace(' ', '').replace('　', '')

def process_csv(ken_all_path, jigyosyo_path, output_path):
    entries = set()

    # 1. 住所データ (ken_all.csv)
    try:
        with open(ken_all_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 9: continue
                # 3-5: カナ(都道府県,市区町村,町域), 6-8: 漢字
                yomi = [clean_field(row[i]) for i in range(3, 6)]
                word = [clean_field(row[i]) for i in range(6, 9)]
                
                # 都道府県+市区町村+町域
                if all(yomi) and all(word):
                    full_yomi = kata_to_hira("".join(yomi))
                    full_word = "".join(word)
                    entries.add((full_yomi, full_word))
                    # 市区町村+町域
                    sub_yomi = kata_to_hira(yomi[1] + yomi[2])
                    sub_word = word[1] + word[2]
                    entries.add((sub_yomi, sub_word))
    except Exception as e:
        print(f"Error reading ken_all: {e}", file=sys.stderr)

    # 2. 事業所データ (jigyosyo.csv)
    try:
        with open(jigyosyo_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 3: continue
                # 1: カナ, 2: 漢字
                yomi = clean_field(row[1])
                word = clean_field(row[2])
                if yomi and word:
                    entries.add((kata_to_hira(yomi), word))
    except Exception as e:
        print(f"Error reading jigyosyo: {e}", file=sys.stderr)

    # 出力
    with open(output_path, 'w', encoding='utf-8') as f:
        for yomi, word in sorted(entries):
            if not yomi or not word: continue
            # 読みのバリデーション (ひらがなのみ)
            if not all(0x3041 <= ord(c) <= 0x3096 or c in 'ー' for c in yomi):
                continue
            f.write(f"{yomi}\t{POS_ID}\t{POS_ID}\t{DEFAULT_COST}\t{word}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ken_all")
    parser.add_argument("jigyosyo")
    parser.add_argument("-o", "--output", default="mozcdic-ut-place-names.txt")
    args = parser.parse_args()
    process_csv(args.ken_all, args.jigyosyo, args.output)
