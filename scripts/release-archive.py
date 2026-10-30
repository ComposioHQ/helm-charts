#!/usr/bin/env python3
"""Deterministic regular-file archives; extraction uses the runner's safety checks."""
import gzip
import os
from pathlib import Path
import stat
import sys
import tarfile


def pack(source, destination, prefix=""):
    root = Path(source)
    files = []
    total = 0
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                raise ValueError("Archive contains a link or special file")
        for name in names:
            path = Path(directory) / name
            size = path.stat().st_size
            total += size
            if size > 256 * 1024 * 1024 or total > 1024 * 1024 * 1024:
                raise ValueError("Archive exceeds runner extraction budget")
            files.append(path)
    if len(files) > 100000:
        raise ValueError("Archive exceeds runner file budget")
    with open(destination, "xb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in sorted(files):
                    name = path.relative_to(root).as_posix()
                    member = tarfile.TarInfo(f"{prefix}/{name}" if prefix else name)
                    member.size = path.stat().st_size
                    member.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                    with path.open("rb") as content:
                        archive.addfile(member, content)


if __name__ == "__main__":
    pack(*sys.argv[1:])
