# Multi-stage Containerfile for Podman
# Deno + Rust/WASM + Haskell + ReScript

# Stage 1: Build Rust WASM modules
FROM rust:1.75-alpine AS wasm-builder

WORKDIR /build

# Install wasm target
RUN rustup target add wasm32-unknown-unknown && \
    apk add --no-cache musl-dev

# Copy Rust source
COPY wasm-modules/Cargo.toml wasm-modules/Cargo.lock* ./
COPY wasm-modules/src ./src

# Build WASM
RUN cargo build --release --target wasm32-unknown-unknown

# Stage 2: Build Haskell validator
FROM haskell:9.2-slim AS haskell-builder

WORKDIR /validator

# Copy Haskell source
COPY validator/validator-bridge.cabal ./
COPY validator/*.hs ./

# Build Haskell validator
RUN cabal update && \
    cabal build && \
    cabal install --installdir=/usr/local/bin

# Stage 3: Build ReScript
FROM denoland/deno:alpine-1.40.0 AS rescript-builder

WORKDIR /app

# Copy ReScript config
COPY bsconfig.json package.json* ./

# Install ReScript and build
RUN if [ -f package.json ]; then \
    apk add --no-cache npm && \
    npm ci && \
    npm run build; \
    fi

# Stage 4: Final runtime image with Deno
FROM denoland/deno:alpine-1.40.0

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tini \
    curl

# Copy WASM modules
COPY --from=wasm-builder /build/target/wasm32-unknown-unknown/release/recon_wasm.wasm ./src/wasm/hasher.wasm

# Copy Haskell validator
COPY --from=haskell-builder /usr/local/bin/validator-bridge /usr/local/bin/

# Copy ReScript compiled output
COPY --from=rescript-builder /app/lib ./lib

# Copy Deno source and configuration
COPY deno.json deno.lock* ./
COPY src ./src
COPY scripts ./scripts

# Cache Deno dependencies
RUN deno cache --lock=deno.lock src/main.ts

# Copy configuration files
COPY justfile ./
COPY examples ./examples

# Create data directory
RUN mkdir -p /data && \
    chmod 777 /data

# Set environment variables
ENV DENO_DIR=/deno-dir
ENV ARANGO_URL=http://arangodb:8529
ENV ARANGO_DATABASE=reconciliation

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--"]

# Default command
CMD ["deno", "run", "--allow-all", "src/main.ts", "help"]

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD deno eval "console.log('healthy')" || exit 1

# Labels
LABEL org.opencontainers.image.title="recon-silly-ation"
LABEL org.opencontainers.image.description="Documentation Reconciliation System (Deno + WASM)"
LABEL org.opencontainers.image.version="0.2.0"
LABEL org.opencontainers.image.authors="Hyperpolymath"
LABEL org.opencontainers.image.source="https://github.com/Hyperpolymath/recon-silly-ation"
