#!/usr/bin/env bash
# Build taskweft CLI for:
#   native   — x86_64 (default, requires cmake + a C++20 compiler)
#   riscv    — RISC-V Linux ELF (requires Docker with riscv64-linux-gnu image)
#   all      — both of the above
# Usage: ./build.sh [native|riscv|all]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMAGE="riscv64-linux-gnu"
TARGET="${1:-native}"

build_native() {
  echo "Building taskweft CLI (x86_64 native)..."
  cmake -B "${SCRIPT_DIR}/.build_native" \
    -DCMAKE_BUILD_TYPE=Release \
    -G Ninja \
    "${SCRIPT_DIR}"
  cmake --build "${SCRIPT_DIR}/.build_native"
  echo "  -> ${SCRIPT_DIR}/.build_native/taskweft"
}

build_riscv() {
  echo "Building taskweft CLI (RISC-V Linux)..."
  if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "Building Docker image ${IMAGE}..."
    docker build -t "${IMAGE}" \
      "${GODOT_ROOT}/modules/sandbox/program/cpp/docker"
  fi

  docker run --rm \
    -v "${SCRIPT_DIR}:/usr/src/cli" \
    -v "${GODOT_ROOT}/modules/taskweft:/usr/taskweft" \
    "${IMAGE}" \
    bash -c "
      set -e
      CXX='riscv64-linux-gnu-g++-14'
      FLAGS='-O2 -std=gnu++23 -fno-stack-protector -fno-threadsafe-statics'
      ARCH='-march=rv64gc_zba_zbb_zbs_zbc -mabi=lp64d'

      \$CXX \$FLAGS \$ARCH \
        -I/usr/taskweft/.. \
        /usr/src/cli/main.cpp \
        -o /usr/src/cli/taskweft_riscv64
    "
  echo "  -> ${SCRIPT_DIR}/taskweft_riscv64"
}

case "${TARGET}" in
  native) build_native ;;
  riscv)  build_riscv  ;;
  all)    build_native; build_riscv ;;
  *)
    echo "Usage: $0 [native|riscv|all]"
    exit 1
    ;;
esac

echo "Done."
