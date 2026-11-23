# sing-box

> **Unofficial REALITY fallback hotfix / 非官方 REALITY 回落连接修复版**
>
> **Status (2026-11-23): built and field-deployed; user reports the fix works.**
> The `v1.14.4-realityfix.1` Linux amd64 build passed CI and was confirmed running with the existing VPS configuration. This is **not** an official SagerNet release or a claim of long-term production validation.
>
> **状态（2026-11-23）：已构建、已实机部署，用户确认修复有效。**
> 本版本仍为非官方测试发布，不代表所有异常连接都能被回收，也不意味着已经完成长期稳定性验证。

## REALITY fallback hotfix / 修复版

- **Public build / 公开下载：** [v1.14.4-realityfix.1 (Linux amd64)](https://github.com/LE-saber/sing-box/releases/tag/v1.14.4-realityfix.1)
- **中文部署说明：** [REALITY 修复版使用与回滚](docs/REALITY_FALLBACK_FIX.zh-CN.md)
- **Technical details (English):** [REALITY fallback FIN fix](docs/REALITY_FALLBACK_FIX.md)
- **Source branch:** [`fix/reality-fallback-close-v1.14.4`](https://github.com/LE-saber/sing-box/tree/fix/reality-fallback-close-v1.14.4), based on upstream `v1.14.4`.
- **CI evidence:** [GitHub Actions successful build](https://github.com/LE-saber/sing-box/actions/runs/45177059834)

The patch applies [MetaCubeX/utls PR #6](https://github.com/MetaCubeX/utls/pull/6) to the pinned uTLS dependency **at build time**. When a REALITY fallback target closes, the server propagates its FIN to the client via `CloseWrite()`. Existing VLESS/REALITY configuration fields are unchanged. **This is not a new-connection rate limiter or a guaranteed cleanup for clients that ignore FIN.** The default `testing` branch does not contain the hotfix source; use the hotfix branch and its dedicated build script.

### Quick verification (Linux amd64)

```bash
BASE=https://github.com/LE-saber/sing-box/releases/download/v1.14.4-realityfix.1
FILE=sing-box-1.14.4-realityfix.1-linux-amd64.tar.gz
mkdir -p ~/sb-realityfix && cd ~/sb-realityfix
wget -c "$BASE/$FILE" "$BASE/$FILE.sha256"
sha256sum -c "$FILE.sha256"
tar -xzf "$FILE"
sha256sum -c SHA256SUMS
chmod +x sing-box
./sing-box version
```

Do not replace an active proxy binary until its actual configuration has passed `sing-box check` and a rollback copy is available. See the deployment guide above.

---

The universal proxy platform.

[![Packaging status](https://repology.org/badge/vertical-allrepos/sing-box.svg)](https://repology.org/project/sing-box/versions)

## Documentation

https://sing-box.sagernet.org

## License

```
Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.

In addition, no derivative work may use the name or imply association
with this application without prior consent.
```