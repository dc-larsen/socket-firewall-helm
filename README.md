# Socket Firewall Helm Chart

Kubernetes Helm chart for deploying the [Socket.dev Registry Firewall](https://github.com/SocketDev/socket-nginx-firewall). Blocks vulnerable and malicious packages before they reach your cluster.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- Socket.dev API token ([get one here](https://socket.dev))

## Quick Start

```bash
# Add your Socket API token
export SOCKET_API_TOKEN="your-token-here"

# Install the chart
helm install socket-firewall . \
  --set socket.apiToken=$SOCKET_API_TOKEN \
  --set registries.npm.domains[0]=npm.internal.example.com

# Verify deployment
kubectl get pods -l app.kubernetes.io/name=socket-firewall
```

## Configuration

### Required

| Parameter | Description |
|-----------|-------------|
| `socket.apiToken` | Socket.dev API token |

### Registry Configuration

Enable registries and set custom domains for proxying:

```yaml
registries:
  npm:
    enabled: true
    domains:
      - npm.internal.example.com
  pypi:
    enabled: true
    domains:
      - pypi.internal.example.com
  maven:
    enabled: false
  rubygems:
    enabled: false
  cargo:
    enabled: false
```

### All Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Docker image | `socketdev/socket-registry-firewall` |
| `image.tag` | Image tag | `latest` |
| `replicaCount` | Number of replicas | `1` |
| `socket.apiToken` | Socket API token | `""` |
| `socket.existingSecret` | Use existing secret | `""` |
| `registries.npm.enabled` | Enable npm proxy | `true` |
| `registries.npm.domains` | npm proxy domains | `["npm.firewall.local"]` |
| `registries.pypi.enabled` | Enable PyPI proxy | `false` |
| `registries.maven.enabled` | Enable Maven proxy | `false` |
| `tls.generateSelfSigned` | Generate self-signed certs | `true` |
| `tls.existingSecret` | Use existing TLS secret | `""` |
| `service.type` | Service type | `ClusterIP` |
| `resources.limits.cpu` | CPU limit | `1` |
| `resources.limits.memory` | Memory limit | `768Mi` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |
| `podSecurityContext` | Pod security context | `{}` |
| `securityContext` | Container security context | `{}` |

See [values.yaml](values.yaml) for all options.

## Using with Package Managers

### npm / yarn / pnpm

```bash
# Point npm to your firewall proxy
npm config set registry https://npm.internal.example.com/

# If using self-signed certificates
npm config set strict-ssl false
# Or trust the CA certificate
npm config set cafile /path/to/socket-ca.crt
```

### pip (PyPI)

```bash
pip config set global.index-url https://pypi.internal.example.com/simple/
pip config set global.trusted-host pypi.internal.example.com
```

### Maven

Add to `~/.m2/settings.xml`:
```xml
<mirrors>
  <mirror>
    <id>socket-central</id>
    <url>https://maven.internal.example.com/</url>
    <mirrorOf>central</mirrorOf>
  </mirror>
</mirrors>
```

## TLS Configuration

### Self-Signed (Default)

The chart generates self-signed certificates automatically. Extract the CA cert:

```bash
POD=$(kubectl get pod -l app.kubernetes.io/name=socket-firewall -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /etc/nginx/ssl/ca.crt > socket-ca.crt
```

### Existing Certificate

```yaml
tls:
  generateSelfSigned: false
  existingSecret: my-tls-secret  # must contain tls.crt and tls.key
```

### cert-manager

Create a Certificate resource and reference the secret:

```yaml
tls:
  generateSelfSigned: false
  existingSecret: socket-firewall-tls
```

## Using an Existing Secret for API Token

```bash
# Create secret
kubectl create secret generic socket-api-token \
  --from-literal=SOCKET_SECURITY_API_TOKEN=your-token

# Reference in values
helm install socket-firewall . \
  --set socket.existingSecret=socket-api-token
```

## Uninstall

```bash
helm uninstall socket-firewall
```

## Support

- [Socket.dev Documentation](https://docs.socket.dev)
- [Socket Firewall Source](https://github.com/SocketDev/socket-nginx-firewall)
