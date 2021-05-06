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
PATCH_TIMEOUT=200s
KCAP_TAG=${KCAP_TAG:-latest}

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <namespace> [clean]

       Capture pods traffic in provided namespace by mean
       patching deployments and statefulsets to add a 'kcap'
       image container inside every pod. That container will
       start pcap captures at detected listen ports.

       This procedure will create an artifacts directory
       where some metadata is stored to be used by the next
       stage driven by './retrieve.sh' script:

       <artifacts example>
                │
                └── metadata
                    ├── deployments
                    │   ├── server1
                    │   └── server2
                    ├── endpoints
                    │   ├── 10.105.101.231
                    │   ├── 10.111.17.117
                    │   ├── 172.17.0.13
                    │   ├── 172.17.0.16
                    │   ├── 172.17.0.17
                    │   └── 172.17.0.9
                    ├── monitor
                    │   ├── server1-584987db45-8l8r4.sh
                    │   ├── server1-584987db45-hz459.sh
                    │   ├── server2-cbcf96fd9-bjk2x.sh
                    │   └── server2-cbcf96fd9-v4tpt.sh
                    ├── namespace
                    ├── pods
                    │   ├── server1-584987db45-8l8r4
                    │   ├── server1-584987db45-hz459
                    │   ├── server2-cbcf96fd9-bjk2x
                    │   └── server2-cbcf96fd9-v4tpt
                    ├── pods_for_deletion
                    │   ├── demo-cbfc88d84-tkb99
                    │   ├── server1-85f9648b44-bmn99
                    │   ├── server1-85f9648b44-x7swt
                    │   ├── server2-55678bd5b4-4l9dn
                    │   └── server2-55678bd5b4-t4cwm
                    └── statefulsets


       You could provide the second optional argument as a
       non-empty parameter indicator to kill tshark processes
       and cleanup remote artifacts before initiating a new
       capture. This speeds up captures as there is no need to
       unpatch the target system and start again from scratch.
       but as drawback it will generate tshark defunct kernel
       processes at the kcap containers, although this is not
       a problem in practice.

       Prepend variables:

       KCAP_TAG:   specify kcap image tag to use. By default 'latest'.
       SKIP_PATCH: non-empty value skips patching stage.

       Examples:

       KCAP_TAG=1.0.0 $0 ns-ct-h2agent
       SKIP_PATCH=yes $0 ns-ct-h2agent

EOF
}

# $1: deployment|statefulset; $2: resource name
get_pods() {
  local resource_type=$1
  local resource_name=$2

  # Pods within the resource:
  local pods
  if [ "${resource_type}" = "deployment" ]
  then
    local selector
    selector=$(kubectl get ${resource_type} "${resource_name}" -n "${NAMESPACE}" -o wide --no-headers | awk '{ print $NF }')
    pods=( $(kubectl get pod -n "${NAMESPACE}" --selector="${selector}" --no-headers 2>/dev/null | awk '{ print $1 }') )
  elif [ "${resource_type}" = "statefulset" ]
  then
    pods=( $(kubectl get pod -n "${NAMESPACE}" -l app="${resource_name}" --no-headers 2>/dev/null | awk '{ print $1 }') )
  fi

  echo "${pods[*]}"
}

# $1: deployment|statefulset; $2: resource name
patch_resource() {
  local resource_type=$1
  local resource_name=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <deployment|statefulset> <resource name>" && return 1

  echo "Patching ${resource_type} '${resource_name}' ..."

  # Already patched ?
  for pod in $(get_pods "${resource_type}" "${resource_name}")
  do
    if ! kubectl get pod "${pod}" -n "${NAMESPACE}" -o=jsonpath='{.spec.containers[*].name}' | grep -qw kcap
    then
      touch "${MD_DIR}/pods_for_deletion/${pod}" # pods which will be deleted as are not patched yet
    fi
  done

  rm -f "${MD_DIR}/pods/*"

  kubectl patch ${resource_type}/"${resource_name}" -n "${NAMESPACE}" -p '{
      "spec": {
          "template": {
              "spec": {
                  "containers": [
                      {
                          "image": "testillano/kcap:'${KCAP_TAG}'",
                          "terminationMessagePolicy": "File",
                          "imagePullPolicy": "IfNotPresent",
                          "name": "kcap",
                          "stdin": true,
                          "tty": true,
                          "securityContext": {
                              "capabilities": {
                                  "add": ["NET_ADMIN", "SYS_TIME"]
                              }
                          }
                      }
                  ]
              }
          }
      }
    }' 2>/dev/null
}

