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
ARTIFACTS_DIR="${SCR_DIR}/artifacts"

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <ip> <ports> [clean]

       ip:    ip to sniff
       ports: space separated list of listen port to sniff
       clean: cleanup indicator to kill current tshark processes
              and remove artifacts directory. This provokes tshark
              defunct kernel processes, but allow to do agile and
              isolated captures.

       Artifacts generated: /kcap/artifacts/<ip>/<port1>/capture.pcap
                                                 <port2>/capture.pcap
                                                 ...

       Artifacts parent directory (${ARTIFACTS_DIR}) is removed before
       every capture, so you may gather all the generated information
       before using this script again.

       Examples:

       $0 172.17.0.6 "8074 8000"
       $0 172.17.0.6 "8074 8000" clean

EOF
}

#############
# EXECUTION #
#############

[ -z "$2" ] && usage && exit 1

# shellcheck disable=SC2164
cd "${SCR_DIR}"

IP=$1
PORTS="$2"
CLEAN=$3

# Extract kubernetes services and start captures:
echo
echo "Launching tshark processes in ${IP} ..."

if [ -n "${CLEAN}" ]
then
  echo "Killing previous tshark processes ..."
  pkill -9 tshark
  #sleep 5
  rm -rf "${ARTIFACTS_DIR}"
fi

for port in ${PORTS}
do
  dir="${ARTIFACTS_DIR}/${IP}/${port}"

  mkdir -p "${dir}"
  # shellcheck disable=SC2009
  if ps -fe | grep "tshark -i any -f tcp port ${port}" | grep -qv grep
  then
    echo "You forgot to unpatch deployment previously, so captures may be mixed."
  else
    nohup tshark -i any -f "host ${IP} and tcp port ${port}" -w "${dir}/capture.pcap" &>/dev/null &
  fi
done
# shellcheck disable=SC2009
ps -fea| grep tshark | grep capture.pcap

