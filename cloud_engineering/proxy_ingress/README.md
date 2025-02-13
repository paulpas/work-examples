## Overview

Deploying Proxy configurations to access private endpoints.

This repository contains a bash script that helps set up a Kubernetes environment based on a `params.yaml` configuration file. It processes parameters, generates the destination path, creates `kustomization.yaml`, `ingress-patch.yaml`, and `service-patch.yaml`.

## Prerequisites

Ensure you have `bash`, `kubectl`, and `yq` installed on your system. The script needs them to run.

Make sure you are authenticated to a Kubernetes cluster with proxying functionality intended with an NGINX Ingress controller.

## params.yaml

This is the configuration file, based on which, the script sets up your Kubernetes environment. For example:

```yaml
- fqdn: "foo.com"
  dst_fqdn: "foo.external.com"
  service_name: "service-foo"
  namespace: "nginx-internal"
  endpoint: "internal"
```

Each block in the configuration file indicates a separate overlay setting and represents a site setup.

- `fqdn`: This is the domain name for the site.
- `dst_fqdn`: This is the destination domain that the service proxies to outside the cluster.
- `service_name`: This is the name of the Kubernetes Service.
- `namespace`: The namespace in Kubernetes where the service should be deployed.
- `endpoint`: This is where an internal or externally facing endpoint is defined.

To add a new site, simple append another block with the above fields in the `params.yaml` file.

## Running Script

You can execute the script using:

```bash
bash script.sh
```

The script provides several options:

- **Interactive mode (-i, --interactive)**: Asks you to choose which overlay to deploy interactively.
```bash
./build.sh -i
1) abcd.foo.com
2) xyz.foo.com
Please enter your choice (ctrl-C to exit):
```

- **Build only mode (-b, --build)**: Builds the overlays but does not deploy them.
```bash
bash script.sh -b
```

- **Deploy all (--deploy-all)**: Builds and deploys all overlays.
```bash
bash script.sh --deploy-all
```

- **Deploy specific overlay (-d, --deploy)**: Builds and deploys a specific overlay.
```bash
bash script.sh -d overlay_name
```

- **Help (-h, --help)**: Displays the usage information.
```bash
bash script.sh -h
```

## Manual Deployment

To manually apply an overlay with kustomize:

```bash
kubectl kustomize overlay/overlay_name | kubectl apply -f -
```

Please replace `overlay_name` with your overlay's name.

