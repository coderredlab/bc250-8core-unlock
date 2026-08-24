#!/usr/bin/env bash
set -euo pipefail

EDK2_TAG="edk2-stable202608"
EDK2_COMMIT="2970e5699ba6267f3384ffab20f96647578aebc8"
EDK2_EPOCH="1786522436"
IMAGE="ghcr.io/tianocore/containers/fedora-41-dev@sha256:ad9a623d6887a8d0505f3a149ae07b88272795c4171420c76d166b97249f8e80"
BROTLI_COMMIT="e230f474b87134e8c6c85b630084c612057f253e"
MIPISYST_COMMIT="370b5944c046bab043dd8b133727b2135af7747a"

EXPECTED_TE_SHA256="097711ca0972db67ef41c0213451c0e98d7d132735dd940086958d34d5013b21"
EXPECTED_FFS_SHA256="ceaafd7b0896d4631e951662e5aa5e46d1883623b2fb228d93800bc39c1cf40d"
EXPECTED_MAP_SHA256="dd644cc0e6dad499c5284d79963613b89a3959d76f4890d2dac08e909fd19c92"

EXPECTED_C_SHA256="d3465dc33ff9077ba922415a5fbc4379cd8c18d9af227922dc06d96da2711562"
EXPECTED_INF_SHA256="c771106f146259cb6810d23ce493c77a0ffc9d75de7ef0a6db64a0b6471d7f2d"
EXPECTED_DSC_SHA256="bd6ed27c1d4a47c1b9dec306c906e03956ea3bf7fb7233680e9a794d50624d0b"
EXPECTED_FDF_SHA256="c6c549d0ac81148716a2c39529eb708c0168a7a2e5326da63e707ec9aa3260b7"
EXPECTED_DEC_SHA256="63117f405cd18d8b09a62652d55dc20603cb2811c75ea7130c5339a561242bea"




SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/bc250"
EDK2_DIR="${CACHE_ROOT}/edk2-${EDK2_COMMIT:0:16}"
OUTPUT_DIR="${PROJECT_DIR}/build-output"
FFS_DIR="${EDK2_DIR}/Build/Bc250CoreUnlockPei/RELEASE_GCCNOLTO/FV/Ffs/45EC1B8A-957A-44E8-88BD-7FF8ABAE06BBBc250CoreUnlockPei"
MAP_FILE="${EDK2_DIR}/Build/Bc250CoreUnlockPei/RELEASE_GCCNOLTO/IA32/Bc250CoreUnlockPei/Bc250CoreUnlockPei/OUTPUT/Bc250CoreUnlockPei.map"

verify_source()
{
    local relative_path="$1"
    local expected_hash="$2"
    local actual_hash

    actual_hash="$(sha256sum "${PROJECT_DIR}/${relative_path}" | cut -d ' ' -f 1)"
    if [[ "${actual_hash}" != "${expected_hash}" ]]; then
        printf 'unexpected source SHA-256 for %s: %s\n' "${relative_path}" "${actual_hash}" >&2
        exit 1
    fi
}

require_clean_tracked()
{
    local repository="$1"
    local label="$2"

    if ! git -C "${repository}" diff --quiet --ignore-submodules=dirty -- ||
       ! git -C "${repository}" diff --cached --quiet --ignore-submodules=dirty --; then
        printf 'tracked changes in %s worktree\n' "${label}" >&2
        exit 1
    fi
}

run_edk_build()
{
    docker run --rm \
        --entrypoint /bin/bash \
        --user "${uid_value}:${gid_value}" \
        -e HOME=/tmp \
        -e EDK2_DOCKER_USER_HOME=/tmp \
        -e SOURCE_DATE_EPOCH="${EDK2_EPOCH}" \
        -v "${EDK2_DIR}:/workspace/edk2" \
        -v "${PROJECT_DIR}:/workspace/project" \
        -w /workspace/edk2 \
        "${IMAGE}" \
        -lc 'source edksetup.sh && export PACKAGES_PATH=/workspace/project/tools/uefi/bc250-core-unlock:/workspace/edk2 && build cleanall -a IA32 -t GCCNOLTO -b RELEASE -p Bc250CoreUnlockPeiPkg.dsc && build -a IA32 -t GCCNOLTO -b RELEASE -p Bc250CoreUnlockPeiPkg.dsc'
}

