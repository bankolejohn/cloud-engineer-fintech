# Multi-stage build for payment-processor
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

COPY services/payment-processor/go.mod services/payment-processor/go.sum* ./
RUN go mod download

COPY services/payment-processor/ .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /bin/payment-processor .

FROM gcr.io/distroless/static:nonroot

COPY --from=builder /bin/payment-processor /bin/payment-processor
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER nonroot:nonroot

EXPOSE 8081

ENTRYPOINT ["/bin/payment-processor"]
