cmake_minimum_required(VERSION 3.22.1)
project(craze LANGUAGES CXX)

add_library(craze SHARED native-lib.cpp)
target_compile_features(craze PRIVATE cxx_std_20)
target_include_directories(craze PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/generated")
target_compile_options(craze PRIVATE
    -Wall -Wextra -Wpedantic
    -fvisibility=hidden
    -fstack-protector-strong
    -D_FORTIFY_SOURCE=2
)
target_link_options(craze PRIVATE -Wl,--exclude-libs,ALL -Wl,--gc-sections -Wl,--strip-all)
