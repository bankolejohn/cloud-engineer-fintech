"""
FinFlow Notification Service

Sends payment notifications via multiple channels (email, SMS, push).
Consumes events from Kafka topics and dispatches notifications.
"""

import json
import logging
import os
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Configuration
PORT = int(os.getenv("PORT", "8084"))
SERVICE_NAME = os.getenv("SERVICE_NAME", "notification-service")

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(name)s %(levelname)s %(message)s'
)
logger = logging.getLogger(SERVICE_NAME)

app = Flask(__name__)


# Prometheus metrics
notifications_sent = Counter(
    'finflow_notifications_sent_total',
    'Total notifications sent',
    ['channel', 'type', 'status']
)

notification_latency = Histogram(
    'finflow_notification_latency_seconds',
    'Notification delivery latency',
    ['channel'],
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
)


class NotificationChannel(str, Enum):
    EMAIL = "email"
    SMS = "sms"
    PUSH = "push"
    WEBHOOK = "webhook"


class NotificationType(str, Enum):
    TRANSACTION_INITIATED = "transaction_initiated"
    TRANSACTION_COMPLETED = "transaction_completed"
    TRANSACTION_FAILED = "transaction_failed"
    FRAUD_ALERT = "fraud_alert"
    ACCOUNT_CREATED = "account_created"
    LOW_BALANCE = "low_balance"


@dataclass
class NotificationRequest:
    recipient_id: str
    channel: str
    type: str
    title: str
    message: str
    metadata: Optional[dict] = None


@dataclass
class NotificationResult:
    notification_id: str
    recipient_id: str
    channel: str
    type: str
    status: str  # sent, failed, queued
    sent_at: str
    delivery_ms: float
    error: Optional[str] = None


# Notification templates
TEMPLATES = {
    NotificationType.TRANSACTION_COMPLETED: {
        "title": "Payment Successful",
        "message": "Your payment of {amount} {currency} to {receiver} was successful. Transaction ID: {transaction_id}"
    },
    NotificationType.TRANSACTION_FAILED: {
        "title": "Payment Failed",
        "message": "Your payment of {amount} {currency} could not be processed. Reason: {reason}. Transaction ID: {transaction_id}"
    },
    NotificationType.FRAUD_ALERT: {
        "title": "Security Alert",
        "message": "Suspicious activity detected on your account. A transaction of {amount} {currency} has been flagged. Please verify."
    },
    NotificationType.ACCOUNT_CREATED: {
        "title": "Welcome to FinFlow",
        "message": "Your account has been created successfully. Account ID: {account_id}"
    },
    NotificationType.LOW_BALANCE: {
        "title": "Low Balance Alert",
        "message": "Your account balance is below {threshold} {currency}. Current balance: {balance} {currency}"
    },
}


