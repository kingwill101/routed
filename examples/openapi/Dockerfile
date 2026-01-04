# ============================================================================
# Routed Backend Dockerfile
# Multi-stage build for optimized production deployment
# ============================================================================

# Build Arguments
ARG DART_VERSION=3.9
ARG APP_NAME=server

# ============================================================================
# Stage 1: Dependencies
# Cache dependencies separately for faster rebuilds
# ============================================================================
FROM dart:${DART_VERSION} AS dependencies

WORKDIR /app

# Copy only dependency files first (for better layer caching)
COPY pubspec.* ./

# Get dependencies
RUN dart pub get

# ============================================================================
# Stage 2: Build
# Compile the application to a native executable
# ============================================================================
FROM dart:${DART_VERSION} AS build

WORKDIR /app

# Copy cached dependencies from previous stage
COPY --from=dependencies /app/.dart_tool /app/.dart_tool
COPY --from=dependencies /app/pubspec.lock /app/pubspec.lock

# Copy pubspec files
COPY pubspec.* ./

# Get dependencies (will use cache from pubspec.lock)
RUN dart pub get --offline || dart pub get

# Copy source code
COPY . .

# Compile to native executable for best performance
# AOT compilation produces a single, fast-starting executable
RUN dart compile exe bin/${APP_NAME}.dart -o bin/${APP_NAME}

# ============================================================================
# Stage 3: Runtime
# Minimal production image
# ============================================================================
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
# - ca-certificates: For HTTPS connections
# - tzdata: For timezone support
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid appuser --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy the compiled executable
ARG APP_NAME=server
COPY --from=build /app/bin/${APP_NAME} /app/server

# Copy configuration files
COPY --from=build /app/config/ /app/config/

# Create storage directories with proper permissions
RUN mkdir -p /app/storage/logs /app/storage/cache /app/storage/sessions \
    && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Environment variables
ENV APP_ENV=production
ENV APP_DEBUG=false
ENV HOST=0.0.0.0
ENV PORT=8080

# Expose the application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the server
ENTRYPOINT ["/app/server"]
