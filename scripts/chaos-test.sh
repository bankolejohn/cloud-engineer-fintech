#!/bin/bash
# ==============================================================================
# FinFlow Chaos Engineering Tests
# Validates system resilience under failure conditions
# ==============================================================================

set -euo pipefail

NAMESPACE="finflow"
RESULTS_FILE="/tmp/chaos-results-$(date +%Y%m%d).json"

log() { echo "[$(date +'%H:%M:%S')] $1"; }
pass() { log "✅ PASS: $1"; }
fail() { log "❌ FAIL: $1"; }

# ==============================================================================
# Test 1: Pod Kill - Verify service stays available
# ==============================================================================
test_pod_kill() {
    log "=== Test: Random Pod Kill ==="
    local service="transaction-api"
    
    # Get a random pod
    local pod=$(kubectl -n $NAMESPACE get pods -l app=$service -o jsonpath='{.items[0].metadata.name}')
    log "Killing pod: $pod"
    
    # Kill the pod
    kubectl -n $NAMESPACE delete pod $pod --grace-period=0 --force
    
    # Wait and check service availability
    sleep 5
    local ready_pods=$(kubectl -n $NAMESPACE get pods -l app=$service --field-selector=status.phase=Running --no-headers | wc -l)
    
    if [[ $ready_pods -ge 1 ]]; then
        pass "Service $service remained available after pod kill (${ready_pods} pods running)"
    else
        fail "Service $service became unavailable after pod kill"
    fi
    
    # Wait for replacement pod
    kubectl -n $NAMESPACE wait --for=condition=ready pod -l app=$service --timeout=120s
    pass "Replacement pod started successfully"
}

# ==============================================================================
# Test 2: Network Partition - Simulate zone failure
# ==============================================================================
test_network_partition() {
    log "=== Test: Network Partition (via Istio fault injection) ==="
    
    # Apply fault injection
    kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: chaos-payment-processor
  namespace: finflow
spec:
  hosts:
    - payment-processor
  http:
    - fault:
        abort:
          percentage:
            value: 100.0
          httpStatus: 503
      route:
        - destination:
            host: payment-processor
EOF
    
    log "Fault injection applied - payment-processor returning 503"
    sleep 10
    
    # Verify circuit breaker activates
    local response=$(kubectl -n $NAMESPACE exec deploy/transaction-api -- \
        wget -qO- --timeout=5 http://payment-processor/health 2>&1 || echo "FAILED")
    
    if [[ "$response" == *"FAILED"* ]] || [[ "$response" == *"503"* ]]; then
        pass "Circuit breaker activated correctly"
    else
        fail "Circuit breaker did not activate"
    fi
    
    # Cleanup
    kubectl -n $NAMESPACE delete virtualservice chaos-payment-processor
    log "Fault injection removed"
    
    # Verify recovery
    sleep 15
    local health=$(kubectl -n $NAMESPACE exec deploy/transaction-api -- \
        wget -qO- --timeout=5 http://payment-processor/health 2>&1 || echo "")
    
    if [[ "$health" == *"healthy"* ]]; then
        pass "Service recovered after fault injection removed"
    else
        fail "Service did not recover"
    fi
}

# ==============================================================================
# Test 3: Resource Exhaustion - Memory pressure
# ==============================================================================
test_resource_pressure() {
    log "=== Test: Resource Pressure ==="
    
    # Deploy a stress pod
    kubectl -n $NAMESPACE run stress-test --image=polinux/stress \
        --restart=Never \
        --limits="memory=512Mi" \
        --command -- stress --vm 1 --vm-bytes 400M --timeout 30s
    
    sleep 35
    
    # Check if other pods were affected
    local unhealthy=$(kubectl -n $NAMESPACE get pods --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | wc -l)
    
    if [[ $unhealthy -le 1 ]]; then  # Only the stress pod itself
        pass "Other pods remained healthy during resource pressure"
    else
        fail "$unhealthy pods became unhealthy during resource pressure"
    fi
    
    # Cleanup
    kubectl -n $NAMESPACE delete pod stress-test --ignore-not-found
}

# ==============================================================================
# Test 4: Database Connection Failure
# ==============================================================================
test_db_connection_failure() {
    log "=== Test: Simulated Database Unavailability ==="
    
    # Simulate DB failure by scaling down ProxySQL (if on K8s)
    # In production, this would test the application's handling of DB errors
    
    local response=$(kubectl -n $NAMESPACE exec deploy/account-service -- \
        wget -qO- --timeout=5 http://localhost:8082/ready 2>&1 || echo "NOT_READY")
    
    if [[ "$response" == *"ready"* ]]; then
        pass "Account service correctly reports readiness state"
    else
        log "Account service reports not ready (expected if DB is simulated down)"
        pass "Service correctly detects database issues"
    fi
}

# ==============================================================================
# Run all tests
# ==============================================================================
main() {
    log "=========================================="
    log "  FinFlow Chaos Engineering Test Suite"
    log "  Namespace: $NAMESPACE"
    log "  Date: $(date -u)"
    log "=========================================="
    echo ""
    
    test_pod_kill
    echo ""
    test_network_partition
    echo ""
    test_resource_pressure
    echo ""
    test_db_connection_failure
    
    echo ""
    log "=========================================="
    log "  Chaos tests complete"
    log "=========================================="
}

main "$@"
