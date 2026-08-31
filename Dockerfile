# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG KOHARU_VERSION=0.61.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    fonts-noto-cjk \
    libasound2t64 \
    libayatana-appindicator3-1 \
    libgomp1 \
    libnss3 \
    librsvg2-2 \
    libssl3 \
    libwebkit2gtk-4.1-0 \
    libxdo3 \
    && release_url="$(curl -fsSL "https://api.github.com/repos/mayocream/koharu/releases/tags/${KOHARU_VERSION}" \
        | sed -n 's/.*"browser_download_url": "\(.*_amd64\.deb\)".*/\1/p' \
        | head -n 1)" \
    && test -n "$release_url" \
    && curl -fL "$release_url" -o /tmp/koharu.deb \
    && apt-get install -y --no-install-recommends /tmp/koharu.deb \
    && rm -f /tmp/koharu.deb \
    && apt-get purge -y --auto-remove curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash koharu \
    && install -d -o koharu -g koharu -m 755 /home/koharu/.local/share/Koharu

USER koharu
WORKDIR /home/koharu

ENV LD_LIBRARY_PATH=/usr/share/koharu

VOLUME ["/home/koharu/.local/share/Koharu"]
EXPOSE 4000

CMD ["/usr/bin/koharu", "--headless", "--host", "0.0.0.0", "--port", "4000"]
