FROM nginxinc/nginx-unprivileged:1.29-alpine

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html 404.html privacy.html robots.txt sitemap.xml \
    manifest.webmanifest styles.css sw.js /usr/share/nginx/html/
COPY fonts/ /usr/share/nginx/html/fonts/
COPY img/ /usr/share/nginx/html/img/
COPY js/ /usr/share/nginx/html/js/
COPY plaatsen/ /usr/share/nginx/html/plaatsen/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
