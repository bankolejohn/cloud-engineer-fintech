# ==============================================================================
# Vault Policies - Per-Service Access Control
# ==============================================================================

# --- Transaction API Policy ---
path "secret/data/finflow/transaction-api/*" {
  capabilities = ["read", "list"]
}

path "database/creds/transaction-api" {
  capabilities = ["read"]
}

path "transit/encrypt/finflow-transactions" {
  capabilities = ["update"]
}

path "transit/decrypt/finflow-transactions" {
  capabilities = ["update"]
}

# --- Payment Processor Policy ---
path "secret/data/finflow/payment-processor/*" {
  capabilities = ["read", "list"]
}

path "database/creds/payment-processor" {
  capabilities = ["read"]
}

path "transit/encrypt/finflow-transactions" {
  capabilities = ["update"]
}

# --- Account Service Policy ---
path "secret/data/finflow/account-service/*" {
  capabilities = ["read", "list"]
}

path "database/creds/account-service" {
  capabilities = ["read"]
}

# --- Fraud Detection Policy ---
path "secret/data/finflow/fraud-detection/*" {
  capabilities = ["read", "list"]
}

path "database/creds/fraud-detection-readonly" {
  capabilities = ["read"]
}

# --- Notification Service Policy ---
path "secret/data/finflow/notification-service/*" {
  capabilities = ["read", "list"]
}

# --- Shared PKI (all services can request certificates) ---
path "pki/issue/finflow-services" {
  capabilities = ["create", "update"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}
