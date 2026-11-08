FROM rust:1.97-bookworm AS builder
ARG CARGO_BUILD_JOBS=2
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY legacy-node/src/paladins-avatar-assets.ts ./legacy-node/src/paladins-avatar-assets.ts
COPY assets/templates ./assets/templates
RUN cargo build --release --locked

FROM debian:bookworm-slim
# chromium package supplies the runtime shared libs (libnss3, libgbm1, libvulkan1, fonts)
# that chrome-headless-shell links against. We then swap the 326 MB GUI chromium binary for
# the 197 MB chrome-headless-shell (same version 154.0.8037.92, same Skia renderer ->
# pixel-identical output) and strip the GUI-only Vulkan/SwiftShader layers the shell never loads.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl chromium fontconfig fonts-inter fonts-dejavu-core fonts-noto-core fonts-noto-cjk unzip \
    && curl -fsSL -o /tmp/hss.zip "https://storage.googleapis.com/chrome-for-testing-public/154.0.8037.92/linux64/chrome-headless-shell-linux64.zip" \
    && unzip -o -q /tmp/hss.zip -d /tmp/hss \
    && install -m 0755 /tmp/hss/chrome-headless-shell-linux64/chrome-headless-shell /usr/local/bin/chrome-headless-shell \
    && rm -rf /tmp/hss /tmp/hss.zip \
    && rm -f /usr/lib/chromium/chromium /usr/lib/chromium/libVkLayer_khronos_validation.so* \
           /usr/lib/chromium/libvk_swiftshader.so /usr/lib/chromium/libVkICD_mock_icd.so* \
    && apt-get purge -y unzip && apt-get autoremove -y --purge \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 1000 --create-home paladinscat
WORKDIR /app
COPY --from=builder /build/target/release/paladinscat-discord-bot /usr/local/bin/paladinscat-discord-bot
COPY assets/templates ./assets/templates
USER 1000:1000
EXPOSE 3020
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD curl -sf http://127.0.0.1:3020/health || exit 1
ENV RUST_LOG=info HEALTH_PORT=3020 CHROME_PATH=/usr/local/bin/chrome-headless-shell
ENTRYPOINT ["/usr/local/bin/paladinscat-discord-bot"]
