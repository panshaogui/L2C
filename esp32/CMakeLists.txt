cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "../clib" "../clib/esp32-camera") 
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(l2c_esp32_firmware)
