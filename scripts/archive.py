#!/usr/bin/env python3
"""Write a deterministic tar stream for a staged release tree."""

from __future__ import annotations

import argparse
import pathlib
import sys
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument("--root", required=True, type=pathlib.Path)
parser.add_argument("--epoch", required=True, type=int)
args = parser.parse_args()
with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
    for path in sorted(args.root.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"symlink is forbidden: {path}")
        relative = path.relative_to(args.root)
        info = archive.gettarinfo(str(path), arcname=str(relative))
        info.uid = 0
        info.gid = 0
        info.uname = ""
        info.gname = ""
        info.mtime = args.epoch
        if path.is_file():
            with path.open("rb") as stream:
                archive.addfile(info, stream)
        else:
            archive.addfile(info)
