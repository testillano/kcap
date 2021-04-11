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
unset DEPLOYMENTS_TO_CAPTURE ; declare -A DEPLOYMENTS_TO_CAPTURE # deployments with listen ports to capture
ANY_PATCHED_POD=

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 <namespace> [clean]

       Capture deployment pods traffic in provided namespace.
       The deployments are patched to launch a 'kcap' image
       container in every pod and captures are started for
       the listen ports deteted.

       You could provide the second optional argument as a
       non-empty parameter indicator to kill tshark processes
       and cleanup remote artifacts before initiating a new
       capture. This speeds up captures as there is no need
       to unpatch the deployment everytime, but as drawback
       will generate tshark defunct kernel processes at the
       kcap containers.

       Prepend variables:

       KCAP_TAG: specify kcap image tag to use. By default 'latest'.

       Examples:

       KCAP_TAG=1.0.0 $0 ns-ct-h2agent
EOF
}

# $1: namespace; $2: deployment name
patch_deployment() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  echo "Patching deployment '${deployment}' ..."

  # Pods in deployment:
  local selector
  selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods
  # shellcheck disable=SC2207
  pods=( $(kubectl -n "${namespace}" get pod --selector="${selector}" --no-headers | awk '{ print $1 }') )

  # Already patched ?
  local willBePatched
  willBePatched=()
  # shellcheck disable=SC2068
  for pod in ${pods[@]}
  do
    if ! kubectl get pod "${pod}" -n "${namespace}" -o=jsonpath='{.spec.containers[*].name}' | grep -qw kcap
    then
      willBePatched+=("${pod}")
    fi
  done

  kubectl patch deployment/"${deployment}" -n "${namespace}" -p '{
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
    }'

  # shellcheck disable=SC2068
  for pod in ${willBePatched[@]}
  do
    echo "Wait for pod '${pod}' deletion ..."
    kubectl -n "${namespace}" wait --for=delete pod/"${pod}" --timeout="${PATCH_TIMEOUT}" &>/dev/null
  done

  # The next is assumed due to high availability default behavior (new pods are ready before starting to delete the old ones):
  # echo "Check new pods creation ..."
  # kubectl -n "${namespace}" wait --for=condition=Ready pod/${pod} --timeout=${PATCH_TIMEOUT}

  # shellcheck disable=SC2207
  pods=( $(kubectl -n "${namespace}" get pod --selector="${selector}" --no-headers | awk '{ print $1 }') )
  local cmd=
  # shellcheck disable=SC2068
  for pod in ${pods[@]}
  do
    [ -z "${ANY_PATCHED_POD}" ] && ANY_PATCHED_POD="${pod}" # anyone is valid for final merge

    cmd="netstat -a | grep -w LISTEN | awk '{ print \$4 }' | cut -d: -f2 > ports"
    cmd+="; hostname -i > ip"
    kubectl exec -it -n "${namespace}" "${pod}" -c kcap -- bash -c "${cmd}"
  done
}

# $1: namespace; $2: deployment name
unpatch_deployment() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  echo "Unpatching deployment '${deployment}' ..."

  kubectl rollout undo deployment/"${deployment}" -n "${namespace}" &>/dev/null
}

# $1: namespace; $2: deployment name
capture_deployment() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  # Pods in deployment:
  local selector
  selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods
  # shellcheck disable=SC2207
  pods=( $(kubectl -n "${namespace}" get pod --selector="${selector}" --no-headers | awk '{ print $1 }') )

  local valid=
  # shellcheck disable=SC2068
  for pod in ${pods[@]}
  do
    if kubectl exec -n "${namespace}" "${pod}" -c kcap -- bash -c "[ -s ports ] && ./start.sh \$(cat ip) \"\$(cat ports)\" ${CLEAN}" 2>/dev/null
    then
      valid=yes
    fi
  done
  [ -n "${valid}" ] && DEPLOYMENTS_TO_CAPTURE[${deployment}]=""
}

# $1: namespace; $2: deployment name
retrieve_artifacts() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  # Pods in deployment:
  local selector
  selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods
  # shellcheck disable=SC2207
  pods=( $(kubectl -n "${namespace}" get pod --selector="${selector}" --no-headers | awk '{ print $1 }') )

  # shellcheck disable=SC2068
  for pod in ${pods[@]}
  do
    mkdir -p "${ARTIFACTS_DIR}/${pod}"
    kubectl cp -n "${NAMESPACE}" "${pod}":/kcap/artifacts -c kcap "${ARTIFACTS_DIR}/${pod}" &>/dev/null
    echo "Generated '${ARTIFACTS_DIR}/${pod}'"
  done
}

#############
# EXECUTION #
#############

[ -z "$1" ] && usage && exit 1
NAMESPACE=$1
CLEAN=$2

echo
echo "Patching deployments in namespace '${NAMESPACE}' ..."
deployments=$(kubectl get deployments -n "${NAMESPACE}" --no-headers | awk '{ print $1 }')
for deployment in ${deployments}
do
  patch_deployment "${NAMESPACE}" "${deployment}"
done

echo
echo "Starting captures ..."
for deployment in ${deployments}
do
  capture_deployment "${NAMESPACE}" "${deployment}"
done

echo
echo "Press ENTER to retrieve captures, CTRL-C to abort"
read -r dummy

echo
echo "Retrieve and merge artifacts ..."
ARTIFACTS_DIR="${SCR_DIR}/artifacts/$(date +'%d%m%Y_%H%M%S')"
# shellcheck disable=SC2068
for deployment in ${!DEPLOYMENTS_TO_CAPTURE[@]}
do
  retrieve_artifacts "${NAMESPACE}" "${deployment}"
done
# Joined together, are uploaded to ANY_PATCHED_POD:
echo "Merge them within arbitrary pod (${ANY_PATCHED_POD}) ..."
kubectl exec -n "${NAMESPACE}" "${ANY_PATCHED_POD}" -c kcap -- bash -c "rm -rf /kcap/all-artifacts/" 2>/dev/null
kubectl cp -n "${NAMESPACE}" "${ARTIFACTS_DIR}" "${ANY_PATCHED_POD}":/kcap/all-artifacts/ -c kcap &>/dev/null
kubectl exec -n "${NAMESPACE}" "${ANY_PATCHED_POD}" -c kcap -- bash -c "./merge.sh /kcap/all-artifacts" 2>/dev/null
echo "Retrieve final artifacts ..."
kubectl cp -n "${NAMESPACE}" "${ANY_PATCHED_POD}":/kcap/all-artifacts/ -c kcap "${ARTIFACTS_DIR}" &>/dev/null
echo "Artifacts available at '${ARTIFACTS_DIR}'"

echo
echo "Press ENTER to unpatch deployment(s), CTRL-C to abort"
# shellcheck disable=SC2034
read -r dummy

echo
for deployment in ${deployments}
do
  unpatch_deployment "${NAMESPACE}" "${deployment}"
done

