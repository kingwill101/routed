#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "$project_dir/.." && pwd)"

: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required}"
: "${PULUMI_PASSPHRASE:?PULUMI_PASSPHRASE is required}"
: "${BASE_URL:?BASE_URL is required}"

export PULUMI_CONFIG_PASSPHRASE="$PULUMI_PASSPHRASE"
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(
  npx wrangler auth token --json | jq -r '.token'
)}"

if [[ -z "$CLOUDFLARE_API_TOKEN" || "$CLOUDFLARE_API_TOKEN" == "null" ]]; then
  echo 'Could not obtain CLOUDFLARE_API_TOKEN from Wrangler.' >&2
  exit 1
fi

database_id="$(
  npx wrangler d1 list --json |
    jq -r '
      (if type == "array" then .[] else (.result // [])[] end)
      | select(.name == "routed-cloudflare-auth-example")
      | (.uuid // .database_id)
    '
)"

if [[ -z "$database_id" || "$database_id" == "null" ]]; then
  echo 'Could not find the routed-cloudflare-auth-example D1 database.' >&2
  exit 1
fi

cd -- "$app_dir"
dart pub get
worker_name="${WORKER_NAME:-routed-cloudflare-auth-example}"
dart run routed_cli:routed deploy \
  --target cloudflare \
  --name "$worker_name" \
  --entry package:routed_cloudflare_auth_example/app.dart \
  --cloudflare-factory environment \
  --var "AUTH_ORIGIN=$BASE_URL" \
  --d1 "AUTH_DB=routed-cloudflare-auth-example:$database_id" \
  --durable-object RATE_LIMIT_STORE=CloudflareRateLimitStoreObject \
  --keep-vars \
  --dry-run

cd -- "$project_dir"
dart pub get
pulumi login --local --non-interactive
pulumi stack select dev \
  --create \
  --secrets-provider=passphrase \
  --non-interactive

pulumi config set accountId "$CLOUDFLARE_ACCOUNT_ID"
pulumi config set workerName "$worker_name"
pulumi config set databaseId "$database_id"
pulumi config set authOrigin "$BASE_URL"

worker_exists=false
deployments_output="$(mktemp "${TMPDIR:-/tmp}/routed-worker-deployments.XXXXXX")"
trap 'rm -f -- "$deployments_output"' EXIT
if npx wrangler deployments list --name "$worker_name" --json \
  >"$deployments_output" 2>&1; then
  deployments_json="$(<"$deployments_output")"
else
  if grep -Eqi \
    '(worker|script).*(not found|does not exist)|(not found|does not exist).*(worker|script)|10090' \
    "$deployments_output"; then
    # A missing Worker is the expected first-deployment state. Other failures
    # (authentication, connectivity, or malformed requests) must fail closed.
    deployments_json='[]'
  else
    cat "$deployments_output" >&2
    echo "Could not determine whether Worker $worker_name already exists." >&2
    exit 1
  fi
fi
if ! worker_exists="$(jq -r '
  if type == "array" then length > 0
  elif (.result? | type) == "array" then (.result | length > 0)
  else error("unexpected deployments response")
  end
' <<<"$deployments_json")"; then
  echo "Could not parse the deployments response for Worker $worker_name." >&2
  exit 1
fi

if [[ "$worker_exists" == "true" ]]; then
  pulumi config set inheritExistingBindings true
  pulumi config set applyDurableObjectMigration false
else
  session_key="${SESSION_KEY:-base64:$(openssl rand -base64 64 | tr -d '\n')}"
  pulumi config set --secret sessionKey "$session_key"
  pulumi config set inheritExistingBindings false
  pulumi config set applyDurableObjectMigration true
fi

set_optional_social_binding() {
  local public_key="$1"
  local secret_key="$2"
  local public_value="${!public_key:-}"
  local secret_value="${!secret_key:-}"

  if [[ -z "$public_value" && -z "$secret_value" ]]; then
    return
  fi
  if [[ -z "$public_value" || -z "$secret_value" ]]; then
    echo "Both $public_key and $secret_key are required together." >&2
    exit 1
  fi

  pulumi config set "$public_key" "$public_value"
  pulumi config set --secret "$secret_key" "$secret_value"
}

set_optional_social_binding GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET
set_optional_social_binding DROPBOX_CLIENT_ID DROPBOX_CLIENT_SECRET
set_optional_social_binding TELEGRAM_BOT_USERNAME TELEGRAM_BOT_TOKEN

pulumi preview --non-interactive --diff
