#!/bin/bash
# ==============================================================================
# FinFlow Disaster Recovery Failover Script
# Orchestrates failover from primary (GCP) to secondary (AWS) cluster
# ==============================================================================

set -euo pipefail

# Configuration
PRIMARY_CLUSTER="gke_finflow-prod_us-central1_finflow-prod-gke"
SECONDARY_CLUSTER="arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/finflow-prod-eks"
DNS_ZONE="finflow.io"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
LOG_FILE="/var/log/finflow/failover-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

notify_slack() {
    local message="$1"
    local color="${2:-warning}"
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${message}\"}]}" \
            > /dev/null 2>&1 || true
    fi
}

check_cluster_health() {
    local cluster="$1"
    local context="$2"
    
    log "Checking health of cluster: $cluster"
    if kubectl --context="$context" get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Main Failover Logic
# ==============================================================================

main() {
    local target="${1:-}"
    local confirm="${2:-}"
    
    if [[ "$target" != "--target" ]] || [[ -z "${2:-}" ]]; then
        echo "Usage: $0 --target <aws|gcp> --confirm"
        echo ""
        echo "Options:"
        echo "  --target aws    Failover to AWS secondary"
        echo "  --target gcp    Failback to GCP primary"
        echo "  --confirm       Skip confirmation prompt"
        exit 1
    fi
    
    local target_cloud="${2}"
    local skip_confirm="${3:-}"
    
    log "${YELLOW}=== FinFlow Disaster Recovery Failover ===${NC}"
    log "Target: ${target_cloud}"
    log "Time: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    
    # Confirmation
    if [[ "$skip_confirm" != "--confirm" ]]; then
        echo ""
        echo -e "${RED}WARNING: This will perform a production failover!${NC}"
        echo "Target cloud: ${target_cloud}"
        read -p "Type 'FAILOVER' to confirm: " confirmation
        if [[ "$confirmation" != "FAILOVER" ]]; then
            log "Failover cancelled by user"
            exit 1
        fi
    fi
    
    notify_slack ":rotating_light: FAILOVER INITIATED to ${target_cloud} by $(whoami)" "danger"
    
    if [[ "$target_cloud" == "aws" ]]; then
        failover_to_aws
    elif [[ "$target_cloud" == "gcp" ]]; then
        failback_to_gcp
    fi
}

failover_to_aws() {
    log "${YELLOW}Step 1/6: Verifying AWS cluster health...${NC}"
    if ! check_cluster_health "aws-secondary" "$SECONDARY_CLUSTER"; then
        log "${RED}ERROR: AWS cluster is not healthy! Aborting failover.${NC}"
        notify_slack ":x: Failover ABORTED - AWS cluster unhealthy" "danger"
        exit 1
    fi
    log "${GREEN}AWS cluster is healthy${NC}"
    
    log "${YELLOW}Step 2/6: Scaling up AWS workloads...${NC}"
    kubectl --context="$SECONDARY_CLUSTER" -n finflow scale deployment \
        transaction-api payment-processor account-service fraud-detection notification-service \
        --replicas=3
    
    log "${YELLOW}Step 3/6: Promoting AWS RDS replica...${NC}"
    aws rds promote-read-replica \
        --db-instance-identifier finflow-prod-mysql-replica \
        --region us-east-1 || log "RDS promotion may already be in progress"
    
    log "${YELLOW}Step 4/6: Updating DNS records...${NC}"
    # Update Route53 to point to AWS
    aws route53 change-resource-record-sets \
        --hosted-zone-id Z1234567890 \
        --change-batch '{
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "api.finflow.io",
                    "Type": "A",
                    "AliasTarget": {
                        "HostedZoneId": "Z35SXDOTRQ7X7K",
                        "DNSName": "aws-nlb-finflow.us-east-1.elb.amazonaws.com",
                        "EvaluateTargetHealth": true
                    }
                }
            }]
        }' || log "DNS update may require manual intervention"
    
    log "${YELLOW}Step 5/6: Verifying service health on AWS...${NC}"
    sleep 30  # Wait for DNS propagation and pod startup
    
    local max_retries=10
    local retry=0
    while [[ $retry -lt $max_retries ]]; do
        if kubectl --context="$SECONDARY_CLUSTER" -n finflow get pods | grep -q "Running"; then
            log "${GREEN}Services are running on AWS${NC}"
            break
        fi
        retry=$((retry + 1))
        log "Waiting for pods... (attempt $retry/$max_retries)"
        sleep 10
    done
    
    log "${YELLOW}Step 6/6: Scaling down GCP workloads...${NC}"
    kubectl --context="$PRIMARY_CLUSTER" -n finflow scale deployment \
        transaction-api payment-processor account-service fraud-detection notification-service \
        --replicas=0 2>/dev/null || log "GCP cluster may be unreachable (expected)"
    
    log "${GREEN}=== Failover to AWS complete ===${NC}"
    log "RTO achieved: $(date)"
    notify_slack ":white_check_mark: Failover to AWS COMPLETE. Services running on AWS us-east-1." "good"
}

failback_to_gcp() {
    log "${YELLOW}Initiating failback to GCP primary...${NC}"
    
    log "Step 1: Verify GCP cluster health"
    if ! check_cluster_health "gcp-primary" "$PRIMARY_CLUSTER"; then
        log "${RED}GCP cluster not ready for failback${NC}"
        exit 1
    fi
    
    log "Step 2: Scale up GCP workloads"
    kubectl --context="$PRIMARY_CLUSTER" -n finflow scale deployment \
        transaction-api payment-processor account-service fraud-detection notification-service \
        --replicas=3
    
    log "Step 3: Wait for pods to be ready"
    kubectl --context="$PRIMARY_CLUSTER" -n finflow wait --for=condition=ready pod \
        -l app.kubernetes.io/part-of=finflow --timeout=300s
    
    log "Step 4: Update DNS back to GCP"
    # DNS update to point back to GCP
    gcloud dns record-sets update api.finflow.io. \
        --zone=finflow-zone \
        --type=A \
        --rrdatas="GCP_LB_IP" \
        --ttl=60 || log "DNS update needs manual intervention"
    
    log "Step 5: Scale down AWS workloads"
    kubectl --context="$SECONDARY_CLUSTER" -n finflow scale deployment \
        transaction-api payment-processor account-service fraud-detection notification-service \
        --replicas=1  # Keep warm standby
    
    log "${GREEN}=== Failback to GCP complete ===${NC}"
    notify_slack ":house: Failback to GCP COMPLETE. Primary region restored." "good"
}

# Run
main "$@"
