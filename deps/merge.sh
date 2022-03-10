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
MERGED_BN=merged

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <artifacts directory> [http2 ports]

       Artifacts directory provided must contain pcap files to be merged in this stage. Added artifacts
       here are courtesy of Deutsche Telekom 5G trace visualizer project (https://github.com/telekom/5g-trace-visualizer):

       ${MERGED_BN}.puml:  plantUML file (https://www.planttext.com/).

       Then, for each detected flow there will be a directory 'flow.<id>' with the following files inside:

         ${MERGED_BN}.atxt:  ascii text output for the merged flow.
         ${MERGED_BN}.pdml:  xml-based wireshark standard for packets description (https://wiki.wireshark.org/PDML).
         ${MERGED_BN}.svg:   scalable vector graphics format.

       Also '${MERGED_BN}2.*' files represent post-processed flows with pod names instead of endpoints' IPs.

       So, these artifacts together with the 'capture.pcap' files from captures execution, are rich enough to
       trobuleshoot any issue related to network interfaces inside the kubernetes cluster.

       A space-separated list of HTTP/2 ports may be provided to restrict the sequence diagram generation for
       merged captures. This could improve performance and eliminate noise during the procedure. By default,
       all the captures found under the artifacts directory will be merged and post-processed.

EOF
}

# $1: puml file
process() {
  local puml=$1

  echo "Process '${puml}' ..."
  local flow_dir=$(dirname ${puml})

  # Backup PlantUML for post process and also check that this file has been generated:
  local puml2=${flow_dir}/${MERGED_BN}2.puml
  cp ${puml} ${puml2}

  # Generate ascii art and svg:
  java -jar plantuml.jar -ttxt ${puml}
  java -jar plantuml.jar -tsvg ${puml}

  # shellcheck disable=SC2045
  for f in $(ls ${puml}.{atxt,pdml,puml,svg} 2>/dev/null); do ext=${f##*.}; mv "$f" "${ARTIFACTS_DIR}/${puml}.${ext}"; done

  #########################################################################################################################
  # Post-process PlantUML to replace IPs by Pod names:
  #
  # Example:
  #   <artifacts directory>/server1-584987db45-5246g/172.17.0.32
  #   <artifacts directory>/server2-cbcf96fd9-dqlfj/172.17.0.34
  #   <artifacts directory>/server1-584987db45-s748j/172.17.0.35
  #   <artifacts directory>/server2-cbcf96fd9-qrmwt/172.17.0.36
  while read -r line
  do
    podname="$(echo $line | awk '{ print $1 }' | sed 's/-/./g')" # dashes must be replaced (i.e. dots) to be PUML-compliant
    ip="$(echo $line | awk '{ print $2 }')"

    sed -i 's/\b'${ip}'\b/'${podname}'/g' ${puml2}

  done < <(ls -d ${ARTIFACTS_DIR}/captures/*/* | awk -F/ '{ print $(NF-1) " " $NF }')

  # Build atxt/svg
  java -jar plantuml.jar -ttxt ${flow_dir}/${MERGED_BN}2.puml
  java -jar plantuml.jar -tsvg ${flow_dir}/${MERGED_BN}2.puml
  mv ${flow_dir} "${ARTIFACTS_DIR}"
  #########################################################################################################################
}

#############
# EXECUTION #
#############

[ -z "$1" ] && usage && exit 1

ARTIFACTS_DIR=$1
shift
HTTP2_PORTS=$@

# Generating visualizer artifacts:
# shellcheck disable=SC2207
pcap_files=( $(find "${ARTIFACTS_DIR}" -follow -name "*.pcap") )
comma=
pcaps=
count=0
re='^[0-9]+$'

# shellcheck disable=SC2068
shopt -s extglob
rm -f +([0-9])
for pcap in ${pcap_files[@]}
do
  count=$((count+1))
  port="$(basename "$(dirname "${pcap}")")"
  link=${count}
  if ! [[ $port =~ $re ]]; then continue; fi # skip non-numeric ports

  if [ -n "${HTTP2_PORTS}" ]
  then
    echo "${HTTP2_PORTS}" | grep -qw "${port}"
    [ $? -ne 0 ] && continue
  fi

  pcaps+="${comma}${link}"
  ports+="${comma}${port}"
  comma=","
  ln -s "${pcap}" ${link}
done

# shellcheck disable=SC2164
cd "${SCR_DIR}"
python3 trace_visualizer.py "${pcaps}" -http2ports "${ports}" &>/dev/null
# Alternative: kubectl get pods --all-namespaces -o yaml > pods.yml
#              python3 trace_visualizer.py ${pcaps} -http2ports ${ports} -pods pods.yml

# Remove symlinks and possible flow directories:
rm -f +([0-9])
rm -rf flow.*
rm -rf ${ARTIFACTS_DIR}/flow.*
rm -f ${ARTIFACTS_DIR}/${MERGED_BN}.pdml

# Normally there is only one pdml file:
mv $(ls *.pdml 2>/dev/null) ${ARTIFACTS_DIR}/${MERGED_BN}.pdml

count=0
pumls=( $(ls *.puml 2>/dev/null) )
for puml in ${pumls[@]}
do
  count=$((count+1))
  mkdir flow.${count}
  flow=flow.${count}/${MERGED_BN}.puml
  mv ${puml} ${flow}
  process ${flow}
done

[ ${count} -eq 0 ] && { echo "ERROR: PlantUML file(s) not found !" ; exit 1 ; }
exit 0

