#!/bin/bash

# This function prints out the usage of the script.
usage() {
  echo "Usage: ${0} [option...]"
  echo " -i, --interactive : Choose which overlay to apply interactively"
  echo " -b, --build       : Only build the overlays, do not execute"
  echo " -h, --help        : Show usage"
  echo " --deploy-all      : Build and deploy all overlays"
  echo " -d, --deploy      : Build and deploy specific overlay"
}

# This function terminates the script with a custom error message.
error_exit() {
  echo "Error: $1"
  exit 1
}

# This function locates and returns the full path of the file.
params_file() {
  local filename="${1}"
  local dir=$(pwd)
  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/${filename}" ]]; then
      echo "$(realpath "${dir}/${filename}")"
      return 0
    elif [[ -d "${dir}/.git" ]]; then
      break
    fi
    dir=$(dirname "${dir}")
  done
  find "$(pwd)" -path "*/.git" -prune -o -name "${filename}" -exec realpath {} \; -quit
}

# This function writes content to kustomization.yaml
kustomization_file() {
    cat <<EOF > ${OVERLAY_DST}/kustomization.yaml
  resources:
    - ../../base
  patches:
    - path: ingress-patch.yaml
      target:
        kind: Ingress
    - path: service-patch.yaml
      target:
        kind: Service
EOF
}

# This function writes content to ingress-patch.yaml
ingress_patch_file() {
    cat <<EOF > ${OVERLAY_DST}/ingress-patch.yaml
- op: replace
  path: "/metadata/name"
  value: "${SERVICE_NAME}-forwarder"
- op: replace
  path: "/metadata/namespace"
  value: "${NAMESPACE}"
- op: replace
  path: "/spec/ingressClassName"
  value: "nginx-${ENDPOINT}"
- op: replace
  path: "/spec/rules/0/host"
  value: "${FQDN}"
- op: replace
  path: "/spec/rules/0/http/paths/0/backend/service/name"
  value: "${SERVICE_NAME}"
- op: replace
  path: "/spec/rules/0/http/paths/0/backend/service/port/number"
  value: 443
- op: replace
  path: "/spec/tls/0/hosts/0"
  value: "${FQDN}"
- op: replace
  path: "/spec/tls/0/secretName"
  value: "tls-${SERVICE_NAME}-crt"
- op: add
  path: "/metadata/annotations/nginx.ingress.kubernetes.io~1upstream-vhost"
  value: "${DST_FQDN}"
EOF
}

# This function write contents to service-patch.yaml
service_patch_file() {
    cat <<EOF > ${OVERLAY_DST}/service-patch.yaml
- op: replace
  path: "/metadata/name"
  value: "${SERVICE_NAME}"
- op: replace
  path: "/metadata/namespace"
  value: "${NAMESPACE}"
- op: replace
  path: "/spec/externalName"
  value: "${DST_FQDN}"
- op: replace
  path: "/spec/ports/0/port"
  value: 443
EOF
}

# This function deploys all overlays
deploy_all_overlays() {
    echo "Deploying all overlays"
    for opt in "${options[@]}"; do
      echo "Deploying: ${opt}"
      kubectl apply -k ${OVERLAY_ROOT}/${opt}
    done
}

# This function deploys a specific overlay chosen interactively
deploy_interactive_overlay() {
    PS3='Please enter your choice (ctrl-C to exit): '
    options=($(ls ${OVERLAY_ROOT}))
    select opt in "${options[@]}"; do
      case $opt in
        *)
          echo "You have chosen to deploy: ${opt}"
          kubectl apply -k ${OVERLAY_ROOT}/${opt}
          break
          ;;
        *)
          echo "Invalid option $REPLY"
          ;;
      esac
    done
}

# This function deploys a specific overlay
deploy_specific_overlay(){
    echo "Deploying: ${DEPLOY_SPECIFIC}"
    kubectl apply -k ${OVERLAY_ROOT}/${DEPLOY_SPECIFIC}
}

# Main script starts here
CONFIG_FILE=$(params_file params.yaml)
OVERLAY_ROOT="overlay"
blocks_count=$(yq eval '. | length' ${CONFIG_FILE})                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  
DEPLOY_SPECIFIC=''
INTERACTIVE=false
BUILD_ONLY=false
DEPLOY_ALL=false

while (( "$#" )); do
  case "$1" in
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    -b|--build)
      BUILD_ONLY=true
      shift
      ;;
    --deploy-all)
      DEPLOY_ALL=true
      shift
      ;;
    -d|--deploy)
      DEPLOY_SPECIFIC=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      usage
      exit 1
      ;;
  esac
done

for (( i=0; i<${blocks_count}; i++ )); do
  FQDN=$(yq eval ".[${i}].fqdn" ${CONFIG_FILE})
  DST_FQDN=$(yq eval ".[${i}].dst_fqdn" ${CONFIG_FILE})
  SERVICE_NAME=$(yq eval ".[${i}].service_name" ${CONFIG_FILE})
  NAMESPACE=$(yq eval ".[${i}].namespace" ${CONFIG_FILE})
  ENDPOINT=$(yq eval ".[${i}].endpoint" ${CONFIG_FILE})

  [[ -z ${FQDN} || ${FQDN} == "null" ]] && error_exit "FQDN is null or missing in block ${i}"
  [[ -z ${DST_FQDN} || ${DST_FQDN} == "null" ]] && error_exit "DST_FQDN is null or missing in block ${i}"
  [[ -z ${SERVICE_NAME} || ${SERVICE_NAME} == "null" ]] && error_exit "SERVICE_NAME is null or missing in block ${i}"
  [[ -z ${NAMESPACE} || ${NAMESPACE} == "null" ]] && error_exit "NAMESPACE is null or missing in block ${i}"
  [[ -z ${ENDPOINT} || ${ENDPOINT} == "null" ]] && error_exit "ENDPOINT is null or missing in block ${i}"

  OVERLAY_DST="${OVERLAY_ROOT}/${FQDN}"
  mkdir -p ${OVERLAY_DST}

  kustomization_file
  ingress_patch_file
  service_patch_file
done

if [[ $BUILD_ONLY = 'false' ]]
then
  if [[ $DEPLOY_ALL = 'true' ]]
  then
    deploy_all_overlays
  elif [[ $INTERACTIVE = 'true' ]]
  then
    deploy_interactive_overlay
  elif [[ -n $DEPLOY_SPECIFIC ]]
  then
    deploy_specific_overlay
  else
    usage
  fi
fi
