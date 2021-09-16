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
SCR_DIR="$(dirname "$(readlink -f "$0")")"

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <kcap artifacts>

       After capturing, you may want to unpatch deployments/statefulsets
       in order to restore the previous state. This script will be executed
       over the artifacts directory for the capture.

EOF
}

# $1: deployment|statefulset; $2: resource name
unpatch_resource() {
  local resource_type=$1
  local resource_name=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <deployment|statefulset> <resource name>" && return 1

  echo "Unpatching ${resource_type} '${resource_name}' ..."

  kubectl rollout undo ${resource_type}/"${resource_name}" -n "${NAMESPACE}" &>/dev/null
}

#############
# EXECUTION #
#############

[ -z "$1" -o "$1" = "-h" -o "$1" = "--help" ] && usage && exit 1
ARTIFACTS_DIR=$1

MD_DIR="${ARTIFACTS_DIR}/metadata"
NAMESPACE="$(cat ${MD_DIR}/namespace 2>/dev/null)"
[ -z "${NAMESPACE}" ] && echo "Missing kcap metadata at '${MD_DIR}'" && exit 1

for deployment in $(find "${MD_DIR}"/deployments -type f | xargs -L1 basename 2>/dev/null); do
  unpatch_resource deployment "${deployment}" &
done
for statefulset in $(find "${MD_DIR}"/statefulsets -type f | xargs -L1 basename 2>/dev/null); do
  unpatch_resource statefulset "${statefulset}" &
done

