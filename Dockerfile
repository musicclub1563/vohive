# syntax=docker/dockerfile:1.7

# Build toolchains run natively on the BuildKit host. Without --platform=$BUILDPLATFORM
# the arm64 branch executes npm and the Go compiler through QEMU, which is much
# slower and makes `npm ci` look like it hangs.

# ---- Stage 1: build the web frontend once on the native builder ----
FROM --platform=$BUILDPLATFORM node:20-alpine AS web-builder
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build

# ---- Stage 2: cross-compile the Go binary on the native builder ----
# go.mod requires a newer toolchain than the base image ships; GOTOOLCHAIN=auto
# downloads it on demand.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS go-builder
ENV GOTOOLCHAIN=auto
RUN apk add --no-cache git
WORKDIR /src

ARG VERSION=dev
ARG BUILD_TIME=""
ARG TARGETOS
ARG TARGETARCH

COPY go.mod go.sum ./
# go.mod replaces github.com/emiago/sipgo with ./third_party/sipgo, so the local
# replacement must be present before any module resolution happens.
COPY third_party/ ./third_party/
RUN go mod download

COPY . .
# Overlay the freshly built frontend so `//go:embed all:dist` picks it up.
COPY --from=web-builder /web/dist ./internal/web/dist

RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -trimpath -buildvcs=false -tags "with_utls nomsgpack" \
    -ldflags "-s -w -X 'github.com/1239t/vohive/internal/global.Version=${VERSION}' -X 'github.com/1239t/vohive/internal/global.BuildTime=${BUILD_TIME}'" \
    -o /out/vohive ./cmd/vohive

# ---- Stage 3: minimal runtime ----
FROM alpine:3.20
# ca-certificates : HTTPS (GitHub release checks, eSIM SM-DP+, notification webhooks)
# iproute2        : ip/netlink management of wwan* modem interfaces
# tzdata          : TZ support
# usbutils        : lsusb diagnostics for modem hot-plug
RUN apk add --no-cache ca-certificates iproute2 tzdata usbutils

RUN mkdir -p /app/config /app/data /app/logs

COPY --from=go-builder /out/vohive /app/vohive
COPY config/config.example.yaml /app/config/config.example.yaml
COPY scripts/docker-entrypoint.sh /usr/local/bin/vohive-entrypoint

RUN chmod 0755 /app/vohive /usr/local/bin/vohive-entrypoint

# Modem discovery, QMI/MBIM control and network management need host networking
# and device access; see docker-compose.yml for the required flags.
VOLUME ["/app/data", "/app/config", "/app/logs"]
EXPOSE 7575
ENV CONFIG_PATH=/app/config/config.yaml \
    TZ=Asia/Shanghai

ENTRYPOINT ["/usr/local/bin/vohive-entrypoint"]
CMD ["-c", "/app/config/config.yaml"]