block_until_ready() {
  for pod in $(find "${MD_DIR}/pods_for_deletion" -type f | xargs -L1 basename 2>/dev/null)
  do
    echo "Wait for pod '${pod}' deletion ..."
    kubectl -n "${NAMESPACE}" wait --for=delete pod/"${pod}" --timeout="${PATCH_TIMEOUT}" &>/dev/null
  done

  # The next is assumed due to high availability default behavior (new pods are ready before starting to delete the old ones):
  # echo "Check new pods creation ..."
  # kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/${pod} --timeout=${PATCH_TIMEOUT}
}

# Persist endpoints
save_endpoints() {
  local endpoint
  local addrs
  local ips
  local current
  local next

  while read -r line
  do
    endpoint=$(echo "${line}" | awk '{ print $1 }')
    addrs=$(echo "${line}" | awk '{ print $2 }')

    ips=
    for ip in $(echo "${addrs}" | tr ',' '\n' | cut -d: -f1 | sort -u)
    do
      current=$(cat "${MD_DIR}/endpoints/${ip}" 2>/dev/null)
      next="$(echo "${current} ${endpoint}" | sed -e 's/^[[:space:]]*//')" # trimmed list
      echo "${next}" > "${MD_DIR}/endpoints/${ip}"
    done

  done < <(kubectl get endpoints -n "${NAMESPACE}" --no-headers | awk '{ print $1 " " $2 }' | grep -vw "<none>")

  while read -r line
  do
    ip="$(echo "${line}" | awk '{ print $1 }')"
    selector="$(echo "${line}" | awk '{ print $2 }')"

    # any of the endpoints is valid, as we will replace the service IP by the same thing than any of the associated endpoints
    ip_endpoint="$(kubectl get pod -n "${NAMESPACE}" --selector="${selector}" --no-headers -o wide | awk '{ print $6 }' | tail -1)"

    cat "${MD_DIR}/endpoints/${ip_endpoint}" > "${MD_DIR}/endpoints/${ip}"

  done < <(kubectl get services -n "${NAMESPACE}" --no-headers -o wide | awk '{ print $3 " " $7 }' | grep -vw "<none>")
}

