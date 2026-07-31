"""
FinFlow Fraud Detection Service

Scores transactions for fraud risk using rule-based and ML-based detection.
Consumes events from Kafka topic 'transactions.created' and publishes
fraud scores to 'transactions.fraud-scored'.
"""

import json
import logging
import os
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import Optional

from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

# Configuration
PORT = int(os.getenv("PORT", "8083"))
SERVICE_NAME = os.getenv("SERVICE_NAME", "fraud-detection")
FRAUD_THRESHOLD = float(os.getenv("FRAUD_THRESHOLD", "0.7"))

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(name)s %(levelname)s %(message)s'
)
logger = logging.getLogger(SERVICE_NAME)

# Flask app
app = Flask(__name__)

# Prometheus metrics
fraud_checks_total = Counter(
    'finflow_fraud_checks_total',
    'Total fraud checks performed',
    ['result']  # clean, suspicious, fraudulent
)

fraud_score_histogram = Histogram(
    'finflow_fraud_score_distribution',
    'Distribution of fraud scores',
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
)

fraud_detection_duration = Histogram(
    'finflow_fraud_detection_duration_seconds',
    'Time taken to score a transaction',
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0]
)

active_fraud_alerts = Gauge(
    'finflow_active_fraud_alerts',
    'Number of active fraud alerts'
)


@dataclass
class FraudScore:
    transaction_id: str
    score: float
    risk_level: str  # low, medium, high, critical
    flags: list
    recommendation: str  # approve, review, block
    scored_at: str
    processing_ms: float


@dataclass
class TransactionEvent:
    transaction_id: str
    sender_account: str
    receiver_account: str
    amount: float
    currency: str
    type: str
    description: Optional[str] = None


# ============================================================
# Fraud Detection Rules Engine
# ============================================================

class FraudDetector:
    """Rule-based fraud detection engine."""

    # Thresholds
    HIGH_AMOUNT_NGN = 5_000_000  # 5 million naira
    HIGH_AMOUNT_USD = 10_000
    VELOCITY_LIMIT = 10  # max transactions per minute per account

    # Known suspicious patterns
    SUSPICIOUS_KEYWORDS = ["urgent", "lottery", "prize", "winner", "inheritance"]

    def __init__(self):
        # In production, these would come from a database/cache
        self.transaction_history = {}  # account -> list of recent txn timestamps

    def score_transaction(self, txn: TransactionEvent) -> FraudScore:
        """Score a transaction for fraud risk. Returns 0.0 (safe) to 1.0 (fraud)."""
        start_time = time.time()
        flags = []
        score = 0.0

        # Rule 1: High amount check
        amount_score = self._check_amount(txn)
        if amount_score > 0:
            flags.append(f"high_amount: {txn.amount} {txn.currency}")
            score += amount_score

        # Rule 2: Velocity check (too many transactions)
        velocity_score = self._check_velocity(txn.sender_account)
        if velocity_score > 0:
            flags.append("high_velocity: unusual transaction frequency")
            score += velocity_score

        # Rule 3: Suspicious description keywords
        desc_score = self._check_description(txn.description)
        if desc_score > 0:
            flags.append("suspicious_keywords: flagged content in description")
            score += desc_score

        # Rule 4: Self-transfer pattern (potential money laundering)
        if txn.sender_account == txn.receiver_account:
            flags.append("self_transfer: sender equals receiver")
            score += 0.3

        # Rule 5: Round amount (common in fraud)
        if txn.amount > 1000 and txn.amount % 1000 == 0:
            flags.append("round_amount: suspiciously round number")
            score += 0.1

        # Rule 6: Cross-border transactions (simplified)
        cross_border_score = self._check_cross_border(txn)
        if cross_border_score > 0:
            flags.append("cross_border: international transfer flagged")
            score += cross_border_score

        # Normalize score to 0-1
        score = min(score, 1.0)

        # Determine risk level and recommendation
        risk_level = self._get_risk_level(score)
        recommendation = self._get_recommendation(score)

        processing_ms = (time.time() - start_time) * 1000

        # Record metrics
        fraud_score_histogram.observe(score)
        fraud_detection_duration.observe(processing_ms / 1000)

        if risk_level in ("high", "critical"):
            fraud_checks_total.labels(result="fraudulent").inc()
            active_fraud_alerts.inc()
        elif risk_level == "medium":
            fraud_checks_total.labels(result="suspicious").inc()
        else:
            fraud_checks_total.labels(result="clean").inc()

        # Track transaction for velocity
        self._record_transaction(txn.sender_account)

        return FraudScore(
            transaction_id=txn.transaction_id,
            score=round(score, 4),
            risk_level=risk_level,
            flags=flags,
            recommendation=recommendation,
            scored_at=datetime.now(timezone.utc).isoformat(),
            processing_ms=round(processing_ms, 2)
        )

    def _check_amount(self, txn: TransactionEvent) -> float:
        """Check if amount exceeds thresholds."""
        if txn.currency == "NGN" and txn.amount > self.HIGH_AMOUNT_NGN:
            return 0.4
        elif txn.currency in ("USD", "GBP", "EUR") and txn.amount > self.HIGH_AMOUNT_USD:
            return 0.3
        elif txn.amount > 1_000_000:  # Generic high amount
            return 0.25
        return 0.0

    def _check_velocity(self, account_id: str) -> float:
        """Check transaction velocity for account."""
        now = time.time()
        history = self.transaction_history.get(account_id, [])

        # Count transactions in the last 60 seconds
        recent = [ts for ts in history if now - ts < 60]
        self.transaction_history[account_id] = recent

        if len(recent) > self.VELOCITY_LIMIT:
            return 0.5
        elif len(recent) > self.VELOCITY_LIMIT // 2:
            return 0.2
        return 0.0

    def _check_description(self, description: Optional[str]) -> float:
        """Check for suspicious keywords in description."""
        if not description:
            return 0.0

        desc_lower = description.lower()
        matches = [kw for kw in self.SUSPICIOUS_KEYWORDS if kw in desc_lower]
        if matches:
            return 0.3
        return 0.0

    def _check_cross_border(self, txn: TransactionEvent) -> float:
        """Flag cross-border transactions above threshold."""
        if txn.currency not in ("NGN",) and txn.amount > 5000:
            return 0.15
        return 0.0

    def _get_risk_level(self, score: float) -> str:
        if score >= 0.8:
            return "critical"
        elif score >= 0.6:
            return "high"
        elif score >= 0.4:
            return "medium"
        return "low"

    def _get_recommendation(self, score: float) -> str:
        if score >= FRAUD_THRESHOLD:
            return "block"
        elif score >= 0.4:
            return "review"
        return "approve"

    def _record_transaction(self, account_id: str):
        """Record transaction timestamp for velocity tracking."""
        if account_id not in self.transaction_history:
            self.transaction_history[account_id] = []
        self.transaction_history[account_id].append(time.time())


