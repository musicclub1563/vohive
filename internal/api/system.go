package api

import (
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/1239t/vohive/internal/config"
	"github.com/1239t/vohive/internal/updater"
	"github.com/1239t/vohive/pkg/logger"
	"github.com/gin-gonic/gin"
)

var errNotFound = errors.New("not found")

// resolveUninstallTargets 计算自毁流程需要清理的数据目录和配置文件路径。
// 配置文件路径必须来自运行时实际加载的路径（config.GetConfigPath()），
// 不能假定其固定位于进程工作目录下的 "config" 子目录——
// OpenWrt 部署通过 -c 显式传入 /etc/vohive/config.yaml，与工作目录无关，
// 用硬编码相对路径删除会删错地方（实际等于什么都没删）。
// configPath 为空（配置管理器未初始化）时不返回任何配置文件路径，避免误删。
func resolveUninstallTargets(configPath string) (dataDir string, configFile string) {
	return "data", configPath
}

// detectServiceStopCommands 根据当前部署形态返回应执行的"停止 + 禁用自启"命令。
// systemd 的 Restart=always 和 OpenWrt procd 的 respawn 都只在进程
// "非主动" 退出时才会重新拉起；只要在自毁前显式请求服务管理器停止/禁用，
// 即使后续删除可执行文件失败（例如只读 squashfs），也不会被重新拉起。
// 仅靠"删掉自己导致 exec 失败"这种副作用来阻止重启是不可靠的。
func detectServiceStopCommands(lookPath func(string) (string, error), statFile func(string) bool) [][]string {
	var cmds [][]string
	if statFile("/etc/init.d/vohive") {
		cmds = append(cmds, []string{"/etc/init.d/vohive", "disable"})
		cmds = append(cmds, []string{"/etc/init.d/vohive", "stop"})
		return cmds
	}
	if _, err := lookPath("systemctl"); err == nil {
		cmds = append(cmds, []string{"systemctl", "disable", "--now", "vohive"})
	}
	return cmds
}

// handleCheckUpdate 检查系统更新
func (s *Server) handleCheckUpdate(c *gin.Context) {
	info, err := updater.CheckUpdate()
	if err != nil {
		logger.Error("检查系统更新失败", "err", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, info)
}

// handleApplyUpdate 应用系统更新
func (s *Server) handleApplyUpdate(c *gin.Context) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				logger.Error("应用更新过程中发生异常", "panic", r)
			}
		}()
		if err := updater.ApplyUpdate(); err != nil {
			logger.Error("应用更新失败", "err", err)
		}
	}()
	c.JSON(http.StatusOK, gin.H{"message": "正在后台下载更新，系统稍后将自动重启..."})
}

// isUninstallAllowed 校验触发自毁/卸载请求的源地址是否可信。
// 仅允许本地回环或私有网段（RFC1918 / ULA / 链路本地，含用户经 frp 内网转发
// 访问的家庭内网地址），避免 7575 端口一旦暴露于公网就被任何人盲触发自毁。
// 额外通过 VOHIVE_UNINSTALL_ALLOW 环境变量（逗号分隔 CIDR）放行特殊拓扑，
// 例如 frp 的 p2p 直连场景（此时源是用户公网 IP）。
func isUninstallAllowed(remote string) bool {
	ip := net.ParseIP(remote)
	if ip == nil {
		// remote 可能是 host:port 形式，剥离端口再解析
		if h, _, err := net.SplitHostPort(remote); err == nil {
			ip = net.ParseIP(h)
		}
	}
	if ip == nil {
		return false
	}
	if ip.IsPrivate() || ip.IsLoopback() {
		return true
	}
	allow := strings.TrimSpace(os.Getenv("VOHIVE_UNINSTALL_ALLOW"))
	if allow == "" {
		return false
	}
	for _, cidr := range strings.Split(allow, ",") {
		cidr = strings.TrimSpace(cidr)
		if cidr == "" {
			continue
		}
		_, netCIDR, err := net.ParseCIDR(cidr)
		if err == nil && netCIDR.Contains(ip) {
			return true
		}
	}
	return false
}

// handleUninstall 自毁/卸载接口，用于用户拒绝免责声明时
func (s *Server) handleUninstall(c *gin.Context) {
	// Critical #1 修复：仅允许本地/局域网/白名单来源触发自毁，
	// 防止 7575 暴露于公网后被盲触发。
	if !isUninstallAllowed(c.ClientIP()) {
		logger.Warn("拒绝非可信来源的自毁请求", "ip", c.ClientIP())
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "仅允许本地或局域网触发卸载"})
		return
	}

	logger.Warn("用户拒绝了免责声明，正在触发自毁/卸载逻辑")
	c.JSON(http.StatusOK, gin.H{"message": "正在卸载软件..."})

	// 在后台异步执行自毁，以免请求无法返回
	go func() {
		time.Sleep(1 * time.Second)

		// 先主动通知服务管理器停止 + 禁用自启，确保即使后面的文件删除
		// 失败（只读文件系统等），systemd Restart=always / procd respawn
		// 也不会把进程重新拉起来。命令异步触发(Start 不 Wait)，
		// 避免对"停止自己"这条命令的等待造成死锁。
		for _, args := range detectServiceStopCommands(exec.LookPath, fileExists) {
			cmd := exec.Command(args[0], args[1:]...)
			if err := cmd.Start(); err != nil {
				logger.Warn("通知服务管理器停止失败", "cmd", args, "err", err)
				continue
			}
			go cmd.Wait()
		}

		dataDir, configFile := resolveUninstallTargets(config.GetConfigPath())

		if err := os.RemoveAll(dataDir); err != nil {
			logger.Warn("清理数据目录失败", "dir", dataDir, "err", err)
			// 兜底：尝试清理可执行文件同级 data 目录（防止部署时数据目录
			// 不在进程工作目录下而漏删）。
			if exe, e := os.Executable(); e == nil {
				_ = os.RemoveAll(filepath.Join(filepath.Dir(exe), "data"))
			}
		}
		if configFile != "" {
			if err := os.Remove(configFile); err != nil && !os.IsNotExist(err) {
				logger.Warn("清理配置文件失败", "file", configFile, "err", err)
			}
		}
		if executable, err := os.Executable(); err == nil {
			if err := os.Remove(executable); err != nil {
				logger.Warn("删除可执行文件失败", "file", executable, "err", err)
			}
		}

		logger.Warn("自毁流程结束，正在关闭服务并退出进程")
		// 优雅关闭 HTTP 服务以 flush 连接，避免 os.Exit 跳过 defer 造成资源泄漏。
		_ = s.Shutdown(context.Background())
		// 刷新日志缓冲，确保上述告警落盘。
		_ = logger.ZapLogger().Sync()
		os.Exit(0)
	}()
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
