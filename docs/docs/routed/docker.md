# Docker Deployment Guide for Routed

This guide explains how to containerize and deploy your Routed backend application.

## Quick Start

```bash
# Build the image
docker build -t my-routed-app .

# Run the container
docker run -p 8080:8080 my-routed-app

# Or use docker-compose
docker compose up -d
```

## Files Overview

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage production build |
| `.dockerignore` | Excludes unnecessary files from build |
| `docker-compose.yml` | Orchestration for local dev/prod |

## Dockerfile Stages

### Stage 1: Dependencies
Caches `pubspec.yaml` and `pubspec.lock` to speed up rebuilds when only source code changes.

### Stage 2: Build
Compiles the Dart application to a native AOT executable for optimal performance:
- Faster cold starts (~50ms vs ~500ms for JIT)
- Lower memory footprint
- No runtime dependency on Dart SDK

### Stage 3: Runtime
Minimal Debian image with only essential runtime dependencies:
- `ca-certificates` - HTTPS support
- `tzdata` - Timezone support
- `curl` - Health checks

## Configuration

### Build Arguments

```bash
docker build \
  --build-arg DART_VERSION=3.9 \
  --build-arg APP_NAME=server \
  -t my-app .
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_ENV` | `production` | Application environment |
| `APP_DEBUG` | `false` | Enable debug mode |
| `HOST` | `0.0.0.0` | Server bind address |
| `PORT` | `8080` | Server port |

### Runtime Configuration

```bash
docker run -p 8080:8080 \
  -e APP_ENV=staging \
  -e APP_DEBUG=true \
  my-routed-app
```

## Health Checks

The container includes a built-in health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

Ensure your app exposes a `/health` endpoint:

```dart
engine.get('/health', (ctx) async {
  return ctx.json({
    'status': 'healthy',
    'timestamp': DateTime.now().toIso8601String(),
  });
});
```

## Production Best Practices

### 1. Security
- Runs as non-root user (`appuser`)
- Minimal base image reduces attack surface
- No unnecessary tools installed

### 2. Performance
- AOT compilation for fast startup
- Multi-stage build keeps final image small (~50MB)
- Layer caching for faster rebuilds

### 3. Persistence
Mount volumes for data that needs to persist:

```yaml
volumes:
  - app-storage:/app/storage
```

### 4. Secrets
Use environment variables or Docker secrets:

```yaml
environment:
  - DB_PASSWORD=${DB_PASSWORD}
```

Or with Docker secrets:

```yaml
secrets:
  - db_password
```

## Development Workflow

### Local Development (without Docker)
```bash
dart run routed_cli dev
```

### Development with Docker
```bash
# Build and run with live logs
docker compose up --build

# Run in background
docker compose up -d

# View logs
docker compose logs -f app

# Stop
docker compose down
```

## Adding Services

### PostgreSQL Database

Uncomment in `docker-compose.yml`:

```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${DB_DATABASE:-app}
      POSTGRES_USER: ${DB_USERNAME:-postgres}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
    volumes:
      - postgres-data:/var/lib/postgresql/data
```

### Redis Cache

```yaml
services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
```

## Deployment Examples

### Docker Swarm

```bash
docker stack deploy -c docker-compose.yml my-app
```

### Kubernetes

Convert to K8s manifests:

```bash
kompose convert -f docker-compose.yml
```

### Cloud Platforms

**Google Cloud Run:**
```bash
gcloud run deploy my-app \
  --image gcr.io/PROJECT/my-app \
  --port 8080
```

**AWS ECS/Fargate:**
Use the Dockerfile with your ECS task definition.

**Fly.io:**
```bash
fly launch
fly deploy
```

## Troubleshooting

### Container won't start
Check logs: `docker logs <container_id>`

### Health check failing
1. Ensure `/health` endpoint exists
2. Check if app binds to `0.0.0.0` (not `127.0.0.1`)
3. Verify PORT environment variable

### Build fails
1. Check Dart version compatibility
2. Ensure all dependencies resolve: `dart pub get`
3. Verify `bin/server.dart` exists

### Image too large
1. Ensure `.dockerignore` is present
2. Check for large files in build context
3. Use `docker image history` to find large layers
