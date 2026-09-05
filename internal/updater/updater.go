package updater

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/1239t/vohive/internal/global"
	"github.com/1239t/vohive/pkg/logger"
	"github.com/minio/selfupdate"
	"github.com/ulikunitz/xz"
	"golang.org/x/mod/semver"
)

const (
	repoOwner = "musicclub1563"
	repoName  = "vohive"
)

// repoAccessToken 返回访问 GitHub Release API 的令牌。
//
// 仓库为私有时，未带令牌的请求会返回 404，在线更新与更新检查将不可用。
// 依次读取 VOHIVE_UPDATE_TOKEN（推荐）与 GITHUB_TOKEN，两者均为空则不鉴权。
// 令牌需要对该私有仓库具备 repo（或 contents:read）权限。
func repoAccessToken() string {
	if token := strings.TrimSpace(os.Getenv("VOHIVE_UPDATE_TOKEN")); token != "" {
		return token
	}
	return strings.TrimSpace(os.Getenv("GITHUB_TOKEN"))
}

// authRequest 为 GitHub API 请求附加标准请求头与可选令牌。
func authRequest(req *http.Request) {
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if token := repoAccessToken(); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
}

type Release struct {
	TagName string  `json:"tag_name"`
	Name    string  `json:"name"`
	Body    string  `json:"body"`
	Assets  []Asset `json:"assets"`
}

type Asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

type UpdateInfo struct {
	HasUpdate   bool   `json:"has_update"`
	CurrentVer  string `json:"current_version"`
	LatestVer   string `json:"latest_version"`
	ReleaseNote string `json:"release_note"`
	IsDocker    bool   `json:"is_docker"`
}

// CheckUpdate 检查是否有新版本
func CheckUpdate() (*UpdateInfo, error) {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", repoOwner, repoName)

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request failed: %w", err)
	}
	authRequest(req)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request github api failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("github api returned status: %d", resp.StatusCode)
	}

	var release Release
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("decode response failed: %w", err)
	}

	currentVersion := global.Version
	if !strings.HasPrefix(currentVersion, "v") {
		currentVersion = "v" + currentVersion
	}
	latestVersion := release.TagName
	if !strings.HasPrefix(latestVersion, "v") {
		latestVersion = "v" + latestVersion
	}

	// 使用 semver 比较版本
	hasUpdate := false
	if semver.IsValid(currentVersion) && semver.IsValid(latestVersion) {
		if semver.Compare(currentVersion, latestVersion) < 0 {
			hasUpdate = true
		}
	} else {
		// 如果本地或线上不是标准 semver (比如 unknown, dev 等)，可以尝试直接不等即提示更新
		if currentVersion != latestVersion {
			hasUpdate = true
		}
	}

	isDocker := false
	if _, err := os.Stat("/.dockerenv"); err == nil {
		isDocker = true
	}

	return &UpdateInfo{
		HasUpdate:   hasUpdate,
		CurrentVer:  currentVersion,
		LatestVer:   latestVersion,
		ReleaseNote: release.Body,
		IsDocker:    isDocker,
	}, nil
}