class NotificationDispatcher:
    """Dispatches notifications to various channels."""

    def send(self, req: NotificationRequest) -> NotificationResult:
        start = time.time()
        notification_id = f"notif-{int(time.time() * 1000)}"

        try:
            if req.channel == NotificationChannel.EMAIL:
                self._send_email(req)
            elif req.channel == NotificationChannel.SMS:
                self._send_sms(req)
            elif req.channel == NotificationChannel.PUSH:
                self._send_push(req)
            elif req.channel == NotificationChannel.WEBHOOK:
                self._send_webhook(req)
            else:
                raise ValueError(f"Unknown channel: {req.channel}")

            delivery_ms = (time.time() - start) * 1000

            notifications_sent.labels(
                channel=req.channel, type=req.type, status="sent"
            ).inc()
            notification_latency.labels(channel=req.channel).observe(delivery_ms / 1000)

            return NotificationResult(
                notification_id=notification_id,
                recipient_id=req.recipient_id,
                channel=req.channel,
                type=req.type,
                status="sent",
                sent_at=datetime.now(timezone.utc).isoformat(),
                delivery_ms=round(delivery_ms, 2)
            )

        except Exception as e:
            delivery_ms = (time.time() - start) * 1000
            notifications_sent.labels(
                channel=req.channel, type=req.type, status="failed"
            ).inc()

            logger.error(f"Notification failed: {e}")
            return NotificationResult(
                notification_id=notification_id,
                recipient_id=req.recipient_id,
                channel=req.channel,
                type=req.type,
                status="failed",
                sent_at=datetime.now(timezone.utc).isoformat(),
                delivery_ms=round(delivery_ms, 2),
                error=str(e)
            )

    def _send_email(self, req: NotificationRequest):
        """Send email notification (simulated)."""
        # In production: integrate with SendGrid, SES, or similar
        logger.info(f"EMAIL to {req.recipient_id}: {req.title} - {req.message}")
        time.sleep(0.05)  # Simulate network latency

    def _send_sms(self, req: NotificationRequest):
        """Send SMS notification (simulated)."""
        # In production: integrate with Twilio, Africa's Talking, etc.
        logger.info(f"SMS to {req.recipient_id}: {req.message[:160]}")
        time.sleep(0.1)  # SMS gateways are slower

    def _send_push(self, req: NotificationRequest):
        """Send push notification (simulated)."""
        # In production: integrate with FCM, APNs
        logger.info(f"PUSH to {req.recipient_id}: {req.title}")
        time.sleep(0.03)

    def _send_webhook(self, req: NotificationRequest):
        """Send webhook notification (simulated)."""
        # In production: POST to configured webhook URL
        logger.info(f"WEBHOOK for {req.recipient_id}: {req.type}")
        time.sleep(0.02)


# Global dispatcher
dispatcher = NotificationDispatcher()


# ============================================================
# API Endpoints
# ============================================================

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/ready", methods=["GET"])
def ready():
    return jsonify({"status": "ready"}), 200


@app.route("/api/v1/notify", methods=["POST"])
def send_notification():
    """Send a single notification."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body required"}), 400

    try:
        req = NotificationRequest(
            recipient_id=data["recipient_id"],
            channel=data["channel"],
            type=data["type"],
            title=data.get("title", ""),
            message=data.get("message", ""),
            metadata=data.get("metadata")
        )

        # Apply template if message not provided
        if not req.message and req.type in TEMPLATES:
            template = TEMPLATES[req.type]
            req.title = template["title"]
            req.message = template["message"].format(**(data.get("metadata") or {}))

    except (KeyError, ValueError) as e:
        return jsonify({"error": f"Invalid request: {str(e)}"}), 400

    result = dispatcher.send(req)

    logger.info(
        f"Notification: id={result.notification_id} "
        f"channel={result.channel} status={result.status} "
        f"delivery_ms={result.delivery_ms}"
    )

    status_code = 200 if result.status == "sent" else 500
    return jsonify(asdict(result)), status_code


@app.route("/api/v1/notify/batch", methods=["POST"])
def send_batch():
    """Send notifications in batch."""
    data = request.get_json()
    if not data or "notifications" not in data:
        return jsonify({"error": "notifications array required"}), 400

    results = []
    for notif_data in data["notifications"]:
        try:
            req = NotificationRequest(
                recipient_id=notif_data["recipient_id"],
                channel=notif_data["channel"],
                type=notif_data["type"],
                title=notif_data.get("title", ""),
                message=notif_data.get("message", ""),
                metadata=notif_data.get("metadata")
            )
            result = dispatcher.send(req)
            results.append(asdict(result))
        except (KeyError, ValueError) as e:
            results.append({"error": str(e), "recipient_id": notif_data.get("recipient_id")})

    sent = sum(1 for r in results if r.get("status") == "sent")
    failed = sum(1 for r in results if r.get("status") == "failed")

    return jsonify({
        "results": results,
        "summary": {"total": len(results), "sent": sent, "failed": failed}
    }), 200


@app.route("/api/v1/templates", methods=["GET"])
def list_templates():
    """List available notification templates."""
    templates = {}
    for key, val in TEMPLATES.items():
        templates[key.value] = val
    return jsonify(templates), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    logger.info(f"Starting {SERVICE_NAME} on port {PORT}")
    app.run(host="0.0.0.0", port=PORT)