copy_build_outputs()
{
    local destination="$1"

    cp "${FFS_DIR}/45EC1B8A-957A-44E8-88BD-7FF8ABAE06BBTe.raw" "${destination}/Bc250CoreUnlockPei.te"
    cp "${FFS_DIR}/45EC1B8A-957A-44E8-88BD-7FF8ABAE06BB.ffs" "${destination}/Bc250CoreUnlockPei.ffs"
    cp "${MAP_FILE}" "${destination}/Bc250CoreUnlockPei.map"
}

verify_build_outputs()
{
    local directory="$1"
    local actual_te_sha256
    local actual_ffs_sha256
    local actual_map_sha256

    actual_te_sha256="$(sha256sum "${directory}/Bc250CoreUnlockPei.te" | cut -d ' ' -f 1)"
    actual_ffs_sha256="$(sha256sum "${directory}/Bc250CoreUnlockPei.ffs" | cut -d ' ' -f 1)"
    actual_map_sha256="$(sha256sum "${directory}/Bc250CoreUnlockPei.map" | cut -d ' ' -f 1)"
    if [[ "${actual_te_sha256}" != "${EXPECTED_TE_SHA256}" ]]; then
        printf 'unexpected TE SHA-256: %s\n' "${actual_te_sha256}" >&2
        exit 1
    fi
    if [[ "${actual_ffs_sha256}" != "${EXPECTED_FFS_SHA256}" ]]; then
        printf 'unexpected FFS SHA-256: %s\n' "${actual_ffs_sha256}" >&2
        exit 1
    fi
    if [[ "${actual_map_sha256}" != "${EXPECTED_MAP_SHA256}" ]]; then
        printf 'unexpected map SHA-256: %s\n' "${actual_map_sha256}" >&2
        exit 1
    fi
}

mkdir -p "${CACHE_ROOT}" "${OUTPUT_DIR}"

verify_source "tools/uefi/bc250-core-unlock/Bc250CoreUnlockPei/Bc250CoreUnlockPei.c" "${EXPECTED_C_SHA256}"
verify_source "tools/uefi/bc250-core-unlock/Bc250CoreUnlockPei/Bc250CoreUnlockPei.inf" "${EXPECTED_INF_SHA256}"
verify_source "tools/uefi/bc250-core-unlock/Bc250CoreUnlockPeiPkg.dsc" "${EXPECTED_DSC_SHA256}"
verify_source "tools/uefi/bc250-core-unlock/Bc250CoreUnlockPeiPkg.fdf" "${EXPECTED_FDF_SHA256}"
verify_source "tools/uefi/bc250-core-unlock/Bc250CoreUnlockPkg.dec" "${EXPECTED_DEC_SHA256}"

if [[ ! -d "${EDK2_DIR}/.git" ]]; then
    git clone --depth 1 --branch "${EDK2_TAG}" https://github.com/tianocore/edk2.git "${EDK2_DIR}"
fi
actual_commit="$(git -C "${EDK2_DIR}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${EDK2_COMMIT}" ]]; then
    printf 'unexpected EDK II commit: %s\n' "${actual_commit}" >&2
    exit 1
fi

git -C "${EDK2_DIR}" submodule update --init --depth 1 \
    BaseTools/Source/C/BrotliCompress/brotli \
    MdePkg/Library/MipiSysTLib/mipisyst
if [[ "$(git -C "${EDK2_DIR}/BaseTools/Source/C/BrotliCompress/brotli" rev-parse HEAD)" != "${BROTLI_COMMIT}" ]]; then
    printf 'unexpected Brotli submodule commit\n' >&2
    exit 1
