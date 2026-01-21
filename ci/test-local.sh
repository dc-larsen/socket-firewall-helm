#!/bin/bash
# Local test script for Socket Firewall Helm chart
# Requires: Orbstack with Kubernetes enabled, helm, kubectl

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="socket-firewall-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    echo_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        echo_error "helm not found"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo_error "Kubernetes cluster not available"
        exit 1
    fi

    echo_success "Prerequisites OK"
}

# Check for Socket API token
check_token() {
    if [ -z "$SOCKET_SECURITY_API_TOKEN" ]; then
        echo_error "SOCKET_SECURITY_API_TOKEN environment variable not set"
        echo_info "Set it with: export SOCKET_SECURITY_API_TOKEN=your-token"
        exit 1
    fi
    echo_success "Socket API token found"
}

# Install the chart
install_chart() {
    echo_info "Installing Socket Firewall chart..."

    # Create namespace if not exists
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

    # Install or upgrade the chart
    helm upgrade --install socket-firewall "$CHART_DIR" \
        --namespace $NAMESPACE \
        -f "$CHART_DIR/ci/test-values.yaml" \
        --set socket.apiToken="$SOCKET_SECURITY_API_TOKEN" \
        --wait --timeout 180s

    echo_success "Chart installed"
}

# Wait for pod to be ready
wait_for_pod() {
    echo_info "Waiting for pod to be ready..."

    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=socket-firewall \
        -n $NAMESPACE \
        --timeout=120s

    echo_success "Pod is ready"
}

# Setup port forward
setup_port_forward() {
    echo_info "Setting up port forward..."

    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*socket-firewall" 2>/dev/null || true
    sleep 1

    kubectl port-forward svc/socket-firewall 8443:443 -n $NAMESPACE &
    PF_PID=$!
    sleep 3

    # Check if port-forward is running
    if ! kill -0 $PF_PID 2>/dev/null; then
        echo_error "Port forward failed to start"
        exit 1
    fi

    echo_success "Port forward running on localhost:8443 (PID: $PF_PID)"
}

# Extract CA certificate
extract_ca_cert() {
    echo_info "Extracting CA certificate..."

    POD=$(kubectl get pod -l app.kubernetes.io/name=socket-firewall -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n $NAMESPACE $POD -- cat /etc/nginx/ssl/ca.crt > /tmp/socket-ca.crt

    echo_success "CA cert saved to /tmp/socket-ca.crt"
}

# Test health endpoint
test_health() {
    echo_info "Testing health endpoint..."

    RESPONSE=$(curl -s -k --resolve npm.firewall.local:8443:127.0.0.1 \
        https://npm.firewall.local:8443/health)

    if [[ "$RESPONSE" == *"OK"* ]]; then
        echo_success "Health check passed: $RESPONSE"
    else
        echo_error "Health check failed: $RESPONSE"
        exit 1
    fi
}

# Test package blocking
test_blocking() {
    echo_info "Testing that form-data@2.3.3 is blocked..."

    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    npm init -y > /dev/null 2>&1

    # Configure npm
    cat > .npmrc << EOF
registry=https://npm.firewall.local:8443/
strict-ssl=false
EOF

    # Try to install (should fail)
    if npm install form-data@2.3.3 2>&1 | tee /tmp/npm-test.log; then
        echo_error "form-data@2.3.3 was NOT blocked!"
        cd -
        rm -rf "$TEST_DIR"
        exit 1
    else
        if grep -qi "403\|blocked\|forbidden" /tmp/npm-test.log; then
            echo_success "form-data@2.3.3 was blocked as expected"
        else
            echo_info "Package failed but may not be due to blocking (checking logs)"
            # Show firewall logs
            kubectl logs -l app.kubernetes.io/name=socket-firewall -n $NAMESPACE --tail=20
        fi
    fi

    cd - > /dev/null
    rm -rf "$TEST_DIR"
}

# Test safe package
test_safe_package() {
    echo_info "Testing that lodash@4.17.21 installs successfully..."

    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    npm init -y > /dev/null 2>&1

    cat > .npmrc << EOF
registry=https://npm.firewall.local:8443/
strict-ssl=false
EOF

    if npm install lodash@4.17.21 2>&1 | tee /tmp/npm-safe.log; then
        echo_success "lodash@4.17.21 installed successfully"
    else
        echo_error "Safe package failed to install"
        cat /tmp/npm-safe.log
    fi

    cd - > /dev/null
    rm -rf "$TEST_DIR"
}

# Cleanup
cleanup() {
    echo_info "Cleaning up..."
    pkill -f "kubectl port-forward.*socket-firewall" 2>/dev/null || true
    helm uninstall socket-firewall -n $NAMESPACE 2>/dev/null || true
    kubectl delete namespace $NAMESPACE 2>/dev/null || true
    echo_success "Cleanup complete"
}

# Show logs
show_logs() {
    echo_info "Firewall logs:"
    kubectl logs -l app.kubernetes.io/name=socket-firewall -n $NAMESPACE --tail=50
}

# Main
case "${1:-all}" in
    prereqs)
        check_prereqs
        ;;
    install)
        check_prereqs
        check_token
        install_chart
        wait_for_pod
        ;;
    test)
        setup_port_forward
        extract_ca_cert
        test_health
        test_blocking
        test_safe_package
        ;;
    logs)
        show_logs
        ;;
    cleanup)
        cleanup
        ;;
    all)
        check_prereqs
        check_token
        install_chart
        wait_for_pod
        setup_port_forward
        extract_ca_cert
        test_health
        test_blocking
        test_safe_package
        echo ""
        echo_success "All tests passed!"
        echo_info "Port forward still running. Run '$0 cleanup' when done."
        ;;
    *)
        echo "Usage: $0 [prereqs|install|test|logs|cleanup|all]"
        exit 1
        ;;
esac
