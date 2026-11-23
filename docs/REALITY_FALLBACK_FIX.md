# REALITY fallback EOF fix (sing-box v1.14.4)

## Baseline and scope
- Base commit: `SagerNet/sing-box v1.14.4` (`c005f35300ce76427dc285481ec5695f5b179cd2`).
- Dependency: `github.com/metacubex/utls v1.8.7` (unchanged in the repository).
- Patch: the minimal half-close propagation proposed in [MetaCubeX/utls PR #6](https://github.com/MetaCubeX/utls/pull/6).
- Issue: [SagerNet/sing-box #4610](https://github.com/SagerNet/sing-box/issues/4610).

### Why this fix
When an invalid REALITY client gets relayed to the handshake target, the target can write an HTTP/TLS error and close. In the unpatched implementation the download direction terminates, but no FIN is propagated back to the client. One upload goroutine can remain blocked reading that client's socket. This patch adds `CloseWrite()` on the underlying TCP connection immediately after the target-to-client copy ends.

### Security and behavior boundaries
- No change to normal VLESS/REALITY authentication, routing, UUIDs, private keys or 233boy JSON configuration fields.
- No changes to upstream `go.mod` or `go.sum` are committed. The build script downloads official pinned uTLS and patches a temporary copy, using a temporary `go mod edit -replace`.
- The fix propagates FIN; it **does not guarantee full teardown** if the remote client deliberately keeps its send side open, and **does not rate-limit** the inbound connection or outbound handshake to B.
- Linux amd64 is built with `release/DEFAULT_BUILD_TAGS_OTHERS`. This excludes the special Naive/Chromium-enabled official binary variant.
- Build must be tested before production; existing `sb-idle-reaper.timer` is a separate operational control. **Do not combine production deployment with a timer rewrite.**

## Master execution plan and evidence

1. **Baseline**: create `maint/v1.14.4` directly from the verified official tag SHA; create `fix/reality-fallback-close-v1.14.4` from that baseline. This keeps the fork's `testing` branch intact.
2. **Patch**: add `patches/0001-utls-reality-propagate-fallback-fin.patch`; fail build if the patch does not match exact uTLS v1.8.7.
3. **Test**: dynamically apply the patch in isolated build workspace, run `TestRealityFallbackClosePropagated` against a local bad HTTP/TLS probe with its client write-half still open. Test should fail without patch and pass after patch; this test intentionally does **not** assert that all leaked resources are reclaimed.
4. **Compile**: run `go test` on `common/tls` and `protocol/vless`, compile `sing-box` for Linux amd64, inspect its version and publish SHA-256 checksum. The upstream `TestReality` depends on Internet to `google.com` and can be enabled with `RUN_UPSTREAM_REALITY_TEST=1` for extra coverage; it is not guaranteed reliable as CI gating.
5. **Release gate**: only trust a green GitHub Actions build with downloadable `sing-box-1.14.4-realityfix.1-linux-amd64` artifact and checksum. Independent production compatibility testing remains necessary.
6. **Rollback**: keep VPS backup `/root/sing-box-backup-20261123-104415/sing-box-1.14.4` and configuration archive. Do not overwrite or expose credentials. Deploy separately with console access; rollback should restore the old binary and restart `sing-box`.

## Build locally
Requires Go 1.26.10, Git, patch, tar, sha256sum and module download access. From the fork's fix branch:

```bash
bash scripts/build-realityfix.sh
```

For a supplemental integration test (requires Internet to `google.com`):

```bash
RUN_UPSTREAM_REALITY_TEST=1 bash scripts/build-realityfix.sh
```

Build output: `dist/realityfix/sing-box` and `dist/realityfix/SHA256SUMS`.

## On the A VPS (future, after green CI and functional tests)
Do not directly install as part of a repository build. Before any production swap, confirm local `sing-box check -c /etc/sing-box/config.json -C /etc/sing-box/conf` with candidate binary, create a timestamped copy of the live binary, then replace and restart under an independent SSH/console session. After deploying, monitor `ss`, BCC inbound/handshake ratios, and the timer to establish whether the connection issue improved.

## Test matrix
| Case | Required evidence |
|---|---|
| Invalid probe, target sends 400 then FIN | Patched REALITY sends response and EOF without requiring client's FIN |
| Valid authenticated VLESS/REALITY | Existing integration test and/or operational staged trial succeeds |
| No changes to app configuration | Current JSON passes candidate `sing-box check` before install |
| Retry/unknown SNI / port mismatch | No unexpected service crashes; explicit source or logs for failures |
| Connection storm | Monitor inbound A:443/2053 vs A-to-B SYN attempts; this fix does not claim to solve rate spikes |
| Fail/rollback | Original 1.14.4 core and config remain recoverable |

## References
- https://github.com/MetaCubeX/utls/pull/6
- https://github.com/SagerNet/sing-box/issues/4610
- https://github.com/XTLS/REALITY/pull/7
