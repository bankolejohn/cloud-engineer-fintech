# Multi-stage build for notification-service (Python)
FROM python:3.11-slim AS builder

WORKDIR /app

COPY services/notification-service/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim

RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY services/notification-service/ .

USER appuser

EXPOSE 8084

CMD ["gunicorn", "--bind", "0.0.0.0:8084", "--workers", "4", "--threads", "2", "--timeout", "120", "app:app"]
