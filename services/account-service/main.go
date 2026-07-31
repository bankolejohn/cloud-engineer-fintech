package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Account represents a financial account
type Account struct {
	ID        string    `json:"id"`
	OwnerName string    `json:"owner_name"`
	Balance   float64   `json:"balance"`
	Currency  string    `json:"currency"`
	Status    string    `json:"status"` // active, frozen, closed
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// TransferRequest represents an internal transfer between accounts
type TransferRequest struct {
	FromAccountID string  `json:"from_account_id"`
	ToAccountID   string  `json:"to_account_id"`
	Amount        float64 `json:"amount"`
	Currency      string  `json:"currency"`
}

// In-memory store (replaced by MySQL/ProxySQL in production)
var (
	accounts   = make(map[string]*Account)
	accountsMu sync.RWMutex
)

// Prometheus metrics
var (
	accountsTotal = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "finflow_accounts_total",
		Help: "Total number of accounts",
	})

	transfersTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "finflow_transfers_total",
			Help: "Total number of transfers",
		},
		[]string{"status", "currency"},
	)

	accountBalance = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "finflow_account_balance",
			Help:    "Distribution of account balances",
			Buckets: []float64{100, 1000, 10000, 100000, 1000000},
		},
		[]string{"currency"},
	)
)

func init() {
	prometheus.MustRegister(accountsTotal)
	prometheus.MustRegister(transfersTotal)
	prometheus.MustRegister(accountBalance)

	// Seed demo accounts
	seedAccounts()
}

func seedAccounts() {
	demoAccounts := []Account{
		{ID: "acct-001", OwnerName: "John Doe", Balance: 50000.00, Currency: "NGN", Status: "active"},
		{ID: "acct-002", OwnerName: "Jane Smith", Balance: 125000.00, Currency: "NGN", Status: "active"},
		{ID: "acct-003", OwnerName: "Bob Johnson", Balance: 5000.00, Currency: "USD", Status: "active"},
		{ID: "acct-004", OwnerName: "Alice Brown", Balance: 750000.00, Currency: "NGN", Status: "active"},
	}

	for i := range demoAccounts {
		acct := demoAccounts[i]
		acct.CreatedAt = time.Now().Add(-30 * 24 * time.Hour)
		acct.UpdatedAt = time.Now()
		accounts[acct.ID] = &acct
	}
	accountsTotal.Set(float64(len(accounts)))
}

func main() {
	port := getEnv("PORT", "8082")
	serviceName := getEnv("SERVICE_NAME", "account-service")

	log.Printf("Starting %s on port %s", serviceName, port)

	router := mux.NewRouter()

	// Health
	router.HandleFunc("/health", healthHandler).Methods("GET")
	router.HandleFunc("/ready", readyHandler).Methods("GET")

	// Account API
	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/accounts", createAccountHandler).Methods("POST")
	api.HandleFunc("/accounts/{id}", getAccountHandler).Methods("GET")
	api.HandleFunc("/accounts", listAccountsHandler).Methods("GET")
	api.HandleFunc("/accounts/{id}/balance", getBalanceHandler).Methods("GET")
	api.HandleFunc("/transfers", transferHandler).Methods("POST")

	// Metrics
	router.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func createAccountHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		OwnerName string  `json:"owner_name"`
		Currency  string  `json:"currency"`
		Balance   float64 `json:"initial_balance"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.OwnerName == "" {
		respondError(w, http.StatusBadRequest, "owner_name is required")
		return
	}

	account := &Account{
		ID:        "acct-" + uuid.New().String()[:8],
		OwnerName: req.OwnerName,
		Balance:   req.Balance,
		Currency:  req.Currency,
		Status:    "active",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	accountsMu.Lock()
	accounts[account.ID] = account
	accountsTotal.Inc()
	accountsMu.Unlock()

	accountBalance.WithLabelValues(account.Currency).Observe(account.Balance)

	log.Printf("Account created: id=%s owner=%s", account.ID, account.OwnerName)
	respondJSON(w, http.StatusCreated, account)
}

func getAccountHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	accountsMu.RLock()
	account, exists := accounts[id]
	accountsMu.RUnlock()

	if !exists {
		respondError(w, http.StatusNotFound, "Account not found")
		return
	}

	respondJSON(w, http.StatusOK, account)
}

func listAccountsHandler(w http.ResponseWriter, r *http.Request) {
	accountsMu.RLock()
	result := make([]*Account, 0, len(accounts))
	for _, acct := range accounts {
		result = append(result, acct)
	}
	accountsMu.RUnlock()

	respondJSON(w, http.StatusOK, result)
}

func getBalanceHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	accountsMu.RLock()
	account, exists := accounts[id]
	accountsMu.RUnlock()

	if !exists {
		respondError(w, http.StatusNotFound, "Account not found")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"account_id": account.ID,
		"balance":    account.Balance,
		"currency":   account.Currency,
	})
}

func transferHandler(w http.ResponseWriter, r *http.Request) {
	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.Amount <= 0 {
		respondError(w, http.StatusBadRequest, "Amount must be greater than zero")
		return
	}

	accountsMu.Lock()
	defer accountsMu.Unlock()

	fromAcct, fromExists := accounts[req.FromAccountID]
	toAcct, toExists := accounts[req.ToAccountID]

	if !fromExists || !toExists {
		transfersTotal.WithLabelValues("failed", req.Currency).Inc()
		respondError(w, http.StatusNotFound, "One or both accounts not found")
		return
	}

	if fromAcct.Status != "active" || toAcct.Status != "active" {
		transfersTotal.WithLabelValues("failed", req.Currency).Inc()
		respondError(w, http.StatusBadRequest, "Both accounts must be active")
		return
	}

	if fromAcct.Balance < req.Amount {
		transfersTotal.WithLabelValues("failed", req.Currency).Inc()
		respondError(w, http.StatusBadRequest, "Insufficient balance")
		return
	}

	// Execute transfer
	fromAcct.Balance -= req.Amount
	toAcct.Balance += req.Amount
	fromAcct.UpdatedAt = time.Now()
	toAcct.UpdatedAt = time.Now()

	transfersTotal.WithLabelValues("completed", req.Currency).Inc()

	log.Printf("Transfer completed: %s -> %s amount=%.2f %s",
		req.FromAccountID, req.ToAccountID, req.Amount, req.Currency)

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"status":       "completed",
		"from_balance": fromAcct.Balance,
		"to_balance":   toAcct.Balance,
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, map[string]interface{}{
		"error":   message,
		"success": false,
	})
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
