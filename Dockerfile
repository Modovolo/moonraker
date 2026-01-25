# Moonraker Dockerfile for Fleet Deployment
# Multi-stage build for optimized container size
#
# Moonraker is the API server for Klipper 3D printer firmware
# https://github.com/Arksine/moonraker

ARG PYTHON_VERSION=3.11

# ---- Builder Stage ----
FROM python:${PYTHON_VERSION}-slim-bookworm AS builder

LABEL org.opencontainers.image.source="https://github.com/Arksine/moonraker"
LABEL org.opencontainers.image.description="Moonraker - API Server for Klipper"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libffi-dev \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    libopenjp2-7-dev \
    libcap-dev \
    libsodium-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy moonraker source
COPY . /build/moonraker

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip wheel setuptools

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy and install requirements from pyproject.toml dependencies
# These are the core dependencies from moonraker's pyproject.toml
RUN pip install --no-cache-dir \
    "tornado>=6.2,<6.5.2" \
    "pyserial>=3.4" \
    "pyserial-asyncio>=0.6" \
    "pillow>=9.0.0" \
    "streaming-form-data>=1.11.0" \
    "distro>=1.7.0" \
    "inotify-simple>=1.3.5" \
    "libnacl>=1.8.0" \
    "paho-mqtt>=1.6.1" \
    "zeroconf>=0.36.0" \
    "apprise>=1.2.1" \
    "ldap3>=2.9.1" \
    "jinja2>=3.1.2" \
    "python-periphery>=2.3.0" \
    "requests>=2.28.0" \
    "lmdb>=1.4.0" \
    "dbus-fast>=1.90.1" \
    "preprocess-cancellation>=0.2.0"

# Install moonraker package
RUN pip install --no-cache-dir /build/moonraker

# ---- Runtime Stage ----
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

LABEL org.opencontainers.image.source="https://github.com/Arksine/moonraker"
LABEL org.opencontainers.image.description="Moonraker - API Server for Klipper"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcap2 \
    libjpeg62-turbo \
    libopenjp2-7 \
    libsodium23 \
    zlib1g \
    curl \
    iproute2 \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    # Create moonraker user
    && useradd -ms /bin/bash -u 1000 moonraker \
    # Create printer_data directory structure
    && mkdir -p /printer_data/config \
    && mkdir -p /printer_data/gcodes \
    && mkdir -p /printer_data/logs \
    && mkdir -p /printer_data/comms \
    && mkdir -p /printer_data/database \
    && mkdir -p /printer_data/certs \
    && chown -R moonraker:moonraker /printer_data

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy moonraker source (needed for assets and components)
COPY --from=builder /build/moonraker /opt/moonraker

WORKDIR /opt/moonraker

# Environment variables
ENV MOONRAKER_DATA_PATH=/printer_data
ENV MOONRAKER_CONFIG_PATH=/printer_data/config/moonraker.conf
ENV PYTHONUNBUFFERED=1

# Expose port
EXPOSE 7125

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:7125/server/info || exit 1

# Switch to non-root user
USER moonraker

# Default command
ENTRYPOINT ["python", "-m", "moonraker"]
CMD ["--datapath", "/printer_data", "--config", "/printer_data/config/moonraker.conf"]
