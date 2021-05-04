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

       This script will be executed over the artifacts directory after
       'retrieve.sh' execution, when all the pcaps have been gathered
       and join together under 'captures' subdirectory.

       New artifacts, like PlantUML and svg sequence diagrams, will be
       created under artifacts subdirectory:

       <artifacts example>
                │
                ├── captures
                │   ├── server1-584987db45-ktm8g
                │   │   └── 172.17.0.16
                │   │       ├── 8000
                │   │       │   └── capture.pcap
                │   │       └── 8074
                │   │           └── capture.pcap
                ...
                ├── merged.atxt             merged: original merged data
                ├── merged.pdml             merged2: endpoints collapsed
                ├── merged.puml
                ├── merged.svg
                ├── merged2.atxt            .atxt: Ascii sequence diagram
                ├── merged2.puml            .puml: PlantUML artifact
                ├── merged2.svg             .svg:  Vector graphics artifact
                └── metadata
                    ├── deployments
                    │   ├── server1
                    │   └── server2
                ...

EOF
}

#############
# EXECUTION #
#############

[ -z "$1" ] && usage && exit 1
ARTIFACTS_DIR=$1

RC=0
docker run --rm -it -w /kcap -v "$(readlink -f "${ARTIFACTS_DIR}")":/artifacts testillano/kcap:latest ./merge.sh /artifacts || RC=1
[ ${RC} -eq 1 ] && echo "Some errors detected during merge !"

echo
echo "All artifacts available at:"
echo
if tree --version &>/dev/null ; then tree "${ARTIFACTS_DIR}" ; fi
echo
echo "Try: firefox last/merged.svg"
echo

