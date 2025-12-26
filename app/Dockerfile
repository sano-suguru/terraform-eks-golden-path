# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Install certificates for HTTPS calls
RUN apk add --no-cache ca-certificates

# Copy go mod files first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /api ./cmd/api

# Runtime stage
FROM scratch

# Copy CA certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /api /api

# Run as non-root user
USER 65534:65534

EXPOSE 8080

ENTRYPOINT ["/api"]
