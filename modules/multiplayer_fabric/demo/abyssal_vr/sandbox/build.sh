#!/usr/bin/env bash
# Build jellygrid sandbox programs as RISC-V ELF using the godot-sandbox Docker image.
# Requires: docker
# Usage: ./build.sh [--strip]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
API_DIR="${GODOT_ROOT}/modules/sandbox/program/cpp/docker/api"
SIM_DIR="${GODOT_ROOT}/modules/multiplayer_fabric_mmog"
TW_DIR="${GODOT_ROOT}/modules/taskweft"
IMAGE="riscv64-linux-gnu"

STRIP_FLAG=""
if [[ "$1" == "--strip" ]]; then STRIP_FLAG="-s"; fi

# Build the Docker image if it doesn't exist.
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "Building Docker image ${IMAGE}..."
  docker build -t "${IMAGE}" "${GODOT_ROOT}/modules/sandbox/program/cpp/docker"
fi

JELLYGRID_PROGRAMS=(jellygrid_swarm jellygrid_power_node jellygrid_current)

for prog in "${JELLYGRID_PROGRAMS[@]}"; do
  echo "Building ${prog}..."
  docker run --rm \
    -v "${SCRIPT_DIR}:/usr/src/sandbox" \
    -v "${API_DIR}:/usr/api" \
    -v "${SIM_DIR}:/usr/sim_headers" \
    "${IMAGE}" \
    bash -c "
      set -e
      CXX='riscv64-linux-gnu-g++-14'
      FLAGS='-O2 -std=gnu++23 -DVERSION=10 -fno-stack-protector -fno-threadsafe-statics'
      ARCH='-march=rv64gc_zba_zbb_zbs_zbc -mabi=lp64d'
      WRAP='-Wl,--wrap=memcpy,--wrap=memset,--wrap=memcmp,--wrap=memmove,--wrap=strlen,--wrap=strcmp,--wrap=strncmp,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free'

      for f in /usr/api/*.cpp; do
        \$CXX \$FLAGS \$ARCH -I/usr/api -c \$f -o \${f}.o
      done

      \$CXX \$FLAGS \$ARCH -I/usr/api -I/usr/sim_headers \
        -c /usr/src/sandbox/${prog}.cpp -o /usr/src/sandbox/${prog}.o

      \$CXX -static ${STRIP_FLAG} \$FLAGS \$ARCH \$WRAP \
        /usr/src/sandbox/${prog}.o /usr/api/*.cpp.o \
        -o /usr/src/sandbox/${prog}
    "
  echo "  -> ${prog} ($(du -h "${SCRIPT_DIR}/${prog}" | cut -f1))"
done

# taskweft_planner: needs the standalone headers (no sim-headers dependency).
echo "Building taskweft_planner..."
docker run --rm \
  -v "${SCRIPT_DIR}:/usr/src/sandbox" \
  -v "${API_DIR}:/usr/api" \
  -v "${TW_DIR}:/usr/taskweft" \
  "${IMAGE}" \
  bash -c "
    set -e
    CXX='riscv64-linux-gnu-g++-14'
    FLAGS='-O2 -std=gnu++23 -DVERSION=10 -fno-stack-protector -fno-threadsafe-statics'
    ARCH='-march=rv64gc_zba_zbb_zbs_zbc -mabi=lp64d'
    WRAP='-Wl,--wrap=memcpy,--wrap=memset,--wrap=memcmp,--wrap=memmove,--wrap=strlen,--wrap=strcmp,--wrap=strncmp,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free'

    for f in /usr/api/*.cpp; do
      \$CXX \$FLAGS \$ARCH -I/usr/api -c \$f -o \${f}.o
    done

    \$CXX \$FLAGS \$ARCH -I/usr/api -I/usr/taskweft/.. \
      -c /usr/src/sandbox/taskweft_planner.cpp -o /usr/src/sandbox/taskweft_planner.o

    \$CXX -static ${STRIP_FLAG} \$FLAGS \$ARCH \$WRAP \
      /usr/src/sandbox/taskweft_planner.o /usr/api/*.cpp.o \
      -o /usr/src/sandbox/taskweft_planner
  "
echo "  -> taskweft_planner ($(du -h "${SCRIPT_DIR}/taskweft_planner" | cut -f1))"

echo "Done."
