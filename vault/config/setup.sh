#!/bin/bash
# ==============================================================================
# Vault Configuration Script
# Sets up secret engines, auth methods, policies, and roles
# Run after Vault is initialized and unsealed
# ==============================================================================

set -euo pipefail

export VAULT_ADDR="https://vault.vault.svc.cluster.local:8200"

echo "=== FinFlow Vault Configuration ==="

# ============================================================
# 1. Enable Secret Engines
# ============================================================
echo "[1/7] Enabling secret engines..."

# KV v2 for static secrets
vault secrets enable -path=secret kv-v2

# Database secret engine (dynamic credentials)
vault secrets enable database

# Transit (encryption as a service)
vault secrets enable transit

# PKI (certificate management)
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# AWS dynamic secrets
vault secrets enable -path=aws aws

# GCP dynamic secrets
vault secrets enable -path=gcp gcp

# ============================================================
# 2. Configure Database Secret Engine (MySQL)
# ============================================================
echo "[2/7] Configuring database engine..."

vault write database/config/finflow-mysql \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(finflow-mysql.internal:3306)/" \
    allowed_roles="transaction-api,payment-processor,account-service,fraud-detection-readonly" \
    username="vault_admin" \
    password="INITIAL_PASSWORD"

# Dynamic role: transaction-api (read-write, 1 hour TTL)
vault write database/roles/transaction-api \
    db_name=finflow-mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE ON finflow.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# Dynamic role: payment-processor (read-write)
vault write database/roles/payment-processor \
    db_name=finflow-mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE ON finflow.transactions TO '{{name}}'@'%'; GRANT SELECT, UPDATE ON finflow.accounts TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# Dynamic role: account-service (read-write on accounts)
vault write database/roles/account-service \
    db_name=finflow-mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE ON finflow.accounts TO '{{name}}'@'%'; GRANT SELECT ON finflow.transactions TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# Dynamic role: fraud-detection (read-only)
vault write database/roles/fraud-detection-readonly \
    db_name=finflow-mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON finflow.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# ============================================================
# 3. Configure Transit Engine (Encryption)
# ============================================================
echo "[3/7] Configuring transit engine..."

# Encryption key for transaction data (PII)
vault write -f transit/keys/finflow-transactions \
    type=aes256-gcm96 \
    auto_rotate_period=90d

# Encryption key for account data
vault write -f transit/keys/finflow-accounts \
    type=aes256-gcm96 \
    auto_rotate_period=90d

# ============================================================
# 4. Configure PKI Engine
# ============================================================
echo "[4/7] Configuring PKI engine..."

# Generate root CA
vault write -format=json pki/root/generate/internal \
    common_name="FinFlow Internal CA" \
    ttl=87600h > /tmp/ca.json

# Configure CA URLs
vault write pki/config/urls \
    issuing_certificates="https://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
    crl_distribution_points="https://vault.vault.svc.cluster.local:8200/v1/pki/crl"

# Service certificate role
vault write pki/roles/finflow-services \
    allowed_domains="finflow.svc.cluster.local,finflow.io" \
    allow_subdomains=true \
    max_ttl=720h \
    generate_lease=true

# ============================================================
# 5. Configure Kubernetes Auth
# ============================================================
echo "[5/7] Configuring Kubernetes auth..."

vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Create roles for each service
for service in transaction-api payment-processor account-service fraud-detection notification-service; do
    vault write auth/kubernetes/role/${service} \
        bound_service_account_names=${service} \
        bound_service_account_namespaces=finflow \
        policies=finflow-${service} \
        ttl=1h
done

# ============================================================
# 6. Write Policies
# ============================================================
echo "[6/7] Writing policies..."

vault policy write finflow-transaction-api vault/policies/finflow-services.hcl
vault policy write finflow-payment-processor vault/policies/finflow-services.hcl
vault policy write finflow-account-service vault/policies/finflow-services.hcl
vault policy write finflow-fraud-detection vault/policies/finflow-services.hcl
vault policy write finflow-notification-service vault/policies/finflow-services.hcl

# ============================================================
# 7. Store Initial Secrets
# ============================================================
echo "[7/7] Storing initial secrets..."

vault kv put secret/finflow/shared \
    kafka-bootstrap-servers="finflow-kafka-kafka-bootstrap.finflow-kafka.svc.cluster.local:9092"

vault kv put secret/finflow/transaction-api \
    api-key="GENERATED_AT_DEPLOY_TIME"

vault kv put secret/finflow/notification-service \
    sendgrid-api-key="CONFIGURE_ME" \
    twilio-account-sid="CONFIGURE_ME" \
    twilio-auth-token="CONFIGURE_ME"

# Enable audit logging
vault audit enable file file_path=/vault/audit/vault-audit.log

echo ""
echo "=== Vault configuration complete ==="
echo "Verify: vault status"
echo "Check secrets: vault kv list secret/finflow/"
echo "Check database: vault read database/creds/transaction-api"
