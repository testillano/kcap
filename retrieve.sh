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

       When we initiate a system capture by mean './capture.sh', an artifacts
       directory is created with metadata used to identify the deployments,
       statefulsets and other elements to analyze.

       This script will be executed over the artifacts directory mentioned,
       and will join together every pcap capture under 'captures' subdirectory:

       <artifacts example>
                │
                ├── captures
                │   ├── server1-584987db45-8l8r4
                │   │   └── 172.17.0.16
                │   │       ├── 8000
                │   │       │   └── capture.pcap
                │   │       └── 8074
                │   │           └── capture.pcap
                │   ├── server1-584987db45-hz459
                │   │   └── 172.17.0.9
                │   │       ├── 8000
                │   │       │   └── capture.pcap
                │   │       └── 8074
                │   │           └── capture.pcap
                │   ├── server2-cbcf96fd9-bjk2x
                │   │   └── 172.17.0.17
                │   │       ├── 8000
                │   │       │   └── capture.pcap
                │   │       └── 8074
                │   │           └── capture.pcap
                │   └── server2-cbcf96fd9-v4tpt
                │       └── 172.17.0.13
                │           ├── 8000
                │           │   └── capture.pcap
                │           └── 8074
                │               └── capture.pcap
                └── metadata
                    ├── deployments
                    │   ├── server1
                    │   └── server2
                    ...

       The next stage will be driven by './merge.sh' script.

EOF

}

retrieve_artifacts_from_pods() {

  local captures="${ARTIFACTS_DIR}/captures"

  for pod in $(find "${MD_DIR}"/pods -type f | xargs -L1 basename 2>/dev/null)
  do
    mkdir -p "${captures}/${pod}"
    kubectl cp -n "${NAMESPACE}" "${pod}":/kcap/artifacts -c kcap "${captures}/${pod}" &>/dev/null
    echo "Generated '${captures}/${pod}'"
  done
}

#############
# EXECUTION #
#############

[ -z "$1" -o "$1" = "-h" -o "$1" = "--help" ] && usage && exit 1
ARTIFACTS_DIR=$1

MD_DIR="${ARTIFACTS_DIR}/metadata"
NAMESPACE="$(cat ${MD_DIR}/namespace 2>/dev/null)"
[ -z "${NAMESPACE}" ] && echo "Missing kcap metadata at '${MD_DIR}'" && exit 1

echo
echo "Retrieve artifacts ..."
retrieve_artifacts_from_pods

shopt -s extglob
cat << EOF

=== Joined captures ===
last -> ${ARTIFACTS_DIR}

$(if tree --version &>/dev/null ; then tree last/captures ; fi)

To merge artifacts in any moment, just execute:
./merge.sh last

As a recommendation, remove (or move away from 'last' structure)
all those pcaps that are not related to HTTP/2 protocol, because
they could dirty the final artifacts and would take many time to
complete the merge stage.

You could also provide ports to be analized, by default all available
ports are processed:

./merge.sh last $(ls -d last/captures/*/*/+([0-9])/ | xargs -L1 basename | sort -u | tr '\n' ' ')


To unpatch deployment(s)/statefulset(s), you may execute:
./unpatch.sh last"

EOF

