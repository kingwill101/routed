# HTTP/2 Example

This directory hosts a minimal TLS-enabled server showcasing Routed's HTTP/2 support and the tooling needed to test it
locally.

## Prerequisites

- Dart SDK installed
- OpenSSL available on your PATH (`openssl` command)
- `curl` ≥ 7.43 (must support `--http2` and ALPN)

## Generate Self-Signed Certificates

The example ships with a SAN-enabled self-signed certificate covering `localhost`, `127.0.0.1`, and `::1`. To regenerate
it:

```bash
cat <<'EOF' > openssl-san.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
C  = US
ST = Local
L  = Local
O  = RoutedDev
CN = localhost

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
IP.1  = 127.0.0.1
IP.2  = ::1
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem -config openssl-san.cnf
rm openssl-san.cnf
```

This produces `cert.pem` and `key.pem` in the directory. Keep them out of version control in production; they are purely
for local testing.

## Run the Server

From this directory:

```bash
dart bin/server.dart
```

You should see:

```
Secure server listening on https://localhost:4043 (HTTP/2 enabled)
```

### Configure via Manifest

Instead of toggling HTTP/2 in code you can add the following to your project’s `config/http.yaml`:

```yaml
http:
  http2:
    enabled: true
    allow_cleartext: false
    max_concurrent_streams: 256
    idle_timeout: 30s
  tls:
    certificate_path: cert.pem
    key_path: key.pem
    password:
    request_client_certificate: false
    shared: false
    v6_only: false
```

The example sets these values directly via `EngineConfig`, but the manifest option keeps secrets/config out of code.
When `http.tls.*` is populated you can call `engine.serveSecure()` without passing paths.

## Verify with curl

Use `curl` with HTTP/2 and the generated CA:

```bash
curl --http2 --tlsv1.2 --cacert cert.pem https://localhost:4043/ -v
```

Expected output includes:

- `ALPN: server accepted h2`
- `HTTP/2 200`
- Body: `Hello World`

If you need to test fallback behavior, remove `--http2` or force HTTP/1.1 with `--http1.1`.
