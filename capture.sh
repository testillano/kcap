#!/bin/bash

#############
# VARIABLES #
#############
SCR_DIR="$(dirname "$(readlink -f $0)")"
TIMEOUT=200s
KCAP_TAG=${KCAP_TAG:-latest}
VALID_DEPLOYMENTS= # deployments with listen ports to capture
VALID_POD=

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
EOF
}

# $1: namespace; $2: deployment name
patch_deployment() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  echo "Patching deployment '${deployment}' ..."

  # Pods in deployment:
  local selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods=$(kubectl -n "${namespace}" get pod --selector=${selector} --no-headers | awk '{ print $1 }')

  # Already patched ?
  local unpatched=
  for pod in ${pods}
  do
    kubectl get pod "${pod}" -n "${namespace}" -o json | jq -r '.spec.containers[].name' | grep -qw ^kcap$
    [ $? -ne 0 ] && unpatched="${unpatched} ${pod}"
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

  for pod in ${unpatched}
  do
    echo "Wait for pod '${pod}' deletion ..."
    kubectl -n "${namespace}" wait --for=delete pod/${pod} --timeout=${TIMEOUT} &>/dev/null
  done

  # The next is assumed due to security overlap:
  # echo "Check new pods creation ..."
  # kubectl -n "${namespace}" wait --for=condition=Ready pod/${pod} --timeout=${TIMEOUT}

  pods=$(kubectl -n "${namespace}" get pod --selector=${selector} --no-headers | awk '{ print $1 }')
  cmd=
  for pod in ${pods}
  do
    [ -z "${VALID_POD}" ] && VALID_POD="${pod}" # anyone is valid for final merge

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
  local selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods=$(kubectl -n "${namespace}" get pod --selector=${selector} --no-headers | awk '{ print $1 }')

  local valid=
  for pod in ${pods}
  do
    kubectl exec -n "${namespace}" "${pod}" -c kcap -- bash -c "[ -s ports ] && ./start.sh \$(cat ip) \"\$(cat ports)\" ${CLEAN}" 2>/dev/null
    [ $? -eq 0 ] && valid=yes
  done
  [ -n "${valid}" ] && VALID_DEPLOYMENTS="${VALID_DEPLOYMENTS} ${deployment}"
}

# $1: namespace; $2: deployment name
retrieve_artifacts() {
  local namespace=$1
  local deployment=$2

  [ -z "$2" ] && echo "Usage: ${FUNCNAME[0]} <namespace> <deployment>" && return 1

  # Pods in deployment:
  local selector=$(kubectl get deployment "${deployment}" -n "${namespace}" -o wide --no-headers | awk '{ print $NF }')
  local pods=$(kubectl -n "${namespace}" get pod --selector=${selector} --no-headers | awk '{ print $1 }')

  for pod in ${pods}
  do
    mkdir -p "${ARTIFACTS_DIR}/${pod}"
    kubectl cp -n "${NAMESPACE}" ${pod}:/kcap/artifacts -c kcap "${ARTIFACTS_DIR}/${pod}" &>/dev/null
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
read dummy

echo
echo "Retrieve and merge artifacts ..."
ARTIFACTS_DIR="${SCR_DIR}/artifacts/$(date +'%d%m%Y_%H%M%S')"
for deployment in ${VALID_DEPLOYMENTS}
do
  retrieve_artifacts "${NAMESPACE}" "${deployment}"
done
# Joined together, are uploaded to VALID_POD:
echo "Merge them within arbitrary pod (${VALID_POD}) ..."
kubectl exec -n "${NAMESPACE}" "${VALID_POD}" -c kcap -- bash -c "rm -rf /kcap/all-artifacts/" 2>/dev/null
kubectl cp -n "${NAMESPACE}" "${ARTIFACTS_DIR}" ${VALID_POD}:/kcap/all-artifacts/ -c kcap &>/dev/null
kubectl exec -n "${NAMESPACE}" "${VALID_POD}" -c kcap -- bash -c "./merge.sh /kcap/all-artifacts" 2>/dev/null
echo "Retrieve final artifacts ..."
#rm -rf ${ARTIFACTS_DIR}
kubectl cp -n "${NAMESPACE}" ${VALID_POD}:/kcap/all-artifacts/ -c kcap "${ARTIFACTS_DIR}" &>/dev/null
echo "Artifacts available at '${ARTIFACTS_DIR}'"

echo
echo "Press ENTER to unpatch deployment(s), CTRL-C to abort"
read dummy

echo
for deployment in ${deployments}
do
  unpatch_deployment "${NAMESPACE}" "${deployment}"
done

