package tls

import (
    "bytes"
    "context"
    "io"
    "net"
    "strings"
    "testing"
    "time"
)

// Regression from MetaCubeX/utls PR #6 and SagerNet/sing-box issue #4610.
// An invalid probe keeps its client write-half open after reading the target
// response. The target's EOF must still arrive at the client promptly.
// This is deliberately a local, non-network-dependent test.
func TestRealityFallbackClosePropagated(t *testing.T) {
    dest, err := net.Listen("tcp4", "127.0.0.1:0")
    if err != nil { t.Fatal(err) }
    defer dest.Close()

    destDone := make(chan error, 1)
    go func() {
        c, err := dest.Accept()
        if err != nil { destDone <- err; return }
        defer c.Close()
        _ = c.SetDeadline(time.Now().Add(7 * time.Second))
        payload := make([]byte, 4096)
        if _, err = c.Read(payload); err != nil { destDone <- err; return }
        _, err = io.WriteString(c, "HTTP/1.1 400 Bad Request\r\nContent-Length: 3\r\nConnection: close\r\n\r\nno!")
        destDone <- err
    }()

    listener, err := net.Listen("tcp4", "127.0.0.1:0")
    if err != nil { t.Fatal(err) }
    defer listener.Close()

    cfg := &RealityConfig{
        DialContext: (&net.Dialer{Timeout: 3 * time.Second}).DialContext,
        Type: "tcp",
        Dest: dest.Addr().String(),
        ServerNames: map[string]bool{"example.com": true},
        PrivateKey: bytes.Repeat([]byte{0x42}, 32),
        ShortIds: map[[8]byte]bool{{}: true},
    }

    realityDone := make(chan error, 1)
    go func() {
        c, err := listener.Accept()
        if err != nil { realityDone <- err; return }
        _, err = RealityServer(context.Background(), c, cfg)
        realityDone <- err
    }()

    client, err := net.DialTimeout("tcp4", listener.Addr().String(), 3 * time.Second)
    if err != nil { t.Fatal(err) }
    defer client.Close()
    if _, err := io.WriteString(client, "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"); err != nil {
        t.Fatal(err)
    }

    // The probe does not close its sending side. Before the patch, io.ReadAll
    // blocks until deadline despite the target sending its final HTTP response.
    _ = client.SetReadDeadline(time.Now().Add(5 * time.Second))
    data, err := io.ReadAll(client)
    if err != nil { t.Fatalf("missing EOF from target: %v; response=%q", err, data) }
    if !strings.Contains(string(data), "400 Bad Request") {
        t.Fatalf("missing expected fallback response: %q", data)
    }

    // The patch only propagates a half-close; full relay cleanup still waits
    // until the client closes. Do not assert immediate full socket teardown.
    _ = client.Close()
    select {
    case err := <-destDone:
        if err != nil { t.Fatalf("destination: %v", err) }
    case <-time.After(3 * time.Second):
        t.Fatal("destination did not finish")
    }
    select {
    case <-realityDone:
    case <-time.After(3 * time.Second):
        t.Fatal("REALITY relay did not finish after client disconnect")
    }
}
