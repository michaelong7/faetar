#! /usr/bin/env python

import pympi
import argparse

from pathlib import Path

def main(args = None):
    parser = argparse.ArgumentParser(description="link wav file to eaf")
    parser.add_argument("in_eaf", type=Path)
    parser.add_argument("in_wav", default=None, type=Path)
    parser.add_argument("out_eaf", type=Path)

    options = parser.parse_args(args)

    in_eaf : Path = options.in_eaf
    in_wav : Path = options.in_wav
    out_eaf: Path = options.out_eaf

    eaf = pympi.Eaf(in_eaf.as_posix())
    eaf.remove_linked_files()
    eaf.add_linked_file(
        in_wav.absolute().as_posix(),
        in_wav.relative_to(out_eaf.parent).as_posix(),
        'audio/x-wav'
    )

    eaf.to_file(out_eaf)

if __name__ == '__main__':
    main()
