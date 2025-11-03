# Build stage
FROM hexpm/elixir:1.15.7-erlang-26.1.2-debian-bookworm-20240130-slim AS build

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential git curl && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before compiling dependencies
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Compile the application FIRST (generates phoenix-colocated hooks)
COPY lib lib
RUN mix compile

# THEN copy assets and compile them (can now find phoenix-colocated hooks)
COPY priv priv
COPY assets assets
RUN mix assets.deploy

# Generate release
COPY config/runtime.exs config/
RUN mix release

# Start a new build stage
FROM debian:bookworm-slim AS app

# Cache buster: 2025-11-03-03:48-fix-tls-certs
# Install runtime dependencies (including ca-certificates for TLS/SSL)
RUN apt-get update && \
    apt-get install -y libstdc++6 openssl locales ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Set environment
ENV USER="elixir"
ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

# Create user (Debian syntax)
RUN groupadd --gid 1000 ${USER} && \
    useradd --uid 1000 --gid ${USER} --shell /bin/sh --create-home ${USER}

WORKDIR /app

# Set runner ENV
ENV HOME=/app

# Copy built application
COPY --from=build --chown=${USER}:${USER} /app/_build/${MIX_ENV}/rel/jump_email_categorization ./

USER ${USER}

# Expose port (Cloud Run will override this)
EXPOSE 4000

# Start the release
CMD ["bin/jump_email_categorization", "start"]

