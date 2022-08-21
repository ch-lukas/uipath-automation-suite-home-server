#!/bin/bash
set -e

#GLOBALS
DIR="$(dirname "${BASH_SOURCE[0]}")"
DIR="$(realpath "${DIR}")"

source $DIR/settings.cfg

CERT_CA_FILE_PATH=$CACERT
CERT_TLS_FILE_PATH=$TLSCERT
CERT_KEY_FILE_PATH=$TLSKEY

export KUBECONFIG="/etc/rancher/rke2/rke2.yaml" \
&& export PATH="$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin"

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function error() {
  echo -e "${RED}[ERROR][$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*${NC}\n" >&2
  exit 1
}

function info() {
  echo "[INFO] [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

function warn() {
  echo "${YELLOW}[WARN] [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*${NC}" >&2
}

function display_usage() {
  echo
  echo "***************************************************************************************"
  echo
  echo "Update cluster tls and server certificate"
  echo 
  echo "Usage:"
  echo "  $COMMAND_NAME [flags]"
  echo 
  echo "Flags:"
  echo "  --ca-cert-file                      Certificate Authority bundle to"
  echo "                                        sign the tls certificate"
  echo "  --tls-cert-file                     Public tls certificate for FQDN"
  echo "  --tls-key-file                      Private key for certificate provided"
  echo "                                        with --tls-cert-file"
  echo "  -h|--help                           Display help" 
  echo "  -f|--force                          Allow update of certificates. This may cause downtime"
  echo
  echo "***************************************************************************************"
  echo
}

function parse_long_args() {
  while (("$#")); do
    case "$1" in
    -d | --debug)
      info "Running in debug"
      shift
      set -x
      ;;

    -h | --help)
      display_usage
      shift
      exit 0
      ;;

    -f | --force)
      SKIP_CONFIRMATION="true"
      shift
      ;;

    --ca-cert-file)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CERT_CA_FILE_PATH=$2
        CERT_CA_FILE_PATH="${CERT_CA_FILE_PATH/#\~/$HOME}"
        shift 2
      else
        display_usage
        error "Argument for $1 is missing"
        shift 2
      fi
    ;;
    --tls-cert-file)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CERT_TLS_FILE_PATH=$2
        CERT_TLS_FILE_PATH="${CERT_TLS_FILE_PATH/#\~/$HOME}"
        shift 2
      else
        display_usage
        error "Argument for $1 is missing"
        shift 2
      fi
    ;;
    --tls-key-file)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        CERT_KEY_FILE_PATH=$2
        CERT_KEY_FILE_PATH="${CERT_KEY_FILE_PATH/#\~/$HOME}"
        shift 2
      else
        display_usage
        error "Argument for $1 is missing"
        shift 2
      fi
    ;;
    -*|*) # unsupported flags
      display_usage
      error "Error: Unsupported flag $1"
      exit 1
    ;;
    esac
  done

  if [[ ! -f ${CERT_CA_FILE_PATH} ]]; then 
    display_usage 
    error "Certificate Authority bundle \"${CERT_CA_FILE_PATH}\" not found"
  fi
  if [[ ! -f ${CERT_TLS_FILE_PATH} ]]; then 
    display_usage 
    error "Public tls certificate \"${CERT_TLS_FILE_PATH}\" not found"
  fi
  if [[ ! -f ${CERT_KEY_FILE_PATH} ]]; then 
    display_usage 
    error "Private key for certificate \"${CERT_KEY_FILE_PATH}\" not found"
  fi

  echo
}

