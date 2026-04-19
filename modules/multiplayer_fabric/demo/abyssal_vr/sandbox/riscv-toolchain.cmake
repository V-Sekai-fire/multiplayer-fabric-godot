set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv64)

# Bare-metal cross-compiler: skip the link-test that tries to find crt0/libc.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_COMPILER   /opt/homebrew/Cellar/riscv64-elf-gcc/15.2.0/bin/riscv64-elf-gcc)
set(CMAKE_CXX_COMPILER /opt/homebrew/Cellar/riscv64-elf-gcc/15.2.0/bin/riscv64-elf-g++)
set(CMAKE_AR           /opt/homebrew/bin/riscv64-elf-ar)
set(CMAKE_RANLIB       /opt/homebrew/bin/riscv64-elf-ranlib)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Suppress macOS sysroot and deployment target checks
set(CMAKE_OSX_SYSROOT "")
set(CMAKE_OSX_DEPLOYMENT_TARGET "")
