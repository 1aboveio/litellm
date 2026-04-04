# syntax=docker/dockerfile:1
# Base image for building
ARG LITELLM_BUILD_IMAGE=cgr.dev/chainguard/wolfi-base
# Runtime image
ARG LITELLM_RUNTIME_IMAGE=cgr.dev/chainguard/wolfi-base
# Builder stage
FROM $LITELLM_BUILD_IMAGE AS builder
ARG LITELLM_BUILD_IMAGE
ARG LITELLM_RUNTIME_IMAGE
WORKDIR /app
USER root
# Install build dependencies
RUN apk add --no-cache bash gcc py3-pip python3 python3-dev openssl openssl-dev
RUN python -m pip install build
# Copy the current directory contents into the container at /app
COPY . .
# Build Admin UI
# Convert Windows line endings to Unix and make executable
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && chmod +x docker/build_admin_ui.sh && ./docker/build_admin_ui.sh
# Build the package
RUN rm -rf dist/* && python -m build
# Install the built wheel using pip; again using a wildcard if it's the only file
RUN pip install dist/*.whl --no-index --find-links=/wheels/
# Replace the nodejs-wheel-binaries bundled node with the system node (fixes CVE-2025-55130)
RUN NODEJS_WHEEL_NODE=$(find /usr/lib -path "*/nodejs_wheel/bin/node" 2>/dev/null) && \
    if [ -n "$NODEJS_WHEEL_NODE" ]; then cp /usr/bin/node "$NODEJS_WHEEL_NODE"; fi
# Runtime stage
FROM $LITELLM_RUNTIME_IMAGE
# Set the working directory to /app
WORKDIR /app
# Copy built artifacts from builder
COPY --from=builder /app/dist/*.whl .
COPY --from=builder /wheels/ /wheels/
# Install runtime dependencies (libsndfile needed for audio processing on ARM64)
RUN apk add --no-cache bash openssl tzdata nodejs npm python3 py3-pip libsndfile && \
    npm install -g npm@latest tar@7.5.11 glob@11.1.0 @isaacs/brace-expansion@5.0.1 minimatch@10.2.4 diff@8.0.3 && \
    pip install *.whl /wheels/* --no-index --find-links=/wheels/ && rm -f *.whl && rm -rf /wheels
# Replace the nodejs-wheel-binaries bundled node with the system node (fixes CVE-2025-55130)
RUN NODEJS_WHEEL_NODE=$(find /usr/lib -path "*/nodejs_wheel/bin/node" 2>/dev/null) && \
    if [ -n "$NODEJS_WHEEL_NODE" ]; then cp /usr/bin/node "$NODEJS_WHEEL_NODE"; fi
EXPOSE 4000/tcp
ENV TEXT_COMPLETION_CALL_LOGGING="False"
CMD ["gunicorn", "litellm:proxy_server", "--bind", "0.0.0.0:4000", "--workers", "2", "--threads", "4", "--timeout", "600", "--keep-alive", "5"]
