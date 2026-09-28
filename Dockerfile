# FROM mcr.microsoft.com/playwright:v1.20.0
# Partially from https://github.com/microsoft/playwright/blob/main/utils/docker/Dockerfile.focal
FROM ubuntu:jammy

# Configuration variables are at the end!

# https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Install up-to-date node & npm, deps for virtual screen & noVNC, Chromium runtime libs, pip for apprise.
RUN apt-get update \
    && apt-get install --no-install-recommends -y curl ca-certificates gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
      nodejs \
      xvfb \
      x11vnc \
      tini \
      novnc websockify \
      dos2unix \
      python3-pip \
    # Chromium runtime libs for CloakBrowser's stealth Chromium (replaces the old Firefox deps)
    && apt-get install --no-install-recommends -y \
      libnss3 \
      libnspr4 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libcups2 \
      libdrm2 \
      libxkbcommon0 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libgbm1 \
      libasound2 \
      libatspi2.0-0 \
      libgtk-3-0 \
      libpango-1.0-0 \
      libcairo2 \
      fonts-liberation \
    # Fonts CloakBrowser needs to pass anti-bot canvas checks when spoofing Windows on Linux:
    # aggressive systems (Kasada, Akamai) hash hidden canvas renders of emoji and extended
    # character sets, so a thin font set is itself a detection signal. See
    # https://github.com/CloakHQ/cloakbrowser#font-setup-on-linux
    # (Real Windows typefaces - Segoe UI, Calibri, Bahnschrift - further improve CreepJS font
    # scoring but are not redistributable; supply them via --fingerprint-fonts-dir if wanted.)
    && apt-get install --no-install-recommends -y \
      fonts-noto-color-emoji \
      fonts-freefont-ttf \
      fonts-unifont \
      fonts-ipafont-gothic \
      fonts-wqy-zenhei \
      fonts-tlwg-loma-otf \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf \
      /tmp/* \
      /usr/share/doc/* \
      /var/cache/* \
      /var/lib/apt/lists/* \
      /var/tmp/*

# RUN node --version
# RUN npm --version

RUN ln -s /usr/share/novnc/vnc_auto.html /usr/share/novnc/index.html
RUN pip install apprise

# Microsoft typefaces that CloakBrowser probes for when spoofing Windows (Segoe UI, Calibri,
# Consolas, ...). Without them it warns "Incomplete Windows font set" and the font fingerprint
# betrays that the host is Linux. These are proprietary and cannot come from apt.
# Build with --build-arg MS_FONTS=0 to skip - see install-ms-fonts.sh for the licensing caveat.
ARG MS_FONTS=1
COPY install-ms-fonts.sh /tmp/
RUN MS_FONTS=${MS_FONTS} bash /tmp/install-ms-fonts.sh && rm /tmp/install-ms-fonts.sh

WORKDIR /fgc
COPY package*.json ./

RUN npm install
# CloakBrowser auto-downloads its stealth Chromium binary (~200MB) on first run.
# Pre-download it at build time so the first container run doesn't stall on the fetch.
# Requires the Chromium system libs installed above to actually launch.
RUN node -e "import('cloakbrowser').then(m => m.ensureBinary())"

COPY . .

# Shell scripts need Linux line endings. On Windows, git might be configured to check out dos/CRLF line endings, so we convert them for those people in case they want to build the image. They could also use --config core.autocrlf=input
RUN dos2unix ./*.sh && chmod +x ./*.sh
COPY docker-entrypoint.sh /usr/local/bin/

ARG COMMIT=""
ARG BRANCH=""
ARG NOW=""
ENV COMMIT=${COMMIT}
ENV BRANCH=${BRANCH}
ENV NOW=${NOW}

LABEL org.opencontainers.image.title="free-games-claimer" \
      org.opencontainers.image.name="free-games-claimer" \
      org.opencontainers.image.description="Automatically claims free games on the Epic Games Store, Amazon Prime Gaming and GOG" \
      org.opencontainers.image.url="https://github.com/vogler/free-games-claimer" \
      org.opencontainers.image.source="https://github.com/vogler/free-games-claimer" \
      org.opencontainers.image.revision=${COMMIT} \
      org.opencontainers.image.ref.name=${BRANCH} \
      org.opencontainers.image.base.name="ubuntu:jammy" \
      org.opencontainers.image.version="latest"

# Configure VNC via environment variables:
ENV VNC_PORT 5900
ENV NOVNC_PORT 6080
EXPOSE 5900
EXPOSE 6080

# Configure Xvfb via environment variables:
ENV WIDTH 1920
ENV HEIGHT 1080
ENV DEPTH 24

# Show browser instead of running headless
ENV SHOW 1

# The image pins the cloakbrowser package and pre-downloads its Chromium above, so skip the runtime update checks:
# the npm "Update available" notice isn't actionable inside the container, and a newer binary would be re-downloaded
# (~200MB) into every fresh container instead of being baked into the image.
ENV CLOAKBROWSER_AUTO_UPDATE=false

# Script to setup display server & VNC is always executed.
ENTRYPOINT ["docker-entrypoint.sh"]
# Default command to run. This is replaced by appending own command, e.g. `docker run ... node prime-gaming` to only run this script.
CMD node epic-games; node prime-gaming; node gog
