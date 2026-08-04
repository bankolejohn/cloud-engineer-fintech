# Dashboard - Simple Nginx serving static HTML + proxying API calls
FROM nginx:1.25-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our Nginx config (reverse proxy to backend services)
COPY services/dashboard/nginx.conf /etc/nginx/conf.d/default.conf

# Copy the dashboard HTML
COPY services/dashboard/index.html /usr/share/nginx/html/index.html

EXPOSE 8090

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:8090/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