function wait_for_pods_ready_label_selector() {
  local namespace=$1
  local app_label=$2

  local try=0
  local maxtry=30
  while [[ $(kubectl -n "$namespace" get pods -l app="$app_label" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') =~ "False" ]] && (( try != maxtry )); do 
    try=$((try+1))
    info "Waiting for app: $app_label to be available...${try}/${maxtry}" &&  sleep 10;
  done
}

function __is_pod_ready() {
  local pod_status
  pod_status="$(kubectl -n "$namespace" get po "$1" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}')"
  [[ "${pod_status}" == "True" ]] && echo "true" || echo "false"
}

function __pods_ready() {
  local pod

  if [[ "$#" == 0 ]]; then
    echo "true"
    return
  fi

  for pod in "${pods[@]}"; do
    if [[ "$(__is_pod_ready "$pod")" == "false" ]]; then
      echo "false"
      return
    fi
  done

  echo "true"
}

function are_all_pods_ready() {
  local all_pods
  all_pods=("$@")
  local pods_ready
  mapfile -t terminating_pods < <(kubectl -n "$namespace" get pods | grep "Terminating" | awk '{print $1}')

  pods=()
  for pod in "${all_pods[@]}"; do
    skip=
    for terminating_pod in "${terminating_pods[@]}"; do
        [[ "$pod" == "$terminating_pod" ]] && { skip=1; break; }
    done
    [[ -n $skip ]] || pods+=("$pod")
  done
  pods_ready="$(__pods_ready "${pods[@]}" "$namespace")"
  echo "${pods_ready}"
}

function wait_for_all_pods_in_namespace_ready() {
  local namespace=$1
  local start_time
  start_time=$(date +%s)
  local current_time
  current_time=$(date +%s)
  local all_deployments_ready
  
  mapfile -t deploy_list < <(kubectl get deploy -n "$namespace" | awk '{print $1}' | tail -n +2)
  while [[ $((current_time-start_time)) -le 1800 ]]; do
    all_deployments_ready="true"
    pending_deploy=()
    for deploy in "${deploy_list[@]}"; do
      if ! kubectl rollout status deployment "$deploy" -n "$namespace" --timeout 20s 2>/dev/null; then
        all_deployments_ready="false"
        pending_deploy+=("${deploy}")
      fi
    done
    
    pods=()
    for deploy in "${pending_deploy[@]}"; do
      selectors=$(kubectl get deploy "$deploy" -n "$namespace" --output=json | jq -j '.spec.selector.matchLabels | to_entries | map([.key, .value]|join("=")) | join(",")')
      mapfile -t pod_list < <(kubectl get pod -n "$namespace" -l "$selectors" | awk '{print $1}' | tail -n +2)
      pods+=("${pod_list[@]}")
    done

    if [[ "$all_deployments_ready" == "true" || "$(are_all_pods_ready "${pods[@]}")" == "true" ]]; then
      return 0
    fi
    
    current_time=$(date +%s)
    info "Waiting for pods to be ready..."
  done

  info "Waited for approx $((current_time-start_time)) seconds, but all pods are not ready yet."
  return 1
}

function scale_down_deployment(){
  local deployment_name=$1
  local namespace=$2

  info "Start Scale Down deployment ${deployment_name} under namespace ${namespace}..."
  info "Waiting to scale down deployment..."

  local try=0
  local maxtry=60
  success=0
  while (( try != maxtry )) ; do
    result=$(kubectl scale deployment "${deployment_name}" --replicas=0 -n "${namespace}") || true
    info "${result}"
    scaledown=$(kubectl get deployment "${deployment_name}" -n "${namespace}"|grep 0/0) || true
    if { [ -n "${scaledown}" ] && [ "${scaledown}" != " " ]; }; then
      info "Deployment scaled down successfully."
      success=1
      break
    else
      try=$((try+1))
      info "waiting for the deployment ${deployment_name} to scale down...${try}/${maxtry}";sleep 30
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Deployment ${deployment_name} scaled down failed"
  fi
}

function scale_down_all_deployment(){
  local namespace=$1

  info "Starting to scale down all the deployments under namespace: $namespace..."

  local try=0
  local maxtry=180
  success=0

  deploy_count=$(kubectl --namespace "${namespace}" get deploy --no-headers | wc -l)
  kubectl scale deployment --replicas=0 --namespace "${namespace}" --all > /dev/null\
    || return 1

  while (( try != maxtry )) ; do
    scaledown_count=$(kubectl --namespace "${namespace}" get deploy --no-headers | grep -c 0/0) \
      || return 1
    if [[ -n "${scaledown_count}" && "${scaledown_count}" == "${deploy_count}" ]]; then
      info "Deployment scaled down successfully."
      return 0
    else
      info "waiting for all the deployments in namespace to scale down...${try}/${maxtry}"
      try=$((try+1))
      sleep 10
    fi
  done
  return 1
}

function scale_up_deployment() {
  local deployment_name=$1
  local namespace=$2
  local replica=$3

  # Scale up deployments using PVCs
  info "Start Scale Up deployment ${deployment_name}..."

  info "Waiting to scale up deployment..."

  local try=1
  local maxtry=15
  success=0
  while (( try != maxtry )) ; do
    result=$(kubectl scale deployment "${deployment_name}" --replicas="${replica}" -n "${namespace}") || true
    info "${result}"

    scaleup=$(kubectl get deployment "${deployment_name}" -n "${namespace}"|grep "${replica}"/"${replica}") || true
    if ! { [ -n "${scaleup}" ] && [ "${scaleup}" != " " ]; }; then
      try=$((try+1))
      info "waiting for the deployment ${deployment_name} to scale up...${try}/${maxtry}";sleep 30
    else
      info "Deployment scaled up successfully."
      success=1
      break
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Deployment scaled up failed ${deployment_name}."
  fi
}

function scale_up_all_deployment() {
  local namespace=$1
  local replica=$2

  # Scale up deployments using PVCs
  info "Starting to scale down all the deployments under namespace: $namespace...."

  info "Waiting to scale up deployment..."

  kubectl --namespace "$namespace" scale deployment --replicas="$replica" --all > /dev/null \
    || return 1

  wait_for_all_pods_in_namespace_ready "$namespace" >/dev/null \
      || return 1

  return 0  
}

function wait_for_all_pods_in_namespace_ready() {
  local namespace=$1
  local start_time
  start_time=$(date +%s)
  local current_time
  current_time=$(date +%s)
  local all_deployments_ready
  
  mapfile -t deploy_list < <(kubectl get deploy -n "$namespace" | awk '{print $1}' | tail -n +2)
  while [[ $((current_time-start_time)) -le 1800 ]]; do
    all_deployments_ready="true"
    pending_deploy=()
    for deploy in "${deploy_list[@]}"; do
      if ! kubectl rollout status deployment "$deploy" -n "$namespace" --timeout 20s 2>/dev/null; then
        all_deployments_ready="false"
        pending_deploy+=("${deploy}")
      fi
    done
    
    pods=()
    for deploy in "${pending_deploy[@]}"; do
      selectors=$(kubectl get deploy "$deploy" -n "$namespace" --output=json | jq -j '.spec.selector.matchLabels | to_entries | map([.key, .value]|join("=")) | join(",")')
      mapfile -t pod_list < <(kubectl get pod -n "$namespace" -l "$selectors" | awk '{print $1}' | tail -n +2)
      pods+=("${pod_list[@]}")
    done

    if [[ "$all_deployments_ready" == "true" || "$(are_all_pods_ready "${pods[@]}")" == "true" ]]; then
      return 0
    fi
    
    current_time=$(date +%s)
    info "Waiting for pods to be ready..."
  done

  info "Waited for approx $((current_time-start_time)) seconds, but all pods are not ready yet."
  return 1
}

function update_docker_registry_certs() {
  local tls_secret_name="docker-registry-tls"
  local namespace="docker-registry"
  local deployment="docker-registry"
  
  kubectl create secret generic ${tls_secret_name} \
    --namespace ${namespace} \
    --from-file=tls.crt="${CERT_TLS_FILE_PATH}" \
    --from-file=tls.key="${CERT_KEY_FILE_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  old_replica_count=$(kubectl get deploy ${deployment} -n ${namespace} -o=jsonpath="{.spec.replicas}") || old_replica_count=1
  # This statement is just to be on safe side, if somehow kubectl command returns 0 as old_replica_count then it will reset to 1
  [[ "${old_replica_count}" == "0" ]] && old_replica_count=1
  
  trap '' SIGINT
  scale_down_deployment "${deployment}" "${namespace}"
  scale_up_deployment "${deployment}" "${namespace}" "${old_replica_count}"
  trap - SIGINT

  if wait_for_all_pods_in_namespace_ready "${namespace}"; then
    info "Docker Registry update successfully"
  else
    error "Docker Registry update failed"
  fi
}

function update_istio_certificate() {
  local tls_secret_name="istio-ingressgateway-certs"
  local namespace="istio-system"
  local label='config-discovery=yes'
  local service_namespace="uipath"
  
  tmp_dir=$(mktemp -d certificates.XXXXXXX)
  tmp_file="ca_tls_merged.crt"
  cat "${CERT_TLS_FILE_PATH}" "${CERT_CA_FILE_PATH}" >> "${tmp_dir}"/"${tmp_file}"
  merge_ca_and_tls_path="${tmp_dir}"/"${tmp_file}"

  kubectl create secret generic ${tls_secret_name} \
    --namespace ${namespace} \
    --from-file=ca.crt="${CERT_CA_FILE_PATH}" \
    --from-file=tls.crt="${merge_ca_and_tls_path}" \
    --from-file=tls.key="${CERT_KEY_FILE_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl label secret ${tls_secret_name} "${label}" \
    --namespace ${namespace} --overwrite=true

  kubectl create secret generic ${tls_secret_name} \
    --namespace ${service_namespace} \
    --from-file=ca.crt="${CERT_CA_FILE_PATH}" \
    --from-file=tls.crt="${merge_ca_and_tls_path}" \
    --from-file=tls.key="${CERT_KEY_FILE_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  rm -rf "${tmp_dir}"
}

function update_server_certificate() {
  local service_namespace="uipath"
  #cert_validation_status=$(validate_server_certificate "${CERT_CA_FILE_PATH}" "${CERT_TLS_FILE_PATH}" "${CERT_KEY_FILE_PATH}" "${CLUSTER_FQDN}" "${ARGO_FQDN}" "${OBJECTSTORE_FQDN}" "${REGISTRY_FQDN}" "${MONITORING_FQDN}" "${INSIGHTS_FQDN}")
  #[[ "${cert_validation_status}" == "success" ]] && info "Validating Server Certificate... Done"

  info "TLS Server Certificate updation is in process, may take upto 30mins \n" 
  info "Configuring TLS ca certificates... IN PROGRESS"

  if [[ "${INSTALL_TYPE}" == "offline" ]]; then
    update_docker_registry_certs >/dev/null
    info "Docker Registry Update... DONE"
    update_argocd_trusted_certs "${REGISTRY_FQDN}" >/dev/null
    info "argocd update done..."
  fi

  update_istio_certificate >/dev/null
  info "Istio Routing Update... DONE"
  
  if [[ "$PROFILE" == "ha" ]]; 
  then
    info "Now restarting pods in uipath namespace"
    kubectl rollout restart deployment --namespace "${service_namespace}" >/dev/null
    info "Waiting for pods to be ready"
    wait_for_all_pods_in_namespace_ready "${service_namespace}" \
      || error "Certificate update failed - timeout waiting for all pods to restart and ready in namespace $service_namespace"
  else
    scale_down_all_deployment "$service_namespace" \
      || error "Certificate update failed - Scalling down all deployment in namespace $service_namespace failed"
    scale_up_all_deployment "$service_namespace" "1" \
      || error "Certificate update failed - Scalling up all deployment in namespace $service_namespace failed" 
  fi
  
  info "Certificate update successfully..."
  exit 0
}

function get_cluster_config_default() {
  value="$(get_cluster_config "$1")"

  [[ -z ${value} ]] && value=$2
  
  echo -n "$value"
}

function get_cluster_config() {
  local NAMESPACE="uipath-infra"
  local CONFIG_NAME="service-cluster-configurations"
  local key=$1
  
  # the go template if prevents it from printing <no-value> instead of empty strings
  value=$(kubectl get secret ${CONFIG_NAME} \
    -o "go-template={{if index .data \"${key^^}\"}}{{index .data \"${key^^}\"}}{{end}}" \
    -n ${NAMESPACE} --ignore-not-found 2>/dev/null) || true

  echo -n "$(base64 -d <<<"$value")"
}

function set_fqdn() {
  CLUSTER_FQDN=$(get_cluster_config "CLUSTER_FQDN")
  #shellcheck disable=SC2015
  [ -z "${CLUSTER_FQDN}" ] && error "Cluster fqdn is not found in cluster" || true

  ARGO_FQDN=$(get_cluster_config "ARGOCD_FQDN")
  OBJECTSTORE_FQDN=$(get_cluster_config "OBJECTSTORE_FQDN")
  REGISTRY_FQDN=$(get_cluster_config "REGISTRY_FQDN")
  MONITORING_FQDN=$(get_cluster_config "MONITORING_FQDN")
  INSIGHTS_FQDN=$(get_cluster_config "INSIGHTS_FQDN")
  INSTALL_TYPE=$(get_cluster_config "INSTALL_TYPE")

  PROFILE=$(get_cluster_config_default "PROFILE" "ha")
}

function main() {
  #parse_long_args "$@"
  set_fqdn
  update_server_certificate
}

main "$@"
#exit 0