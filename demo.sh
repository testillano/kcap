#!/bin/bash

#############
# VARIABLES #
#############

REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_DIR" ] && { echo "You must execute under a valid git repository !" ; exit 1 ; }

CHART_NAME=demo
NAMESPACE="ns-${CHART_NAME}"
HELM_CHART="helm/${CHART_NAME}"

#############
# FUNCTIONS #
#############
usage() {
  cat << EOF

Usage: $0 [-h|--help]

       -h|--help:      this help

       Prepend variables:

       SKIP_HELM_DEPS: non-empty value skip helm dependencies update.
       REUSE:          non-empty value reuses the possible existing
                       deployment (by default, a cleanup is done).

       Examples:

       CLEAN=true $0 # deploys from scratch in case already deployed
EOF
}

# $1: namespace; $2: optional prefix app filter
get_pod() {
  #local filter="-o=custom-columns=:.metadata.name --field-selector=status.phase=Running"
  # There is a bug in kubectl: field selector status.phase is Running also for teminating pods
  local filter=
  [ -n "$2" ] && filter+=" -l app.kubernetes.io/name=${2}"

  # shellcheck disable=SC2086
  kubectl --namespace="$1" get pod --no-headers ${filter} | awk '{ if ($3 == "Running") print $1 }'
  return $?
}

#############
# EXECUTION #
#############

# shellcheck disable=SC2164
cd "${REPO_DIR}"

# shellcheck disable=SC2166
[ "$1" = "-h" -o "$1" = "--help" ] && usage && exit 0

echo
echo "================="
echo "Kcap example test"
echo "================="
echo
echo "(-h|--help for more information)"
echo
echo "Chart name:       ${CHART_NAME}"
echo "Namespace:        ${NAMESPACE}"
[ -n "${REUSE}" ] && echo "REUSE:            selected"
echo

if [ -z "${REUSE}" ]
then
  echo -e "\nCleaning up ..."
  helm delete "${CHART_NAME}" -n "${NAMESPACE}" &>/dev/null
fi

# Check deployment existence:
list=$(helm list -q --deployed -n "${NAMESPACE}" | grep -w "${CHART_NAME}")
if [ -n "${list}" ] # reuse
then
  echo -e "\nReusing detected deploment ..."
else
  echo -e "\nPreparing to deploy chart '${CHART_NAME}' ..."
  # just in case, some failed deployment exists:
  helm delete "${CHART_NAME}" -n "${NAMESPACE}" &>/dev/null

  echo -e "\nUpdating helm chart dependencies ..."
  if [ -n "${SKIP_HELM_DEPS}" ]
  then
    echo "Skipped !"
  else
    helm dep update "${HELM_CHART}" &>/dev/null || { echo "Error !"; exit 1 ; }
  fi

  echo -e "\nDeploying chart ..."
  kubectl create namespace "${NAMESPACE}" &>/dev/null
  # shellcheck disable=SC2086
  helm install "${CHART_NAME}" "${HELM_CHART}" -n "${NAMESPACE}" --wait || { echo "Error !"; exit 1 ; }
fi

echo -e "\nStart captures ..."
${REPO_DIR}/capture.sh "${NAMESPACE}"

echo -e "\nStart traffic ..."
test_pod="$(get_pod "${NAMESPACE}" demo)"
[ -z "${test_pod}" ] && echo "Missing target pod to test" && exit 1

# shellcheck disable=SC2068
kubectl exec -it "${test_pod}" -c demo1 -n "${NAMESPACE}" -- sh -c "source /venv/bin/activate && pytest $@"
# shellcheck disable=SC2068
kubectl exec -it "${test_pod}" -c demo2 -n "${NAMESPACE}" -- sh -c "source /venv/bin/activate && pytest $@"

echo -e "\nRetrieve capture artifacts ..."
${REPO_DIR}/retrieve.sh last

echo -e "\nMerge capture artifacts ..."
${REPO_DIR}/merge.sh last