# $1: deployment|statefulset; $2: resource name
capture() {
  local resource_type=$1
  local resource_name=$2

  local cmd=
  for pod in $(get_pods "${resource_type}" "${resource_name}")
  do
    cmd="netstat -a | grep -w LISTEN | awk '{ print \$4 }' | cut -d: -f2 > ports ; hostname -i > ip"
    cmd+="; [ -s ports ] && ./start.sh \$(cat ip) \"\$(cat ports)\" ${CLEAN} 2>/dev/null"
    if kubectl exec -it -n "${NAMESPACE}" "${pod}" -c kcap -- bash -c "${cmd}" 2>/dev/null; then
      touch "${MD_DIR}/${resource_type}s/${resource_name}"
      touch "${MD_DIR}/pods/${pod}"

      # Build monitor helper command:
      podIP="$(kubectl get pods -n "${NAMESPACE}" "${pod}" -o=jsonpath="{.status.podIP}")"
      ports=( $(kubectl exec -n "${NAMESPACE}" "${pod}" -c kcap -- bash -c "cat ports" 2>/dev/null) )
      #echo "${pod}" > "${MD_DIR}/endpoints/${podIP}"

      cat << EOF > "${MD_DIR}/monitor/${pod}.sh"
#!/bin/bash
# Live captures monitoring

echo
[ "\$1" = "-h" -o "\$1" = "--help" ] && echo "Usage: \$0 [space-separated list of ports to monitor, ${ports[*]} by default]" && exit 0

PORTS=\$@
PIDS=()
for port in ${ports[*]}
do
  if [ -n "\${PORTS}" ]
  then
    echo "\${PORTS}" | grep -qw "\${port}"
    [ \$? -ne 0 ] && continue
  fi
  echo "Start monitoring '\$(basename \$0 .sh)' at port \${port} ..."
  pipe=/tmp/kcap-pipe.\${port}
  rm -f \${pipe}
  mkfifo \${pipe}
  kubectl exec -n "${NAMESPACE}" "${pod}" -c kcap -- bash -c "tail -F -c +0 /kcap/artifacts/${podIP}/\${port}/capture.pcap" > \${pipe} &
  PIDS+=(\$!)
  sudo wireshark -k -i \${pipe} &>/dev/null &
  pid=\$!
  ppid=\$(ps --ppid \${pid} -o pid=)
  until [ -n "\${ppid}" ]; do ppid=\$(ps --ppid \$! -o pid=); done
  PIDS+=(\${ppid})
done

trap "sudo kill \${PIDS[*]} 2>/dev/null" INT QUIT TERM
wait \${PIDS[*]}
echo -e "\nFinished captures monitoring !\n"
EOF
      chmod a+x "${MD_DIR}/monitor/${pod}.sh"
    fi

  done
}

#############
# EXECUTION #
#############

[ -z "$1" ] && usage && exit 1
NAMESPACE=$1
CLEAN=$2

# Artifacts directory
ARTIFACTS_DIR="${SCR_DIR}/artifacts/kcap/$(date +'%d%m%Y_%H%M%S')"

# Metadata
MD_DIR="${ARTIFACTS_DIR}/metadata"
mkdir -p "${MD_DIR}"
for dir in deployments statefulsets endpoints pods_for_deletion pods monitor; do
  mkdir "${MD_DIR}/${dir}" || { echo "Error creating metadata directory for '${dir}' !" && exit 1; }
done

# Namespace metadata
echo "${NAMESPACE}" > "${MD_DIR}/namespace"

# Symlink last artifacts
rm -f last && ln -s "${ARTIFACTS_DIR}" last

# Get all available deployments and statefulsets
deployments=( $(kubectl get deployments -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{ print $1 }') )
statefulsets=( $(kubectl get statefulsets -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{ print $1 }') )

if [ -z "${SKIP_PATCH}" ]
then
  # Patch resources
  if [ "${#deployments[@]}" -ne 0 ]; then
    echo
    echo "=== Patch deployments ==="
    for deployment in ${deployments[@]}; do
      patch_resource deployment "${deployment}"
    done
  fi

  if [ "${#statefulsets[@]}" -ne 0 ]; then
    echo
    echo "== Patch statefulsets ==="
    for statefulset in ${statefulsets[@]}; do
      patch_resource statefulset "${statefulset}"
    done
  fi
else
  echo
  echo "Skipping patching resources ..."
fi

# Block until new pods are ready
block_until_ready

# Persist new endpoints
save_endpoints

# Capture
if [ "${#deployments[@]}" -ne 0 ]; then
  echo
  echo "=== Capture deployments ==="
  for deployment in ${deployments[@]}; do
    capture deployment "${deployment}"
  done
fi

if [ "${#statefulsets[@]}" -ne 0 ]; then
  echo
  echo "== Capture statefulsets ==="
  for statefulset in ${statefulsets[@]}; do
    capture statefulset "${statefulset}"
  done
fi

cat << EOF

=== Generated capture metadata at artifacts directory ===
last -> ${ARTIFACTS_DIR}

$(if tree --version &>/dev/null ; then tree last ; fi)

To retrieve artifacts in any moment, just execute:
./retrieve.sh last

EOF

