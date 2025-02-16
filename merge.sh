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
KCAP_IMG=${KCAP_IMG:-testillano/kcap:latest}

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <kcap artifacts> [http2 ports]

       This script will be executed over the artifacts directory after
       'retrieve.sh' execution, when all the pcaps have been gathered
       and join together under 'captures' subdirectory.

       A space-separated list of HTTP/2 ports may be provided to restrict
       the sequence diagram generation for merged captures. This could
       improve performance and eliminate noise during the procedure. By
       default, all the captures found under the artifacts directory will
       be merged and post-processed.

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
                ├── flow.1
                │   ├── merged.atxt  | merged: original merged data
                │   ├── merged.puml  |
                │   ├── merged.svg   |
                │   ├── merged2.atxt | merged2: endpoints collapsed
                │   ├── merged2.puml |
                │   └── merged2.svg  |
                ├── merged.pdml
                └── metadata
                    ├── deployments
                    │   ├── server1
                    │   └── server2
                ...

       Merged extensions:

       .pdml: xml artifact
       .atxt: Ascii sequence diagram
       .puml: PlantUML artifact
       .svg:  Vector graphics artifact

       Prepend variables:

       KCAP_IMG:   Specify kcap image to use.
                   Defaults to 'testillano/kcap:latest', uploaded to docker hub:
                     https://hub.docker.com/repository/docker/testillano/kcap

       Examples:

       KCAP_IMG=testillano/kcap:1.0.0 $0 last

EOF
}

#############
# EXECUTION #
#############

[ -z "$1" ] && usage && exit 1
[ -z "$1" -o "$1" = "-h" -o "$1" = "--help" ] && usage && exit 1
ARTIFACTS_DIR=$1
shift
HTTP2_PORTS=$@

RC=0
docker run --rm -it -w /kcap -v "$(readlink -f "${ARTIFACTS_DIR}")":/artifacts ${KCAP_IMG} ./merge.sh /artifacts ${HTTP2_PORTS} || RC=1
[ ${RC} -eq 1 ] && echo "Some errors detected during merge !"

echo
echo "All artifacts available at:"
echo
if tree --version &>/dev/null ; then tree "${ARTIFACTS_DIR}" ; fi
echo
echo "Try: firefox $(ls last/flow*/*.svg | tr '\n' ' ')"
echo

