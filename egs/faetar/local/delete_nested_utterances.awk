#!/usr/bin/env -S awk -f
BEGIN {
  last="";
  rec="";
  start=0;
  end=10000;
  skip=0;
}
rec != $2 {
  if (last != "") print last;
  rec=$2
  last=$0;
  start=$3;
  end=$4;
}
rec == $2 {
  if (end <= $3) {
    if (skip == 0) {
      print last;
    }
    else {
      skip=0;
    }
  }
  else {
    skip=1;
  }
  start=$3;
  end=$4;
  last=$0;
}
END {if (last != "") print last}