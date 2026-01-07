#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2025 Overlay Maintainer
# Licensed under the Apache License, Version 2.0

"""
Generate place-names dictionary from Japan Post ZIP code data.
Reads pre-downloaded CSV files (ken_all.csv and jigyosyo.csv).

Usage: python generate_place_names_full.py <ken_all.csv> <jigyosyo.csv>
"""

import argparse
import csv
import re
import sys
import unicodedata
from typing import Set, Tuple

# Mozc Dictionary Constants
# ID 1847 corresponds to "Proper Noun - Place" in standard IPADIC
POS_ID_LEFT = 1847
POS_ID_RIGHT = 1847
DEFAULT_COST = 8000

# Regex for stripping parentheses and enclosed text
# Handles both full-width （） and half-width ()
# Note: ken_all often uses full-width for comments
RE_PARENTHESES = re.compile(r'[（\(].*?[）\)]')


def kata_to_hira(text: str) -> str:
    """
    Convert katakana to hiragana.
    Handles both full-width and half-width katakana via NFKC normalization.
    """
    normalized = unicodedata.normalize('NFKC', text)
    result = []
    for ch in normalized:
        code = ord(ch)
        # Katakana (ァ-ン: U+30A1-U+30F3) to Hiragana
        if 0x30A1 <= code <= 0x30F3:
            result.append(chr(code - 0x60))
        elif ch == 'ヵ':
            result.append('か')
        elif ch == 'ヶ':
            result.append('け')
        elif ch == 'ヴ':
            result.append('ゔ')
        else:
            result.append(ch)
    return ''.join(result)


def clean_address_field(text: str, is_reading: bool = False) -> str:
    """
    Clean address fields by removing parentheses/comments and normalizing.
    """
    # Normalize first
    if is_reading:
        # For reading, use NFKC to handle half-width kana
        text = unicodedata.normalize('NFKC', text)
    
    # Remove contents inside parentheses (e.g., "Ginza (1-chome)" -> "Ginza")
    text = RE_PARENTHESES.sub('', text)
    
    # Remove specific ignore phrases
    if '以下に掲載がない場合' in text:
        return ''
    
    # Remove whitespace
    text = text.replace(' ', '').replace('　', '')
    
    return text.strip()


def process_ken_all(csv_path: str) -> Set[Tuple[str, str]]:
    """
    Process ken_all.csv (residential addresses).
    Returns: set of (reading, surface) tuples
    """
    entries = set()

    try:
        with open(csv_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 9:
                    continue

                # Columns: 3=PrefKana, 4=CityKana, 5=TownKana
                # Columns: 6=PrefKanji, 7=CityKanji, 8=TownKanji
                
                pref_kana = clean_address_field(row[3], is_reading=True)
                city_kana = clean_address_field(row[4], is_reading=True)
                town_kana = clean_address_field(row[5], is_reading=True)

                pref_kanji = clean_address_field(row[6])
                city_kanji = clean_address_field(row[7])
                town_kanji = clean_address_field(row[8])

                # Combinations
                if pref_kana and pref_kanji:
                    entries.add((pref_kana, pref_kanji))

                if city_kana and city_kanji:
                    entries.add((city_kana, city_kanji))
                    entries.add((pref_kana + city_kana, pref_kanji + city_kanji))

                if town_kana and town_kanji:
                    entries.add((town_kana, town_kanji))
                    entries.add((city_kana + town_kana, city_kanji + town_kanji))
                    entries.add((pref_kana + city_kana + town_kana,
                                 pref_kanji + city_kanji + town_kanji))

    except Exception as e:
        print(f"Error processing {csv_path}: {e}", file=sys.stderr)
        sys.exit(1)

    return entries


def process_jigyosyo(csv_path: str) -> Set[Tuple[str, str]]:
    """
    Process jigyosyo.csv (business/office addresses).
    """
    entries = set()

    try:
        with open(csv_path, 'r', encoding='cp932', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 3:
                    continue

                # 1: Kana, 2: Kanji
                name_kana = clean_address_field(row[1], is_reading=True)
                name_kanji = clean_address_field(row[2])

                if name_kana and name_kanji and len(name_kanji) >= 2:
                    entries.add((name_kana, name_kanji))

    except Exception as e:
        print(f"Error processing {csv_path}: {e}", file=sys.stderr)
        sys.exit(1)

    return entries


def main():
    parser = argparse.ArgumentParser(description="Generate Mozc place-names dictionary")
    parser.add_argument("ken_all", help="Path to ken_all.csv")
    parser.add_argument("jigyosyo", help="Path to jigyosyo.csv")
    parser.add_argument("-o", "--output", default="mozcdic-ut-place-names.txt", help="Output file path")
    parser.add_argument("--cost", type=int, default=DEFAULT_COST, help=f"Dictionary cost (default: {DEFAULT_COST})")
    
    args = parser.parse_args()

    all_entries = set()

    print(f"Processing {args.ken_all}...")
    all_entries.update(process_ken_all(args.ken_all))

    print(f"Processing {args.jigyosyo}...")
    all_entries.update(process_jigyosyo(args.jigyosyo))

    print(f"Total unique entries: {len(all_entries)}")
    print(f"Generating dictionary to {args.output}...")

    valid_count = 0
    
    try:
        with open(args.output, 'w', encoding='utf-8') as f:
            for kana, kanji in sorted(all_entries):
                if not kana or not kanji:
                    continue

                reading = kata_to_hira(kana)

                # Validate reading (Hiragana, prolonged mark, iteration marks)
                valid = True
                for ch in reading:
                    if not (0x3041 <= ord(ch) <= 0x3096 or ch in 'ーゝゞ'):
                        valid = False
                        break
                
                if valid:
                    f.write(f"{reading}\t{POS_ID_LEFT}\t{POS_ID_RIGHT}\t{args.cost}\t{kanji}\n")
                    valid_count += 1
    except IOError as e:
        print(f"Error writing output: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Done. Written {valid_count} entries.")


if __name__ == "__main__":
    main()
