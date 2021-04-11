#!/bin/bash

#############
# VARIABLES #
#############
image_tag__dflt=latest
base_tag__dflt=latest
plantumljar_ver__dflt=1.2021.4

#############
# FUNCTIONS #
#############
# $1: variable by reference; $2: default value
_read() {
  local -n varname=$1
  local default=$2

  local s_default="<null>"
  [ -n "${default}" ] && s_default="${default}"
  echo "Input '$1' value [${s_default}]:"

  if [ -n "${varname}" ]
  then
    echo "${varname}"
  else
    read varname
    [ -z "${varname}" ] && varname=${default}
  fi
}

#############
# EXECUTION #
#############
cd $(dirname $0)
echo
echo "=== Build kcap image ==="
echo
echo "For headless mode, prepend/export asked variables:"
echo " $(grep "^_read " build.sh | awk '{ print $2 }' | tr '\n' ' ')"
echo
_read image_tag ${image_tag__dflt}
_read base_tag ${base_tag__dflt}
_read plantumljar_ver ${plantumljar_ver__dflt}

bargs="--build-arg base_tag=${base_tag}"
bargs+=" --build-arg plantumljar_ver=${plantumljar_ver}"

set -x
docker build --rm ${bargs} -t testillano/kcap:${image_tag} . || return 1
set +x

