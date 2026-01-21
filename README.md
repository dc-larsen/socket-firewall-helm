# Socket Firewall Helm Chart

Kubernetes Helm chart for deploying the Socket.dev Registry Firewall. Blocks vulnerable packages before they reach your cluster.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Socket.dev API token (get one at https://socket.dev)

## Installation

```bash
# Add your Socket API token
export SOCKET_API_TOKEN="your-token-here"

# Install the chart
helm install socket-firewall . \
  --set socket.apiToken=$SOCKET_API_TOKEN \
  --set registries.npm.domains[0]=npm.internal.example.com
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `socket.apiToken` | Socket.dev API token (required) | `""` |
| `socket.existingSecret` | Use existing secret for API token | `""` |
| `registries.npm.enabled` | Enable npm registry proxy | `true` |
| `registries.npm.domains` | Domains to proxy for npm | `["npm.firewall.local"]` |
| `registries.pypi.enabled` | Enable PyPI registry proxy | `false` |
| `registries.maven.enabled` | Enable Maven registry proxy | `false` |
| `tls.generateSelfSigned` | Auto-generate self-signed certs | `true` |
| `tls.existingSecret` | Use existing TLS secret | `""` |

See `values.yaml` for all available options.

## Local Testing (Orbstack)

1. Start the Orbstack Kubernetes cluster
2. Install the chart with test values:

```bash
# Get your Socket API token from https://socket.dev
export SOCKET_API_TOKEN="your-token"

# Install with test values
helm install socket-firewall . \
  -f ci/test-values.yaml \
  --set socket.apiToken=$SOCKET_API_TOKEN

# Wait for pod to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=socket-firewall \
  --timeout=120s

# Port forward
kubectl port-forward svc/socket-firewall 8443:443 &

# Add hosts entry
echo "127.0.0.1 npm.firewall.local" | sudo tee -a /etc/hosts

# Extract CA cert (for trusting self-signed cert)
POD=$(kubectl get pod -l app.kubernetes.io/name=socket-firewall -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /etc/nginx/ssl/ca.crt > /tmp/socket-ca.crt

# Test health
curl -k --resolve npm.firewall.local:8443:127.0.0.1 \
  https://npm.firewall.local:8443/health

# Test blocking (form-data@2.3.3 should be blocked)
mkdir /tmp/test-npm && cd /tmp/test-npm
npm init -y
npm config set registry https://npm.firewall.local:8443/
npm config set strict-ssl false
npm install form-data@2.3.3  # Should fail with 403
```

## Validating Package Blocking

The firewall blocks packages based on Socket.dev security analysis. To verify:

```bash
# This should be BLOCKED (known vulnerable)
npm install form-data@2.3.3

# This should SUCCEED (safe package)
npm install lodash@4.17.21
```

## Using with Package Managers

### npm/yarn/pnpm

```bash
npm config set registry https://npm.firewall.local/
npm config set cafile /path/to/socket-ca.crt  # If using self-signed
```

### pip (PyPI)

```bash
pip config set global.index-url https://pypi.firewall.local/simple/
pip config set global.cert /path/to/socket-ca.crt
```

## Uninstall

```bash
helm uninstall socket-firewall
```
