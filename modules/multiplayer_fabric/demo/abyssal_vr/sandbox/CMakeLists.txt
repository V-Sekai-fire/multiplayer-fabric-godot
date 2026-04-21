cmake_minimum_required(VERSION 3.20)
project(jellygrid_sandbox LANGUAGES CXX)

# Reuse the existing godot-sandbox cmake infrastructure.
set(SANDBOX_CMAKE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../modules/sandbox/program/cpp/cmake")
add_subdirectory("${SANDBOX_CMAKE_DIR}" sandbox_cmake)

# Pure sim headers from the mmog module — no Godot, no api.hpp dependency.
set(SIM_HEADERS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../modules/multiplayer_fabric_mmog")

function(add_jellygrid_program name source)
    add_sandbox_program_at(${name}
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/${source}"
    )
    target_include_directories(${name} PRIVATE
        "${SIM_HEADERS_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endfunction()

add_jellygrid_program(jellygrid_swarm      jellygrid_swarm.cpp)
add_jellygrid_program(jellygrid_power_node jellygrid_power_node.cpp)
add_jellygrid_program(jellygrid_current    jellygrid_current.cpp)

# Taskweft HTN planner — pure C++ standalone, no sim-headers dependency.
set(TW_STANDALONE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../modules/taskweft/standalone")
add_sandbox_program_at(taskweft_planner
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/taskweft_planner.cpp"
)
target_include_directories(taskweft_planner PRIVATE "${TW_STANDALONE_DIR}/..")
