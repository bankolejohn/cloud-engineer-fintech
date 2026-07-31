# Multi-stage build for fraud-detection (Python)
FROM python:3.11-slim AS builder

WORKDIR /app

# Install dependencies
COPY services/fraud-detection/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.11-slim

# Security: run as non-root
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy installed dependencies
COPY --from=builder /install /usr/local

# Copy application code
COPY services/fraud-detection/ .

USER appuser

EXPOSE 8083

# Use gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8083", "--workers", "4", "--threads", "2", "--timeout", "120", "app:app"]
