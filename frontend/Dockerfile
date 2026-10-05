# Pinned to the nginx 1.27 stable line on Alpine; never `latest`.
FROM nginx:1.27-alpine

# Site configuration: static page + /api reverse proxy to the backend service.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Static assets.
COPY html/ /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=6 \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
