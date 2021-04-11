#!/bin/bash

#   _
#  | |
#  | | _____ __ _ _ __
#  | |/ / __/ _` | '_ \  kcap utility to capture network interfaces in kubernetes cluster
#  |   < (_| (_| | |_) | Version 1.0.z
#  |_|\_\___\__,_| .__/  https://github.com/testillano/kcap
#                | |
#                |_|
#
# Licensed under the MIT License <http://opensource.org/licenses/MIT>.
# SPDX-License-Identifier: MIT
# Copyright (c) 2021 Eduardo Ramos
#
# Permission is hereby  granted, free of charge, to any  person obtaining a copy
# of this software and associated  documentation files (the "Software"), to deal
# in the Software  without restriction, including without  limitation the rights
# to  use, copy,  modify, merge,  publish, distribute,  sublicense, and/or  sell
# copies  of  the Software,  and  to  permit persons  to  whom  the Software  is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE  IS PROVIDED "AS  IS", WITHOUT WARRANTY  OF ANY KIND,  EXPRESS OR
# IMPLIED,  INCLUDING BUT  NOT  LIMITED TO  THE  WARRANTIES OF  MERCHANTABILITY,
# FITNESS FOR  A PARTICULAR PURPOSE AND  NONINFRINGEMENT. IN NO EVENT  SHALL THE
# AUTHORS  OR COPYRIGHT  HOLDERS  BE  LIABLE FOR  ANY  CLAIM,  DAMAGES OR  OTHER
# LIABILITY, WHETHER IN AN ACTION OF  CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE  OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

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
    read -r varname
    [ -z "${varname}" ] && varname=${default}
  fi
}

#############
# EXECUTION #
#############
# shellcheck disable=SC2164
cd "$(dirname "$0")"
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
# shellcheck disable=SC2086
docker build --rm ${bargs} -t testillano/kcap:"${image_tag}" . || return 1
set +x

