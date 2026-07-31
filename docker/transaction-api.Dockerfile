# Multi-stage build for transaction-api
# Stage 1: Build
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy go mod files first for layer caching
COPY services/transaction-api/go.mod services/transaction-api/go.sum* ./
RUN go mod download

# Copy source code
COPY services/transaction-api/ .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /bin/transaction-api .

# Stage 2: Runtime (distroless for minimal attack surface)
FROM gcr.io/distroless/static:nonroot

COPY --from=builder /bin/transaction-api /bin/transaction-api
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/bin/transaction-api"]
