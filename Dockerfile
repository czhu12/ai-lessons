# syntax=docker/dockerfile:1
# Stage 1 renders every book to static HTML (markdown, highlighting, search index).
FROM node:22-alpine AS build
WORKDIR /src
COPY reader/package.json reader/package-lock.json reader/
RUN cd reader && npm ci --omit=dev --no-audit --no-fund
COPY reader reader
COPY books books
ARG REPO_URL=https://github.com/czhu12/ai-lessons
ARG SITE_TITLE="AI Lessons"
RUN REPO_URL="$REPO_URL" SITE_TITLE="$SITE_TITLE" node reader/build.js

# Stage 2 only serves files: busybox httpd, ~1 MB of RAM, no state. Reading progress lives in each browser.
FROM busybox:1.37-musl
COPY --from=build /src/dist /www
COPY reader/httpd.conf /etc/httpd.conf
USER 65534:65534
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
CMD ["httpd", "-f", "-p", "8080", "-h", "/www", "-c", "/etc/httpd.conf"]
