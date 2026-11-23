# sing-box 1.14.4 REALITY 回落修复版使用说明

> **状态：已可使用（2026-11-23）。** 该非官方版本已通过 CI 构建和回落关闭回归测试，并在用户的 Linux VPS 实机部署。用户反馈修复成功。它仍是公开的预发布版本，不代表已经完成长期稳定性压测。

## 1. 这次修复了什么？

针对 [SagerNet/sing-box #4610](https://github.com/SagerNet/sing-box/issues/4610) 中 REALITY 回落连接不能正确向客户端传递目标关闭信号的问题，采用 [MetaCubeX/utls PR #6](https://github.com/MetaCubeX/utls/pull/6) 的最小修改：当回落目标的下载方向结束时，通过 TCP `CloseWrite()` 向客户端传递 FIN。

**注意边界：**

- 修复的是关闭信号传播，**不保证**恶意客户端始终不关闭时全部服务器资源立刻释放。
- **不限制**新建连接速率，也不直接解决 A→B 突发建连；这部分需要单独监测。
- 不更改 UUID、REALITY 密钥、路由和现有配置格式。
- 目前只发布 **Linux amd64** 核心，使用不含 NaiveProxy 出站的非 Naive 构建标签；其他平台和功能组合尚未验证。

## 2. 下载已构建版本（VPS 直接下载）

**公开下载：** [v1.14.4-realityfix.1](https://github.com/LE-saber/sing-box/releases/tag/v1.14.4-realityfix.1)。无需 GitHub 登录或 Windows 电脑中转。

以下命令在 Linux amd64 VPS 上执行，**只下载、验证，不会替换当前服务**：

```bash
set -e
DIR=/root/sb-realityfix
BASE=https://github.com/LE-saber/sing-box/releases/download/v1.14.4-realityfix.1
FILE=sing-box-1.14.4-realityfix.1-linux-amd64.tar.gz

sudo mkdir -p "$DIR"
cd "$DIR"
sudo wget -c "$BASE/$FILE" "$BASE/$FILE.sha256"
sudo sha256sum -c "$FILE.sha256"
sudo tar -xzf "$FILE"
sudo sha256sum -c SHA256SUMS
sudo chmod 755 sing-box
sudo ./sing-box version | head -n 1
sudo ./sing-box check -c /etc/sing-box/config.json -C /etc/sing-box/conf
```

预期显示 `sing-box version 1.14.4-realityfix.1`，且两个 `sha256sum` 都返回 `OK`，配置检查无错误。路径采用 233boy 常见的 `/etc/sing-box` 安装结构；其他安装方式应先确认服务真实执行路径。

## 3. 安装（先备份，独立 SSH 会话）

如果你尚未部署修复版，首先检查 `systemctl cat sing-box` 中的 `ExecStart`，确认服务确实运行 `/etc/sing-box/bin/sing-box`。仅在确认下载、校验和配置检查通过后执行：

```bash
sudo bash <<'SH'
set -euo pipefail
BIN=/etc/sing-box/bin/sing-box
NEW=/root/sb-realityfix/sing-box
BACKUP="/root/sing-box-maintenance/backups/before-realityfix-$(date +%Y%m%d-%H%M%S)"

mkdir -p -m 700 "$BACKUP"
cp -a "$BIN" "$BACKUP/sing-box"
tar -czf "$BACKUP/config.tar.gz" -C /etc/sing-box config.json conf

"$NEW" version | grep -Fq '1.14.4-realityfix.1'
"$NEW" check -c /etc/sing-box/config.json -C /etc/sing-box/conf
install -m 755 "$NEW" "$BIN.new"
mv -f "$BIN.new" "$BIN"

if ! systemctl restart sing-box || ! systemctl is-active --quiet sing-box; then
  install -m 755 "$BACKUP/sing-box" "$BIN.restore"
  mv -f "$BIN.restore" "$BIN"
  systemctl reset-failed sing-box
  systemctl restart sing-box
  echo '修复版未正常启动，已尝试恢复备份' >&2
  exit 1
fi
sleep 5
if ! systemctl is-active --quiet sing-box; then
  install -m 755 "$BACKUP/sing-box" "$BIN.restore"
  mv -f "$BIN.restore" "$BIN"
  systemctl reset-failed sing-box
  systemctl restart sing-box
  echo '修复版启动后异常，已尝试恢复备份' >&2
  exit 1
fi

"$BIN" version | head -n 1
systemctl is-active sing-box
echo "回滚备份：$BACKUP"
SH
```

替换核心会短暂中断现有代理连接。不要通过完全依赖此代理的远程通道执行。

## 4. 实机验证和监控

检查正常客户端是否能使用原有 REALITY 入站，并验证相关路由功能。查看服务：

```bash
/etc/sing-box/bin/sing-box version | head -n 1
systemctl is-active sing-box
sudo ss -lntp | grep sing-box
sudo journalctl -u sing-box --since '10 minutes ago' --no-pager
ps -C sing-box -o pid,etime,%cpu,%mem,rss
```

在先前实机部署日志中，`1.14.4-realityfix.1` 已正常运行、服务显示 `active`，TCP 443、4433、2053 端口监听正常；用户随后确认修复有效。**尚未保存完整的定量对比抓包或长期压测数据。**

若环境安装了额外的 `sb-idle-reaper.timer`，它本身也可能关闭长时间闲置的正常连接或触发紧急重启。评估修复版的连接释放效果时应单独记录该定时器状态，不能将所有连接数变化归功于修复版。

## 5. 回滚和备份说明

首次安装修复版之前的官方 `1.14.4` 二进制必须保留。**不要直接取“最新备份”**：如果多次安装，新备份里可能已经是修复版。

已有部署中的首次官方版回滚记录为：

`sb-before-fix-20261123-124843/sing-box`

它可能保留在 `/root/`，也可能被整理到 `/root/sing-box-maintenance/backups/`。先执行 `<备份文件>/sing-box version`，确认版本是 `1.14.4`，再用于恢复。

一般回滚命令（把 `BACKUP` 改成**真实且已验证的官方备份目录**）：

```bash
BACKUP=/root/sing-box-maintenance/backups/sb-before-fix-20261123-124843
sudo "$BACKUP/sing-box" version | head -n 1
sudo install -m 755 "$BACKUP/sing-box" /etc/sing-box/bin/sing-box.restore
sudo mv -f /etc/sing-box/bin/sing-box.restore /etc/sing-box/bin/sing-box
sudo systemctl reset-failed sing-box
sudo systemctl restart sing-box
sudo systemctl is-active sing-box
```

如备份实际位于其他路径，应先更正 `BACKUP`；不存在时不要执行恢复。当前版本没有要求迁移配置文件，通常只需恢复二进制。

## 6. 源码、构建与验证证据

- [修复分支](https://github.com/LE-saber/sing-box/tree/fix/reality-fallback-close-v1.14.4)
- [补丁](../patches/0001-utls-reality-propagate-fallback-fin.patch)
- [构建脚本](../scripts/build-realityfix.sh)：构建过程中在临时模块目录应用补丁，仓库 `go.mod` / `go.sum` 不变
- [CI 成功记录](https://github.com/LE-saber/sing-box/actions/runs/45177059834)
- [英文技术说明](REALITY_FALLBACK_FIX.md)
- [PR #1](https://github.com/LE-saber/sing-box/pull/1)

**说明：** Fork 默认 `testing` 分支不是本修复版的源码分支；需要重新构建时，应检出 `fix/reality-fallback-close-v1.14.4` 并执行 `bash scripts/build-realityfix.sh`。公开 Release 中的文件是 GitHub Actions 产出的、已校验的二进制。
