#! /usr/bin/env python

# Copyright 2023 Sean Robertson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import sys
import argparse
import os
import logging
import gzip
import io
import itertools

from typing import Optional, Mapping, List, Union

# import torch
import numpy as np
import ngram_lm

from src.pydrobert.torch.data import parse_arpa_lm
from src.pydrobert.torch.argcheck import as_file


SOS_DEFTS = ("<s>", "<S>")
EOS_DEFTS = ("</s>", "</S>")
UNK_DEFTS = ("<unk>", "<UNK>")
VOCAB_SIZE_KEY = "vocab_size"
SOS_KEY = "sos"
EOS_KEY = "eos"
UNK_KEY = "unk"
FN = os.path.basename(__file__)

DESCRIPTION = f"""\
Compute perplexity of a corpus using an arpa LM

Treating a corpus C as a sequence of independent sentences s^(1), s^(2), ..., s^(S),

    P(C) = prod_(i=1 to S) P(s^(i)),

each sentence as a sequence of tokens s = (s_1, s_2, ... s_W), |s^(i)| = W_i, and the
probability of a sentence s determined by an N-gram/lookup LM as

    P(s) = prod_(j=1 to W_i) P(s_j|s_(j - 1), s_(j - 2), s_(j - (N - 1))),

the perplexity of a corpus is just the inverse of the M-th root of the corpus
probability,

    PP(C) = P(C)^(-1/M),

where M is the total number of tokens in the corpus,

    M = sum_(i=1 to S) W_s

It may be interpreted as the "average compressed vocabulary size." For actual vocabulary
size V, PP(C) << V in general. The perplexity of the corpus will change with the choice
of LM.

This script takes in a corpus as an (optionally gzipped) text file, one line per
sentence, and an n-gram/lookup LM, and prints the perplexity of the corpus to stdout.
For example, assuming that a gzipped ARPA lm is saved to "lm.arpa.gz" and the text file
is "text.gz":

   {FN} --arpa lm.arpa.gz text.gz

While fast and serviceable for small LMs, this pure-Python implementation isn't very
efficient memory-wise. 
"""


class CorpusDataset:
    filename: str
    token2id: Optional[Mapping[str, int]]
    eos: Optional[Union[str, int]]
    unk: Optional[int]

    def __init__(
        self,
        filename: str,
        token2id: Optional[Mapping[str, int]] = None,
        eos: Optional[Union[str, int]] = None,
        unk: Optional[int] = None,
    ):
        assert os.path.isfile(filename)
        if isinstance(eos, str) and token2id is not None:
            eos = token2id[eos]
        self.filename, self.token2id, self.eos, self.unk = filename, token2id, eos, unk

    def process_line(self, line: str):
        line_ = line.strip().split()
        if self.eos is not None:
            line_.append(self.eos)
        if self.token2id is None:
            return line_

    def __iter__(self):
        with open(self.filename, "rb") as fb:
            if fb.peek()[:2] == b"\x1f\x8b":
                ft = gzip.open(fb, mode="rt")
            else:
                ft = io.TextIOWrapper(fb)
            yield from (self.process_line(line) for line in ft)


def main_arpa(options: argparse.Namespace):
    logging.info("Parsing lm...")
    with open(options.arpa, "rb") as arpa:
        if arpa.peek()[:2] == b"\x1f\x8b":
            arpa = gzip.open(arpa, mode="rt")
        else:
            arpa = io.TextIOWrapper(arpa)
        prob_dicts = parse_arpa_lm(
            arpa, ftype=np.float32, to_base_e=False, logger=logging.getLogger()
        )
    logging.info("Parsed lm")

    logging.info("Building LM")
    lm = ngram_lm.BackoffNGramLM(
        prob_dicts,
        options.sos_token,
        options.eos_token,
        options.unk_token,
        destructive=True,
    )
    del prob_dicts
    logging.info("Built LM")

    logging.info("Computing perplexity")
    corpus = CorpusDataset(options.corpus, eos=options.eos_token)
    pp = lm.corpus_perplexity(corpus)
    logging.info("Computed perplexity")

    print(f"{pp:.10f}", file=options.output)


def main(args: Optional[str] = None):
    logging.captureWarnings(True)

    parser = argparse.ArgumentParser(
        description=DESCRIPTION,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    lm_grp = parser.add_mutually_exclusive_group(required=True)
    lm_grp.add_argument(
        "--arpa",
        type=as_file,
        metavar="PTH",
        default=None,
        help="Path to a(n optionally gzipped) ARPA file",
    )
    lm_grp.add_argument(
        "--states-and-token2id",
        nargs=2,
        type=as_file,
        metavar=("STATE_PTH", "TOKEN2ID_PTH"),
        default=None,
        help="Path to a(n optionally gzipped) state dict file (from "
        "arpa-lm-to-state-dict.py) and a token2id file for PyTorch decoding",
    )
    parser.add_argument(
        "corpus",
        metavar="PTH",
        type=as_file,
        help="Path to a(n optionally gzipped) text corpus",
    )
    parser.add_argument(
        "output",
        type=argparse.FileType("w"),
        nargs="?",
        default=sys.stdout,
        help="File to write perplexity to. Defaults to stdout",
    )
    parser.add_argument("--verbose", "-v", action="store_true", default=False)

    parser.add_argument(
        "--sos-token",
        metavar="TOK",
        default=None,
        help="Token used to demarcate the start of a token sequence",
    )
    parser.add_argument(
        "--eos-token",
        default=None,
        metavar="TOK",
        help="Token used to demarcate the end of a token sequence",
    )
    parser.add_argument(
        "--unk-token",
        default=None,
        metavar="TOK",
        help="Token replacing those missing from LM",
    )

    options = parser.parse_args(args)

    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        level=logging.INFO if options.verbose else logging.WARNING,
    )

    if options.arpa is not None:
        main_arpa(options)

if __name__ == "__main__":
    main()