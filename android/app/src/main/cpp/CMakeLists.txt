cmake_minimum_required(VERSION 3.18.1)
project("crazechat-native")

add_library(
    crazechat-native
    SHARED
    native-lib.c
)

find_library(
    log-lib
    log
)

target_link_libraries(
    crazechat-native
    ${log-lib}
)