// ApplyUpdate 获取最新 release 并下载对应架构的二进制进行自我替换
func ApplyUpdate() error {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", repoOwner, repoName)
	client := &http.Client{Timeout: 15 * time.Second}

	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return fmt.Errorf("failed to fetch release info: %w", err)
	}
	authRequest(req)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch release info: %w", err)
	}
	defer resp.Body.Close()

	var release Release
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return fmt.Errorf("failed to decode release info: %w", err)
	}

	// 拼接对应的 asset 名称,与 binary-release.yml 产出一致:vohive-linux-<arch>
	// (文件名不含版本号)。runtime 的 arm64 对应 vohive-linux-arm64(aarch64 为同一
	// GOARCH=arm64 编译的别名,自更新按 arm64 匹配即可)。
	targetGoarch := runtime.GOARCH
	switch targetGoarch {
	case "arm":
		targetGoarch = "armv7"
	case "386":
		targetGoarch = "386"
	case "amd64":
		targetGoarch = "amd64"
	case "arm64":
		targetGoarch = "arm64"
	}

	binaryName := "vohive"
	assetPrefix := fmt.Sprintf("%s-linux-%s", binaryName, targetGoarch)

	var downloadURL string
	for _, asset := range release.Assets {
		if strings.HasPrefix(asset.Name, assetPrefix) {
			downloadURL = asset.BrowserDownloadURL
			break
		}
	}

	if downloadURL == "" {
		return fmt.Errorf("no matching asset found for architecture linux/%s (prefix %q)", targetGoarch, assetPrefix)
	}

	logger.Info("开始下载更新", "url", downloadURL)

	// 下载二进制。私有仓库的 Release 资产下载也需要令牌鉴权。
	// 使用独立的下载客户端并放宽超时：归档体积较大且可能处于慢速网络，
	// 原先与查询复用的 15s 超时会在流式解压读取 body 时触发
	// "context deadline exceeded (Client.Timeout ...)" 导致更新失败。
	dlClient := &http.Client{Timeout: 10 * time.Minute}
	dlReq, err := http.NewRequest(http.MethodGet, downloadURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create download request: %w", err)
	}
	dlReq.Header.Set("Accept", "application/octet-stream")
	if token := repoAccessToken(); token != "" {
		dlReq.Header.Set("Authorization", "Bearer "+token)
	}

	dlResp, err := dlClient.Do(dlReq)
	if err != nil {
		return fmt.Errorf("failed to download update: %w", err)
	}
	defer dlResp.Body.Close()

	if dlResp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed with status %d", dlResp.StatusCode)
	}

	// 先把整个归档读入内存，再解压提取二进制。这样解压阶段不再依赖
	// 网络连接，避免慢速网络下读取 body 中途被判定为超时。
	const maxArchiveSize = 300 * 1024 * 1024
	archiveData, err := io.ReadAll(io.LimitReader(dlResp.Body, maxArchiveSize))
	if err != nil {
		return fmt.Errorf("failed to read update archive: %w", err)
	}

	// Release 资产是 .tar.xz 归档，而 selfupdate 需要解压后的原始二进制。
	// 先解压归档并提取名为 "vohive" 的可执行文件，再交给 selfupdate 做原子替换。
	binData, err := extractBinaryFromTarXZ(bytes.NewReader(archiveData), "vohive")
	if err != nil {
		return fmt.Errorf("failed to extract binary from archive: %w", err)
	}

	// 执行替换
	err = selfupdate.Apply(bytes.NewReader(binData), selfupdate.Options{})
	if err != nil {
		// 回滚
		if rerr := selfupdate.RollbackError(err); rerr != nil {
			return fmt.Errorf("update failed and rollback failed: %v, original error: %w", rerr, err)
		}
		return fmt.Errorf("update failed: %w", err)
	}

	logger.Info("应用更新成功，正在准备重启...")

	// 延迟退出以便接口能返回成功响应，随后触发服务重启使新二进制生效。
	go func() {
		time.Sleep(2 * time.Second)
		logger.Info("应用更新成功，正在重启服务以加载新版本")
		restartService()
	}()

	return nil
}

// extractBinaryFromTarXZ 从 .tar.xz 流中解压并提取名为 wantName 的可执行文件内容。
// Release 资产经 xz 压缩并以 tar 打包，selfupdate 只能消费解压后的裸二进制，
// 因此下载后必须在此解包，否则会把压缩数据当成 ELF 写入导致启动失败。
func extractBinaryFromTarXZ(r io.Reader, wantName string) ([]byte, error) {
	xzr, err := xz.NewReader(r)
	if err != nil {
		return nil, fmt.Errorf("xz decompress: %w", err)
	}
	tr := tar.NewReader(xzr)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("tar read: %w", err)
		}
		if filepath.Base(hdr.Name) != wantName {
			continue
		}
		// 防御过大文件撑爆内存；正常二进制不会超过 200MiB。
		if hdr.Size > 200*1024*1024 {
			return nil, fmt.Errorf("binary %q too large: %d bytes", wantName, hdr.Size)
		}
		data, err := io.ReadAll(io.LimitReader(tr, hdr.Size))
		if err != nil {
			return nil, fmt.Errorf("read binary entry: %w", err)
		}
		return data, nil
	}
	return nil, fmt.Errorf("binary %q not found in archive", wantName)
}

// restartService 在自我替换完成后触发服务重启，使新二进制生效。
// 优先调用 systemctl 显式重启（通过 systemd IPC，不依赖 Restart= 配置），
// 非 systemd 环境（如 OpenWrt procd）或 systemctl 不可用时，回退为向自身
// 发送 SIGTERM，由服务管理器的 respawn 机制重新拉起。
func restartService() {
	bin, err := exec.LookPath("systemctl")
	if err == nil {
		out, err := exec.Command(bin, "is-active", "vohive").CombinedOutput()
		if err == nil && strings.TrimSpace(string(out)) == "active" {
			// 交给 systemd 显式重启：systemd 会终止当前（旧）进程并启动新二进制。
			// 这里只负责触发，随后本进程会被 systemd 发出的停止信号终止；
			// 若长时间未被终止，末尾的 SIGTERM 兜底逻辑仍会生效。
			_ = exec.Command(bin, "restart", "vohive").Start()
			time.Sleep(10 * time.Second)
		}
	}
	if p, err := os.FindProcess(os.Getpid()); err == nil {
		_ = p.Signal(syscall.SIGTERM)
	} else {
		os.Exit(1)
	}
}
