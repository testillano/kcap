#!/bin/bash

#############
# VARIABLES #
#############
SCR_DIR="$(dirname "$(readlink -f $0)")"
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
  rm -rf ${ARTIFACTS_DIR}
fi

for port in ${PORTS}
do
  dir="${ARTIFACTS_DIR}/${IP}/${port}"

  mkdir -p "${dir}"
  ps -fe | grep "tshark -i any -f tcp port ${port}" | grep -qv grep
  if [ $? -ne 0 ]
  then
    nohup tshark -i any -f "tcp port ${port}" -w "${dir}/capture.pcap" &>/dev/null &
  else
    echo "You forgot to unpatch deployment previously, so captures may be mixed."
  fi
done
ps -fea| grep tshark | grep capture.pcap

