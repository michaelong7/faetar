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
import re
import math

from typing import Dict, Optional, Mapping, List, Union, TextIO, Tuple, Type, TypeVar

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

K = TypeVar("K", bound=Union[str, int, np.signedinteger])
F = TypeVar("F", bound=Union[float, np.floating])

def parse_arpa_lm(
    file_: Union[TextIO, str],
    token2id: Optional[Dict[str, np.signedinteger]] = None,
    to_base_e: bool = None,
    ftype: Type[F] = float,
    logger: Optional[logging.Logger] = None,
) -> List[Dict[Union[K, Tuple[K, ...]], F]]:
    r"""Parse an ARPA statistical language model

    An `ARPA language model <https://cmusphinx.github.io/wiki/arpaformat/>`__
    is an n-gram model with back-off probabilities. It is formatted as::

        \data\
        ngram 1=<count>
        ngram 2=<count>
        ...
        ngram <N>=<count>

        \1-grams:
        <logp> <token[t]> <logb>
        <logp> <token[t]> <logb>
        ...

        \2-grams:
        <logp> <token[t-1]> <token[t]> <logb>
        ...

        \<N>-grams:
        <logp> <token[t-<N>+1]> ... <token[t]>
        ...

        \end\

    Parameters
    ----------
    file_
        Either the path or a file pointer to the file.
    token2id
        A dictionary whose keys are token strings and values are ids. If set, tokens
        will be replaced with ids on read
    to_base_e
        ARPA files store log-probabilities and log-backoffs in base-10. This 
    ftype
        The floating-point type to store log-probabilities and backoffs as
    logger
        If specified, progress will be written to this logger at INFO level

    Returns
    -------
    prob_dicts : list
        A list of the same length as there are orders of n-grams in the
        file (e.g. if the file contains up to tri-gram probabilities then
        `prob_dicts` will be of length 3). Each element is a dictionary whose
        key is the word sequence (earliest word first). For 1-grams, this is
        just the word. For n > 1, this is a tuple of words. Values are either
        a tuple of ``logp, logb`` of the log-probability and backoff
        log-probability, or, in the case of the highest-order n-grams that
        don't need a backoff, just the log probability.
    
    Warnings
    --------
    Version ``0.3.0`` and prior do not have the option `to_base_e`, always returning
    values in log base 10. While this remains the default, it is deprecated and will
    be removed in a later version.

    This function is not safe for JIT scripting or tracing.
    """
    if isinstance(file_, str):
        with open(file_) as f:
            return parse_arpa_lm(f, token2id, to_base_e, ftype, logger)
    if to_base_e is None:
        logging.warnings.warn(
            "The default of to_base_e will be changed to True in a later version. "
            "Please manually specify this argument to suppress this warning"
        )
        to_base_e = False
    norm = math.log10(math.e) if to_base_e else 1.0
    norm = ftype(norm)
    if logger is None:
        print_ = lambda x: None
    else:
        print_ = logger.info
    line = ""
    print_("finding \\data\\ header")
    for line in file_:
        if line.strip() == "\\data\\":
            break
    if line.strip() != "\\data\\":
        raise IOError("Could not find \\data\\ line. Is this an ARPA file?")
    ngram_counts: List[Dict[int, int]] = []
    count_pattern = re.compile(r"^ngram\s+(\d+)\s*=\s*(\d+)$")
    print_("finding n-gram counts")
    for line in file_:
        line = line.strip()
        if not line:
            continue
        match = count_pattern.match(line)
        if match is None:
            break
        n, count = (int(x) for x in match.groups())
        print_(f"there are {count} {n}-grams")
        if len(ngram_counts) < n:
            ngram_counts.extend(0 for _ in range(n - len(ngram_counts)))
        ngram_counts[n - 1] = count
    prob_dicts: List[Dict[Union[K, Tuple[K, ...]], F]] = [dict() for _ in ngram_counts]
    ngram_header_pattern = re.compile(r"^\\(\d+)-grams:$")
    ngram_entry_pattern = re.compile(r"^(-?\d+(?:\.\d+)?(?:[Ee]-?\d+)?)\s+(.*)$")
    while line != "\\end\\":
        match = ngram_header_pattern.match(line)
        if match is None:
            raise IOError('line "{}" is not valid'.format(line))
        ngram = int(match.group(1))
        if ngram > len(ngram_counts):
            raise IOError(
                "{}-grams count was not listed, but found entry" "".format(ngram)
            )
        dict_ = prob_dicts[ngram - 1]
        for line in file_:
            line = line.strip()
            if not line:
                continue
            match = ngram_entry_pattern.match(line)
            if match is None:
                break
            logp, rest = match.groups()
            tokens = tuple(rest.strip().split())
            # IRSTLM and SRILM allow for implicit backoffs on non-final
            # n-grams, but final n-grams must not have backoffs
            logb = ftype(0.0)
            if len(tokens) == ngram + 1 and ngram < len(prob_dicts):
                try:
                    logb = ftype(tokens[-1])
                    tokens = tokens[:-1]
                except ValueError:
                    pass
            if len(tokens) != ngram:
                raise IOError(
                    'expected line "{}" to be a(n) {}-gram' "".format(line, ngram)
                )
            if token2id is not None:
                tokens = tuple(token2id[tok] for tok in tokens)
            if ngram == 1:
                tokens = tokens[0]
            if ngram != len(ngram_counts):
                dict_[tokens] = (ftype(logp) / norm, logb / norm)
            else:
                dict_[tokens] = ftype(logp) / norm
    if line != "\\end\\":
        raise IOError("Could not find \\end\\ line")
    for ngram_m1, (ngram_count, dict_) in enumerate(zip(ngram_counts, prob_dicts)):
        if len(dict_) != ngram_count:
            raise IOError(f"Expected {ngram_count} {ngram_m1}-grams, got {len(dict_)}")
    return prob_dicts

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