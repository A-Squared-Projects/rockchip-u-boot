# Build container for the Rithum Switch u-boot (RK3308 AArch32).
#
# x86_64-only: the pinned gcc-linaro-6.3.1-2017.05 toolchain is
# x86_64-hosted. Canonical source is Arm's Legacy Linaro GNU Toolchains
# permalink (Linaro's own hosting of the 4.9-7.5 era releases is gone;
# Arm publishes md5 ea9ba26cfc0aaf0a1d307083f64e2fa9 for this tarball,
# whose contents are bit-identical to the Firefly RK3308 SDK copy that
# built every image so far), with a release asset on this repository as
# fallback mirror since Arm marks these releases end-of-life. On
# aarch64 hosts run with: docker run --platform linux/amd64 (works via
# binfmt emulation).
FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
	bc \
	bison \
	build-essential \
	ca-certificates \
	curl \
	flex \
	git \
	libssl-dev \
	xz-utils \
	&& rm -rf /var/lib/apt/lists/*

ARG TC_URL=https://developer.arm.com/-/cdn-downloads/permalink/legacy-linaro-gnu-toolchains/6.3-2017.05/gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf.tar.xz
ARG TC_URL_FALLBACK=https://github.com/A-Squared-Projects/rockchip-u-boot/releases/download/toolchain-6.3.1-2017.05/gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf.tar.xz
ARG TC_SHA256=926b791cd689e8573c3cd912d10e30b7d12a08bb16b9b9eaf598e2074052dc5f
RUN { curl -fsSL -o /tmp/toolchain.tar.xz "${TC_URL}" \
	|| curl -fsSL -o /tmp/toolchain.tar.xz "${TC_URL_FALLBACK}"; } \
	&& echo "${TC_SHA256}  /tmp/toolchain.tar.xz" | sha256sum -c - \
	&& tar -C /opt -xf /tmp/toolchain.tar.xz \
	&& rm /tmp/toolchain.tar.xz

ENV CROSS_COMPILE=/opt/gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