fi
if [[ "$(git -C "${EDK2_DIR}/MdePkg/Library/MipiSysTLib/mipisyst" rev-parse HEAD)" != "${MIPISYST_COMMIT}" ]]; then
    printf 'unexpected mipisyst submodule commit\n' >&2
    exit 1
fi
require_clean_tracked "${EDK2_DIR}" "EDK II"
require_clean_tracked "${EDK2_DIR}/BaseTools/Source/C/BrotliCompress/brotli" "Brotli"
require_clean_tracked "${EDK2_DIR}/MdePkg/Library/MipiSysTLib/mipisyst" "mipisyst"

docker pull "${IMAGE}" >/dev/null
uid_value="$(id -u)"
gid_value="$(id -g)"
docker run --rm \
    --entrypoint /bin/bash \
    --user "${uid_value}:${gid_value}" \
    -e HOME=/tmp \
    -e EDK2_DOCKER_USER_HOME=/tmp \
    -v "${EDK2_DIR}:/workspace/edk2" \
    -w /workspace/edk2 \
    "${IMAGE}" \
    -lc 'source edksetup.sh && make -C BaseTools clean && make -C BaseTools -j12'

first_build=""
second_build=""
staging_dir=""
artifact_link=""
cleanup()
{
    if [[ -n "${first_build}" && -d "${first_build}" ]]; then
        rm -rf "${first_build}"
    fi
    if [[ -n "${second_build}" && -d "${second_build}" ]]; then
        rm -rf "${second_build}"
    fi
    if [[ -n "${staging_dir}" && -d "${staging_dir}" ]]; then
        rm -rf "${staging_dir}"
    fi
    if [[ -n "${artifact_link}" && -L "${artifact_link}" ]]; then
        rm -f "${artifact_link}"
    fi
}
trap cleanup EXIT

first_build="$(mktemp -d "${OUTPUT_DIR}/.pei-first.XXXXXX")"
run_edk_build
copy_build_outputs "${first_build}"
verify_build_outputs "${first_build}"

second_build="$(mktemp -d "${OUTPUT_DIR}/.pei-second.XXXXXX")"
run_edk_build
copy_build_outputs "${second_build}"
verify_build_outputs "${second_build}"
cmp "${first_build}/Bc250CoreUnlockPei.te" "${second_build}/Bc250CoreUnlockPei.te"
cmp "${first_build}/Bc250CoreUnlockPei.ffs" "${second_build}/Bc250CoreUnlockPei.ffs"
cmp "${first_build}/Bc250CoreUnlockPei.map" "${second_build}/Bc250CoreUnlockPei.map"

staging_dir="$(mktemp -d "${OUTPUT_DIR}/.pei-output.XXXXXX")"
copy_build_outputs "${staging_dir}"
artifact_name="BC250CoreUnlockPei-${EXPECTED_TE_SHA256}"
artifact_dir="${OUTPUT_DIR}/${artifact_name}"
if [[ -d "${artifact_dir}" ]]; then
    cmp "${staging_dir}/Bc250CoreUnlockPei.te" "${artifact_dir}/Bc250CoreUnlockPei.te"
    cmp "${staging_dir}/Bc250CoreUnlockPei.ffs" "${artifact_dir}/Bc250CoreUnlockPei.ffs"
    cmp "${staging_dir}/Bc250CoreUnlockPei.map" "${artifact_dir}/Bc250CoreUnlockPei.map"
    rm -rf "${staging_dir}"
else
    mv "${staging_dir}" "${artifact_dir}"
fi
staging_dir=""

artifact_link="${OUTPUT_DIR}/.pei-dir-link.$$"
ln -s "${artifact_name}" "${artifact_link}"
mv -Tf "${artifact_link}" "${OUTPUT_DIR}/BC250CoreUnlockPei-BUILD"

printf 'PEIM build reproduced and verified:\n'
printf '  %s\n' "${OUTPUT_DIR}/${artifact_name}"
