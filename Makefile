BINARY_NAME ?= vohive
GO_TAGS ?= with_utls nomsgpack
GOOS ?= linux
CGO_ENABLED ?= 0
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "unknown")
# 注入的版本号统一带 v 前缀（semver），与 CI/Docker 构建保持一致
VERSION_TAG = $(if $(filter v%,$(VERSION)),$(VERSION),v$(VERSION))
BUILD_TIME ?= $(shell date "+%Y-%m-%d %H:%M:%S")
DIST_DIR ?= dist
MAIN_PACKAGE ?= ./cmd/vohive
MODULE ?= github.com/1239t/vohive
PKG_LIST ?= ./...

LDFLAGS = -s -w -X '$(MODULE)/internal/global.Version=$(VERSION_TAG)' -X '$(MODULE)/internal/global.BuildTime=$(BUILD_TIME)'
GO_BUILD = go build -trimpath -buildvcs=false -tags "$(GO_TAGS)" -ldflags "$(LDFLAGS)"

# 本地产物命名与 CI 发布对齐:vohive-linux-<arch>(不含版本号,版本由 ldflags 注入)
AMD64_OUT = $(DIST_DIR)/$(BINARY_NAME)-linux-amd64
ARM64_OUT = $(DIST_DIR)/$(BINARY_NAME)-linux-arm64
ARMV7_OUT = $(DIST_DIR)/$(BINARY_NAME)-linux-armv7
UPX ?= $(shell command -v upx || command -v upx-ucl)
UPX_FLAGS ?= --best --lzma

.PHONY: all help build build-amd64 build-arm64 build-all \
        frontend-install frontend-dev frontend-dist \
        test test-race cover bench vet lint fmt fmt-check tidy \
        docker-build run clean

all: build-all

help:
	@echo "VoHive 构建目标:"
	@echo "  make build           构建 linux/amd64 产物 (含前端)"
	@echo "  make build-all       构建 amd64 / arm64 双架构产物"
	@echo "  make frontend-dev    启动前端开发服务器 (Vite :5173)"
	@echo "  make run             本地编译并运行"
	@echo "  make test            运行 Go 单元测试"
	@echo "  make test-race       运行 Go 单元测试 (竞态检测)"
	@echo "  make cover           生成覆盖率报告 coverage.out"
	@echo "  make vet             go vet"
	@echo "  make lint            gofmt 检查 + go vet"
	@echo "  make fmt             格式化 Go 代码"
	@echo "  make tidy            整理 go.mod / go.sum"
	@echo "  make docker-build    构建 Docker 镜像 vohive:local"
	@echo "  make clean           清理构建产物"

build: build-amd64

build-all: build-amd64 build-arm64

# ---- 前端 ----

frontend-install:
	npm ci --prefix web

frontend-dev:
	npm run dev --prefix web

frontend-dist:
	npm ci --prefix web
	npm run build --prefix web
	rm -rf internal/web/dist
	mkdir -p internal/web
	cp -R web/dist internal/web/dist

# ---- 测试与静态检查 ----

test:
	go test -tags "$(GO_TAGS)" $(PKG_LIST)

test-race:
	go test -race -tags "$(GO_TAGS)" $(PKG_LIST)

cover:
	go test -tags "$(GO_TAGS)" -coverprofile=coverage.out -covermode=atomic $(PKG_LIST)
	go tool cover -func=coverage.out | tail -n 1

bench:
	go test -tags "$(GO_TAGS)" -bench=. -benchmem $(PKG_LIST)

vet:
	go vet -tags "$(GO_TAGS)" $(PKG_LIST)

fmt:
	gofmt -s -w $(shell git ls-files '*.go' | grep -v '^third_party/')

fmt-check:
	@out=$$(gofmt -s -l $(shell git ls-files '*.go' | grep -v '^third_party/')); \
	if [ -n "$$out" ]; then echo "以下文件未格式化:"; echo "$$out"; exit 1; fi

lint: fmt-check vet

tidy:
	go mod tidy

# ---- 本地运行 ----

run:
	go run -tags "$(GO_TAGS)" $(MAIN_PACKAGE) -c config/config.yaml

# ---- 容器 ----

docker-build:
	docker build -t vohive:local .

# ---- 编译 ----

build-amd64: frontend-dist
	mkdir -p $(DIST_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=amd64 $(GO_BUILD) -o $(AMD64_OUT) $(MAIN_PACKAGE)
	@if [ -n "$(UPX)" ]; then $(UPX) $(UPX_FLAGS) $(AMD64_OUT); else echo "未检测到 upx，跳过压缩: $(AMD64_OUT)"; fi

build-arm64: frontend-dist
	mkdir -p $(DIST_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=arm64 $(GO_BUILD) -o $(ARM64_OUT) $(MAIN_PACKAGE)
	@if [ -n "$(UPX)" ]; then $(UPX) $(UPX_FLAGS) $(ARM64_OUT); else echo "未检测到 upx，跳过压缩: $(ARM64_OUT)"; fi

clean:
	go clean
	rm -rf $(DIST_DIR)
	rm -rf internal/web/dist
