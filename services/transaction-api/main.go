package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Transaction represents a payment transaction
type Transaction struct {
	ID              string    `json:"id"`
	SenderAccount   string    `json:"sender_account"`
	ReceiverAccount string    `json:"receiver_account"`
	Amount          float64   `json:"amount"`
	Currency        string    `json:"currency"`
	Type            string    `json:"type"` // transfer, deposit, withdrawal
	Status          string    `json:"status"`
	Description     string    `json:"description"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// TransactionRequest is the API request payload
type TransactionRequest struct {
	SenderAccount   string  `json:"sender_account"`
	ReceiverAccount string  `json:"receiver_account"`
	Amount          float64 `json:"amount"`
	Currency        string  `json:"currency"`
	Type            string  `json:"type"`
	Description     string  `json:"description"`
}

// APIResponse wraps all API responses
type APIResponse struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// Prometheus metrics
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "finflow_http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "finflow_http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint"},
	)

	transactionsCreated = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "finflow_transactions_created_total",
			Help: "Total number of transactions created",
		},
		[]string{"type", "currency"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(transactionsCreated)
}

func main() {
	port := getEnv("PORT", "8080")
	serviceName := getEnv("SERVICE_NAME", "transaction-api")

	log.Printf("Starting %s on port %s", serviceName, port)

	router := mux.NewRouter()

	// Health endpoints
	router.HandleFunc("/health", healthHandler).Methods("GET")
	router.HandleFunc("/ready", readyHandler).Methods("GET")

	// API v1 routes
	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/transactions", createTransactionHandler).Methods("POST")
	api.HandleFunc("/transactions/{id}", getTransactionHandler).Methods("GET")
	api.HandleFunc("/transactions", listTransactionsHandler).Methods("GET")
	api.HandleFunc("/transactions/{id}/status", updateTransactionStatusHandler).Methods("PATCH")

	// Metrics endpoint
	router.Handle("/metrics", promhttp.Handler())

	// Apply middleware
	router.Use(loggingMiddleware)
	router.Use(metricsMiddleware)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced shutdown: %v", err)
	}
	log.Println("Server stopped")
}

func createTransactionHandler(w http.ResponseWriter, r *http.Request) {
	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid request body",
		})
		return
	}

	// Validate request
	if req.Amount <= 0 {
		respondJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Amount must be greater than zero",
		})
		return
	}

	if req.SenderAccount == "" || req.ReceiverAccount == "" {
		respondJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Sender and receiver accounts are required",
		})
		return
	}

	// Create transaction
	txn := Transaction{
		ID:              uuid.New().String(),
		SenderAccount:   req.SenderAccount,
		ReceiverAccount: req.ReceiverAccount,
		Amount:          req.Amount,
		Currency:        req.Currency,
		Type:            req.Type,
		Status:          "pending",
		Description:     req.Description,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	// TODO: Publish to Kafka topic "transactions.created"
	// TODO: Store in database via account-service

	transactionsCreated.WithLabelValues(txn.Type, txn.Currency).Inc()

	log.Printf("Transaction created: id=%s type=%s amount=%.2f %s",
		txn.ID, txn.Type, txn.Amount, txn.Currency)

	respondJSON(w, http.StatusCreated, APIResponse{
		Success: true,
		Data:    txn,
	})
}

func getTransactionHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	txnID := vars["id"]

	// TODO: Fetch from database
	// Placeholder response
	txn := Transaction{
		ID:        txnID,
		Status:    "completed",
		CreatedAt: time.Now().Add(-5 * time.Minute),
		UpdatedAt: time.Now(),
	}

	respondJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    txn,
	})
}

func listTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement pagination and filtering
	respondJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    []Transaction{},
	})
}

func updateTransactionStatusHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	txnID := vars["id"]

	var body struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		respondJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid request body",
		})
		return
	}

	validStatuses := map[string]bool{
		"pending": true, "processing": true, "completed": true, "failed": true, "reversed": true,
	}
	if !validStatuses[body.Status] {
		respondJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid status. Must be: pending, processing, completed, failed, reversed",
		})
		return
	}

	log.Printf("Transaction %s status updated to: %s", txnID, body.Status)

	respondJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data: map[string]string{
			"id":     txnID,
			"status": body.Status,
		},
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	// TODO: Check database connectivity, Kafka connectivity
	respondJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s %v", r.Method, r.RequestURI, r.RemoteAddr, time.Since(start))
	})
}

func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		duration := time.Since(start).Seconds()
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", http.StatusOK)).Inc()
	})
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
