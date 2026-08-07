cmake_minimum_required(VERSION 3.16)

set(ENV{IDF_TARGET} esp32s3)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(esp32_drone)