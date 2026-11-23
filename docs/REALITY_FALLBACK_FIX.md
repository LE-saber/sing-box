# REALITY fallback FIN fix — sing-box v1.14.4

**Status (2026-11-23): public test release available; deployed and reported working on the user's VPS.**

- [Public prerelease v1.14.4-realityfix.1](https://github.com/LE-saber/sing-box/releases/tag/v1.14.4-realityfix.1) — Linux amd64, direct download with no GitHub authentication
- [Successful build/test/publish workflow](https://github.com/LE-saber/sing-box/actions/runs/45177059834)
- [中文部署与回滚说明](REALITY_FALLBACK_FIX.zh-CN.md)

**Evidence scope:** The CI logs confirm a local fallback EOF regression, TLS/VLESS package tests, binary compilation and archive SHA-256 verification. The field deployment log showed `sing-box version 1.14.4-realityfix.1`, an active systemd unit, and active listeners on TCP 443, 4433 and 2053. The operator subsequently reported that the fix worked and the proxy was usable. A packet-level before/after capture and long-running stability benchmark have not been published; do not extrapolate one successful field deployment into proof against every probe pattern.

## Background

Upstream issue: [SagerNet/sing-box #4610](https://github.com/SagerNet/sing-box/issues/4610).
Proposed dependency patch: [MetaCubeX/utls PR #6](https://github.com/MetaCubeX/utls/pull/6).

In the original invalid-REALITY-client fallback flow, the handshake destination may send an error and close, while the server-to-client relay does not propagate that TCP close to the client. If the probing client keeps its sending direction open, an upload copy may remain blocked. This is both a connection-lifetime problem and a remotely observable discrepancy.

The narrow patch adds a `CloseWrite()` after the destination-to-client `io.Copy` finishes, forwarding the destination's FIN to the client without requiring the client to close first.

### Source and compatibility

- Base: official `SagerNet/sing-box v1.14.4`, commit `c005f35300ce76427dc285481ec5695f5b179cd2`.
- Maintenance ref: `maint/v1.14.4`; fix ref: `fix/reality-fallback-close-v1.14.4`.
- Pinned dependency: `github.com/metacubex/utls v1.8.7`.
- Minimal upstream-derived patch: [patches/0001-utls-reality-propagate-fallback-fin.patch](../patches/0001-utls-reality-propagate-fallback-fin.patch).
- Build script: [scripts/build-realityfix.sh](../scripts/build-realityfix.sh). It extracts a clean source archive and patches an isolated local uTLS module, then compiles against that local copy; the repository `go.mod` and `go.sum` remain unchanged.
- Platform: Linux amd64; Go 1.26.10; CGO disabled; build tags taken from `release/DEFAULT_BUILD_TAGS_OTHERS`. This artifact is not the official NaiveProxy/Chromium-enabled binary.
- Existing VLESS/REALITY authentication, UUIDs, TLS options, outbound routes and 233boy JSON configuration fields are not changed by the patch.

## Verified and unverified results

| Check | Evidence / status |
| --- | --- |
| Apply PR #6 to pinned uTLS v1.8.7 without fuzz | CI: passed |
| `TestRealityFallbackClosePropagated` using local HTTP error and target EOF | CI: passed |
| `go test` on `./common/tls` and `./protocol/vless` | CI: passed |
| Compile Linux amd64 and verify version string | CI: passed |
| SHA-256 for archive and executable | CI generated, checked in publish job |
| Real VPS: configuration check | Operator command output: passed |
| Real VPS: installed binary, active service, inbound port listeners | Operator command output: passed (2026-11-23) |
| Real VPS: fix solves observed issue / usable | Operator explicitly reported successful fix |
| External `TestReality` against google.com | Not part of CI gating; requires network access |
| Quantitative long-run socket/flood/resource benchmark | Not yet collected |

## Download and verify without Windows transfer

The archive and separate checksum are public on GitHub Release. On the target Linux amd64 machine:

```bash
set -e
BASE=https://github.com/LE-saber/sing-box/releases/download/v1.14.4-realityfix.1
FILE=sing-box-1.14.4-realityfix.1-linux-amd64.tar.gz
mkdir -p "$HOME/sb-realityfix"
cd "$HOME/sb-realityfix"
wget -c "$BASE/$FILE" "$BASE/$FILE.sha256"
sha256sum -c "$FILE.sha256"
tar -xzf "$FILE"
sha256sum -c SHA256SUMS
chmod +x sing-box
./sing-box version
```

Expected: `sing-box version 1.14.4-realityfix.1`; both checksum checks say `OK`.

To check a typical 233boy installation (adapt paths if different):

```bash
./sing-box check -c /etc/sing-box/config.json -C /etc/sing-box/conf
```

**Do not overwrite a running binary before confirming this check and creating a backup.** The [Chinese runbook](REALITY_FALLBACK_FIX.zh-CN.md) covers safe deployment, monitoring and rollback.

## Build from source

Requires Git, Go 1.26.10, GNU patch, tar, sha256sum and module download access. From the fix branch:

```bash
bash scripts/build-realityfix.sh
```

Build output: `dist/realityfix/sing-box` and `dist/realityfix/SHA256SUMS`.

An additional upstream end-to-end integration test can be requested with `RUN_UPSTREAM_REALITY_TEST=1`, but it depends on public external access to `google.com` and is not part of the deterministic CI gate.

## Runtime limitations and monitoring

1. **Half-close is not the same as forced socket destruction.** A client that ignores the FIN may leave other resources alive. This is not a hard idle timeout.
2. The patch does **not** cap new probe connections or the rate of A-to-fallback-target outbound connections. Investigate spikes separately.
3. An independent external idle reaper (if installed by the operator) may close inactive legitimate proxy sessions and, if configured, restart the entire process. Do not attribute every connection decrease to this patch while the reaper is active.
4. During staged validation, check active client traffic, `systemctl is-active sing-box`, `ss -lntp`, TCP state counts and resident memory. Compare to baseline without changing routing or REALITY credentials.
5. Save a known-good original `1.14.4` executable before the swap. Revert by restoring that exact file and restarting `sing-box` from an independent SSH/console session. **Do not select the newest backup blindly**: a second installation may have backed up the patched build.

## Licensing and disclaimer

This is an **unofficial fork build**, not an upstream SagerNet release. It is available for use with explicit understanding of the limitations above. Preserve the upstream licensing notices and inspect changes before deploying on production systems.

## References

- https://github.com/SagerNet/sing-box/issues/4610
- https://github.com/MetaCubeX/utls/pull/6
- https://github.com/LE-saber/sing-box/pull/1
