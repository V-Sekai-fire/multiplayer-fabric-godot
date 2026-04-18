cmake_minimum_required(VERSION 3.20)
project(taskweft_cli CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(taskweft main.cpp)
target_include_directories(taskweft PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/..")
