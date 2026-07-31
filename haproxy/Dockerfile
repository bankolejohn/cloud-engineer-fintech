FROM haproxy:2.9-alpine

# Copy configuration
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

# Create error pages directory
RUN mkdir -p /etc/haproxy/errors /etc/haproxy/certs /run/haproxy

# Expose ports
EXPOSE 80 443 8404 3306

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8404/stats || exit 1

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
