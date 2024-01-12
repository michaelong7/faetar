#!/usr/bin/env -S awk -F ':' -f
BEGIN {
  last="";
  id="";
}
id != $1 {
  if (id != "") print id FS last;
  id=$1;
  last="";
}
id == $1 {
  $1="";
  v=substr($0,2,length($0)-1);
  if (last == "") last=v;
  else last=last FS v
}
END {print id FS last}