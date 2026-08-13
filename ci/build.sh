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
#   RKBIN          rkbin checkout (default ../rkbin), for the prebuilt
#                  loaderimage/trust_merger tools plus the RKTRUST ini
#                  and bl31 blob. rkbin's loaderimage is used in
#                  preference to the in-tree one because it also fills
#                  the header's js_hash field, matching the images
#                  proven on the device's factory miniloader.
set -eu

BOARD=${BOARD:-rithum-rk3308-aarch32}
RKBIN=${RKBIN:-../rkbin}
LOADERIMAGE=${LOADERIMAGE:-${RKBIN}/tools/loaderimage}

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

# trust.img packed the way make.sh's ARM64_TRUSTZONE path does for this
# config. Deterministic: pure function of the trust ini + rkbin blobs.
# The trust ini is taken from ci/<name> in this repo if present (so the
# trust composition - notably BL32/OP-TEE enablement - is reviewable and
# pinned in-tree), else from the pinned rkbin's stock RKTRUST/<name>.
# PATH= entries inside resolve relative to the rkbin checkout
# (trust_merger's cwd), so they stay bin/rk33/... either way.
TRUST_INI=$(sed -n 's/^CONFIG_TRUST_INI="\(.*\)"/\1/p' .config)
T_KB=$(sed -n 's/^CONFIG_TRUST_SIZE_KB=//p' .config)
T_NUM=$(sed -n 's/^CONFIG_TRUST_NUM=//p' .config)
T_SHA=$(sed -n 's/^CONFIG_TRUST_SHA_MODE=//p' .config)
T_RSA=$(sed -n 's/^CONFIG_TRUST_RSA_MODE=//p' .config)
SRC=$(pwd)
TRUST_INI_ARG="${SRC}/ci/${TRUST_INI}"
[ -f "${TRUST_INI_ARG}" ] || TRUST_INI_ARG="RKTRUST/${TRUST_INI}"
echo "trust ini: ${TRUST_INI_ARG}"

# OEM key: replace the world-known Rockchip dev-kit public key baked into BL32
# with ours, so only TAs signed with our matching private key load (see the TA
# recipes in meta-rithum). change_puk is an x86_64 glibc binary (libc/libdl/libz
# - all present) that edits the .bin in place; the rkbin sparse checkout is
# fresh + writable each run. Verify it actually changed the blob: a silent no-op
# would ship a stock-key trust.img that rejects our re-signed TAs.
BL32_REL=$(sed -n 's/^PATH=\(.*bl32.*\)/\1/Ip' "${TRUST_INI_ARG}" | head -1)
if [ -n "${BL32_REL}" ]; then
	BL32="${RKBIN}/${BL32_REL}"
	[ -f "${BL32}" ] || { echo "ERROR: BL32 not found at ${BL32}" >&2; exit 1; }
	BL32_BEFORE=$(sha256sum "${BL32}" | cut -d' ' -f1)
	chmod +x "${SRC}/ci/change_puk"
	"${SRC}/ci/change_puk" --teebin "${BL32}" --key "${SRC}/ci/oem_privkey.pem"
	BL32_AFTER=$(sha256sum "${BL32}" | cut -d' ' -f1)
	[ "${BL32_BEFORE}" != "${BL32_AFTER}" ] || { echo "ERROR: change_puk did not modify BL32 - OEM key not applied" >&2; exit 1; }
	echo "change_puk: baked our OEM public key into ${BL32_REL}"
else
	# BL31-only trust (the android flavor): no secure world, so there is
	# no TA public key to replace and no need for the git-crypt-held OEM
	# key. The BL32 guard above stays fail-secure for inis that do carry
	# one.
	echo "trust ini carries no BL32 - BL31-only trust, change_puk skipped"
fi

(cd "${RKBIN}" && ./tools/trust_merger "${TRUST_INI_ARG}" \
	--size "${T_KB:-512}" "${T_NUM:-2}" \
	--sha "${T_SHA:-3}" --rsa "${T_RSA:-3}" \
	&& mv trust.img "${SRC}/trust.img")

sha256sum u-boot.bin uboot.img trust.img | tee sha256sums.txt
