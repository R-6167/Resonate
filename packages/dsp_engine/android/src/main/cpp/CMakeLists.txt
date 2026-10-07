cmake_minimum_required(VERSION 3.16)
project(dsp_engine_android LANGUAGES CXX)

# packages/dsp_engine/android/src/main/cpp → repo root (6 levels up)
set(DSP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../..")

add_library(dsp_engine SHARED
    "${DSP_ROOT}/src/dsp_engine_core.cpp"
)

target_include_directories(dsp_engine PRIVATE
    "${DSP_ROOT}/include"
)

target_compile_options(dsp_engine PRIVATE
    -O3
    -fno-exceptions
    -fno-rtti
    -Wall
    -Wextra
)

find_library(log-lib log)
target_link_libraries(dsp_engine ${log-lib})
