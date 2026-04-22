#!/usr/bin/env python
"""Convert a Raindrop CSV export to Florilegio JSON import format.

Usage:
    python support/convert.py --in export.csv --out bookmarks.json

Only extracts: title, url, tags, created.
"""
# pyright: basic

import argparse
import csv
import json
import uuid


def convert(input_path: str, output_path: str) -> None:
    bookmarks = []

    with open(input_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            url = row.get("url", "").strip()
            if not url:
                print("NOT FOUND??")
                continue

            title = row.get("title", "").strip() or None
            tags = row.get("tags", "").strip() or None
            created = row.get("created", "").strip()

            bookmarks.append(
                {
                    "id": str(uuid.uuid4()),
                    "url": url,
                    "title": title,
                    "tags": tags,
                    "created_at": created or None,
                    "updated_at": created or None,
                }
            )

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(bookmarks, f, indent=2, ensure_ascii=False)

    print(f"Converted {len(bookmarks)} bookmarks → {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Raindrop CSV to Florilegio JSON"
    )
    parser.add_argument("--in", dest="input", required=True, help="Input CSV path")
    parser.add_argument("--out", dest="output", required=True, help="Output JSON path")
    args = parser.parse_args()
    convert(args.input, args.output)


if __name__ == "__main__":
    main()
