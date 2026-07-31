# Multi-stage build for account-service
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

COPY services/account-service/go.mod services/account-service/go.sum* ./
RUN go mod download

COPY services/account-service/ .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /bin/account-service .

FROM gcr.io/distroless/static:nonroot

COPY --from=builder /bin/account-service /bin/account-service
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER nonroot:nonroot

EXPOSE 8082

ENTRYPOINT ["/bin/account-service"]
