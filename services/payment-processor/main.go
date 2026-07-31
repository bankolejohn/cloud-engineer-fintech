package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// PaymentEvent represents a transaction event from Kafka
type PaymentEvent struct {
	TransactionID   string  `json:"transaction_id"`
	SenderAccount   string  `json:"sender_account"`
	ReceiverAccount string  `json:"receiver_account"`
	Amount          float64 `json:"amount"`
	Currency        string  `json:"currency"`
	Type            string  `json:"type"`
}

// ProcessingResult represents the outcome of payment processing
type ProcessingResult struct {
	TransactionID string `json:"transaction_id"`
	Status        string `json:"status"`
	Reason        string `json:"reason,omitempty"`
	ProcessedAt   string `json:"processed_at"`
	ProcessingMs  int64  `json:"processing_ms"`
}

// Prometheus metrics
var (
	paymentsProcessed = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "finflow_payments_processed_total",
			Help: "Total payments processed",
		},
		[]string{"status", "type", "currency"},
	)

	paymentProcessingDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "finflow_payment_processing_duration_ms",
			Help:    "Payment processing duration in milliseconds",
			Buckets: []float64{10, 50, 100, 250, 500, 1000, 2500, 5000},
		},
		[]string{"type"},
	)

	paymentAmountTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "finflow_payment_amount_total",
			Help: "Total payment amount processed",
		},
		[]string{"currency", "type"},
	)
)

func init() {
	prometheus.MustRegister(paymentsProcessed)
	prometheus.MustRegister(paymentProcessingDuration)
	prometheus.MustRegister(paymentAmountTotal)
}

func main() {
	port := getEnv("PORT", "8081")
	serviceName := getEnv("SERVICE_NAME", "payment-processor")

	log.Printf("Starting %s on port %s", serviceName, port)

	router := mux.NewRouter()

	// Health endpoints
	router.HandleFunc("/health", healthHandler).Methods("GET")
	router.HandleFunc("/ready", readyHandler).Methods("GET")

	// Processing endpoints
	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/process", processPaymentHandler).Methods("POST")
	api.HandleFunc("/validate", validatePaymentHandler).Methods("POST")

	// Metrics
	router.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// TODO: Start Kafka consumer for "transactions.created" topic
	// go startKafkaConsumer()

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
}

func processPaymentHandler(w http.ResponseWriter, r *http.Request) {
	var event PaymentEvent
	if err := json.NewDecoder(r.Body).Decode(&event); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	start := time.Now()

	// Simulate payment processing
	result := processPayment(event)

	duration := time.Since(start).Milliseconds()
	paymentProcessingDuration.WithLabelValues(event.Type).Observe(float64(duration))
	paymentsProcessed.WithLabelValues(result.Status, event.Type, event.Currency).Inc()
	paymentAmountTotal.WithLabelValues(event.Currency, event.Type).Add(event.Amount)

	result.ProcessingMs = duration

	log.Printf("Payment processed: txn=%s status=%s duration=%dms",
		event.TransactionID, result.Status, duration)

	w.Header().Set("Content-Type", "application/json")
	if result.Status == "failed" {
		w.WriteHeader(http.StatusUnprocessableEntity)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	json.NewEncoder(w).Encode(result)
}

func validatePaymentHandler(w http.ResponseWriter, r *http.Request) {
	var event PaymentEvent
	if err := json.NewDecoder(r.Body).Decode(&event); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	errors := validatePayment(event)

	w.Header().Set("Content-Type", "application/json")
	if len(errors) > 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"valid":  false,
			"errors": errors,
		})
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"valid": true,
	})
}

func processPayment(event PaymentEvent) ProcessingResult {
	// Simulate processing time (50-500ms)
	processingTime := time.Duration(50+rand.Intn(450)) * time.Millisecond
	time.Sleep(processingTime)

	// Simulate occasional failures (5% failure rate)
	if rand.Float64() < 0.05 {
		return ProcessingResult{
			TransactionID: event.TransactionID,
			Status:        "failed",
			Reason:        "Payment gateway timeout",
			ProcessedAt:   time.Now().UTC().Format(time.RFC3339),
		}
	}

	// Check for suspicious amounts (fraud simulation)
	if event.Amount > 1000000 {
		return ProcessingResult{
			TransactionID: event.TransactionID,
			Status:        "held",
			Reason:        "Amount exceeds threshold, sent for manual review",
			ProcessedAt:   time.Now().UTC().Format(time.RFC3339),
		}
	}

	return ProcessingResult{
		TransactionID: event.TransactionID,
		Status:        "completed",
		ProcessedAt:   time.Now().UTC().Format(time.RFC3339),
	}
}

func validatePayment(event PaymentEvent) []string {
	var errors []string

	if event.Amount <= 0 {
		errors = append(errors, "amount must be greater than zero")
	}
	if event.SenderAccount == "" {
		errors = append(errors, "sender_account is required")
	}
	if event.ReceiverAccount == "" {
		errors = append(errors, "receiver_account is required")
	}
	if event.SenderAccount == event.ReceiverAccount {
		errors = append(errors, "sender and receiver cannot be the same account")
	}

	validCurrencies := map[string]bool{"NGN": true, "USD": true, "GBP": true, "EUR": true, "KES": true}
	if !validCurrencies[event.Currency] {
		errors = append(errors, fmt.Sprintf("unsupported currency: %s", event.Currency))
	}

	validTypes := map[string]bool{"transfer": true, "deposit": true, "withdrawal": true}
	if !validTypes[event.Type] {
		errors = append(errors, fmt.Sprintf("invalid transaction type: %s", event.Type))
	}

	return errors
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func readyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