# Global detector instance
detector = FraudDetector()


# ============================================================
# API Endpoints
# ============================================================

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/ready", methods=["GET"])
def ready():
    return jsonify({"status": "ready"}), 200


@app.route("/api/v1/score", methods=["POST"])
def score_transaction():
    """Score a single transaction for fraud risk."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body is required"}), 400

    try:
        txn = TransactionEvent(
            transaction_id=data["transaction_id"],
            sender_account=data["sender_account"],
            receiver_account=data["receiver_account"],
            amount=float(data["amount"]),
            currency=data["currency"],
            type=data["type"],
            description=data.get("description")
        )
    except (KeyError, ValueError) as e:
        return jsonify({"error": f"Invalid request: {str(e)}"}), 400

    result = detector.score_transaction(txn)

    logger.info(
        f"Fraud score: txn={result.transaction_id} "
        f"score={result.score} risk={result.risk_level} "
        f"recommendation={result.recommendation}"
    )

    return jsonify(asdict(result)), 200


@app.route("/api/v1/batch-score", methods=["POST"])
def batch_score():
    """Score multiple transactions in batch."""
    data = request.get_json()
    if not data or "transactions" not in data:
        return jsonify({"error": "transactions array is required"}), 400

    results = []
    for txn_data in data["transactions"]:
        try:
            txn = TransactionEvent(
                transaction_id=txn_data["transaction_id"],
                sender_account=txn_data["sender_account"],
                receiver_account=txn_data["receiver_account"],
                amount=float(txn_data["amount"]),
                currency=txn_data["currency"],
                type=txn_data["type"],
                description=txn_data.get("description")
            )
            result = detector.score_transaction(txn)
            results.append(asdict(result))
        except (KeyError, ValueError) as e:
            results.append({
                "transaction_id": txn_data.get("transaction_id", "unknown"),
                "error": str(e)
            })

    return jsonify({"results": results, "total": len(results)}), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    """Prometheus metrics endpoint."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    logger.info(f"Starting {SERVICE_NAME} on port {PORT}")
    app.run(host="0.0.0.0", port=PORT)
