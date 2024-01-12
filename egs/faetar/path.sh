if [ "$CONDA_DEFAULT_ENV" != "kaldi" ]; then
  if [ "$(hostname)" = "bludgeon" ]; then
    # my (sdrobert) local install. Feel free to add a condition for yours
    source /home/sdrobert/.pyenv/versions/miniconda3-latest/bin/activate kaldi || exit 1
  elif [ "$(hostname -d)" = "ca-central-1.compute.internal" ]; then
    # aws
    source /opt/conda/bin/activate kaldi || exit 1
  else
    # default assumes conda is properly set up on command line
    conda activate kaldi || exit 1
  fi
fi
export PATH="$PWD/utils/:$PATH"
# [ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
# export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD:$PATH
# [ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
# . $KALDI_ROOT/tools/config/common_path.sh
if locale -a | grep -Fx "C.utf8" >/dev/null; then
  export LC_ALL=C.utf8
elif locale -a | grep -Fx "C.UTF-8" >/dev/null; then
  export LC_ALL=C.UTF-8
elif locale -a | grep -Fx "en_US.utf8" >/dev/null; then
  export LC_ALL=en_US.utf8
fi
export PYTHONUNBUFFERED=1
