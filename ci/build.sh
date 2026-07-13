#!/bin/sh
# Reproducible uboot.img build for the Rithum Switch (RK3308 AArch32).
#
# Runs inside the ci/Dockerfile container (or natively, given the same
# gcc-linaro-6.3.1-2017.05 toolchain on CROSS_COMPILE and a rkbin
# checkout for loaderimage). Deliberately bypasses make.sh: only
# uboot.img is produced here - trust.img and the loader stay on their
# factory versions on the device.
#
# Environment:
#   CROSS_COMPILE  toolchain prefix (required)
#   BOARD          defconfig basename (default rithum-rk3308-aarch32)
#   LOADERIMAGE    path to rkbin's prebuilt loaderimage (default
#                  ../rkbin/tools/loaderimage). The rkbin tool is used
#                  in preference to the in-tree one because it also
#                  fills the header's js_hash field, matching the
#                  images proven on the device's factory miniloader.
set -eu

BOARD=${BOARD:-rithum-rk3308-aarch32}
LOADERIMAGE=${LOADERIMAGE:-../rkbin/tools/loaderimage}

[ -n "${CROSS_COMPILE:-}" ] || { echo "ERROR: CROSS_COMPILE not set" >&2; exit 1; }
[ -x "${LOADERIMAGE}" ] || { echo "ERROR: ${LOADERIMAGE} not found/executable" >&2; exit 1; }

# The container user may not own the bind-mounted checkout.
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

# Reproducibility: embed the commit date, not the build date.
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2>/dev/null || echo 0)
export SOURCE_DATE_EPOCH

make mrproper

# The vendor setlocalversion caches whatever it first computed in an
# untracked .scmversion file and reuses it verbatim (including across
# mrproper in some vintages), and its git-describe logic depends on
# which tags happen to be fetched. Pin the local version explicitly
# through the same cache file: pure function of the commit built.
rm -f .scmversion
echo "-g$(git rev-parse --short=12 HEAD)" > .scmversion

make "${BOARD}_defconfig"
make -j"$(nproc)"

LOAD_ADDR=$(sed -n 's/^CONFIG_SYS_TEXT_BASE=//p' include/autoconf.mk | tr -d '\r')
U_KB=$(sed -n 's/^CONFIG_UBOOT_SIZE_KB=//p' .config)
U_NUM=$(sed -n 's/^CONFIG_UBOOT_NUM=//p' .config)
U_KB=${U_KB:-512}
U_NUM=${U_NUM:-2}

# Same limit make.sh enforces: image slot minus the 2KB loaderimage header.
BIN=$(stat -c %s u-boot.bin)
MAX=$(( (U_KB - 2) * 1024 ))
if [ "$BIN" -gt "$MAX" ]; then
	echo "ERROR: u-boot.bin ${BIN} bytes exceeds ${MAX} byte limit" >&2
	exit 1
fi
echo "u-boot.bin: ${BIN} / ${MAX} bytes ($(( MAX - BIN )) spare)"

"${LOADERIMAGE}" --pack --uboot u-boot.bin uboot.img "${LOAD_ADDR}" --size "${U_KB}" "${U_NUM}"

sha256sum u-boot.bin uboot.img | tee sha256sums.txt
