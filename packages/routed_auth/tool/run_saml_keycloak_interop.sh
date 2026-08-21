#!/usr/bin/env bash
set -euo pipefail

readonly keycloak_image='quay.io/keycloak/keycloak:26.7.1@sha256:f1f1f01e472c8a78df40d8f2a49a925274eda4d3d80d5f6edbb5c880ee3c01c6'
readonly tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly package_dir="$(cd "$tool_dir/.." && pwd)"
readonly realm_source="$tool_dir/saml_keycloak/realm.json"

for command_name in dart docker openssl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 2
  fi
done

if ! docker info >/dev/null 2>&1; then
  printf 'Docker is installed but its daemon is unavailable.\n' >&2
  exit 2
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/routed-saml-keycloak.XXXXXXXX")"
container_name="routed-saml-keycloak-$$-$(date +%s)"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if ((exit_code != 0)) && docker inspect "$container_name" >/dev/null 2>&1; then
    docker logs --tail 200 "$container_name" >&2 || true
  fi
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  if [[ "$temp_dir" == "${TMPDIR:-/tmp}"/routed-saml-keycloak.* && -d "$temp_dir" ]]; then
    find "$temp_dir" -depth -delete
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

cp "$realm_source" "$temp_dir/realm.json"
openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 1 \
  -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  -keyout "$temp_dir/tls.key" \
  -out "$temp_dir/tls.crt" \
  >/dev/null 2>&1
chmod 0644 "$temp_dir/realm.json" "$temp_dir/tls.key" "$temp_dir/tls.crt"

docker run \
  --detach \
  --rm \
  --name "$container_name" \
  --label dev.routed.saml-interop=true \
  --publish '127.0.0.1::8443' \
  --volume "$temp_dir/realm.json:/opt/keycloak/data/import/routed-saml-realm.json:ro" \
  --volume "$temp_dir/tls.crt:/opt/keycloak/conf/tls.crt:ro" \
  --volume "$temp_dir/tls.key:/opt/keycloak/conf/tls.key:ro" \
  "$keycloak_image" \
  start-dev \
  --import-realm \
  --http-enabled=false \
  --https-certificate-file=/opt/keycloak/conf/tls.crt \
  --https-certificate-key-file=/opt/keycloak/conf/tls.key \
  >/dev/null

port_mapping="$(docker port "$container_name" 8443/tcp)"
host_port="${port_mapping##*:}"
if [[ ! "$host_port" =~ ^[0-9]+$ ]]; then
  printf 'Unable to resolve the Keycloak host port from: %s\n' "$port_mapping" >&2
  exit 1
fi

printf 'Keycloak image: %s\n' "$keycloak_image"
printf 'Keycloak endpoint: https://127.0.0.1:%s\n' "$host_port"

(
  cd "$package_dir"
  dart run tool/saml_keycloak_interop.dart \
    --keycloak-base-url "https://127.0.0.1:$host_port"
)
