#! /usr/bin/env python

import argparse
import wave

def main(args = None):
    parser = argparse.ArgumentParser(description="Fix wav length in metadata")
    parser.add_argument("in_", type=lambda x: wave.open(x, 'rb'))
    parser.add_argument("out", type=lambda x: wave.open(x, 'wb'))
    parser.add_argument("--chunk-size", type=int, default=10_000)
    
    options = parser.parse_args(args)

    in_ : wave.Wave_read = options.in_
    out : wave.Wave_write = options.out

    # number of frames will be clobbered on close
    out.setparams(in_.getparams())

    chunk = in_.readframes(options.chunk_size)
    while chunk:
        out.writeframes(chunk)
        chunk = in_.readframes(options.chunk_size)


if __name__ == "__main__":
    main()
