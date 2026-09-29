cmake_minimum_required(VERSION 3.22.1)
project(resonate_dsp LANGUAGES CXX)

# Vendored DSP ENGINE — always packaged into the APK as libdsp_engine.so
add_library(dsp_engine SHARED dsp_engine_core.cpp)
target_include_directories(dsp_engine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(dsp_engine PRIVATE cxx_std_17)
target_compile_options(dsp_engine PRIVATE -O3 -fPIC -fno-exceptions -fno-rtti)
find_library(log-lib log)
target_link_libraries(dsp_engine PRIVATE ${log-lib})

# JNI bridge — links engine directly (no fragile dlopen dependency at runtime)
add_library(dsp_jni SHARED dsp_engine_jni.cpp)
target_include_directories(dsp_jni PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(dsp_jni PRIVATE cxx_std_17)
target_compile_options(dsp_jni PRIVATE -O3 -fPIC -fno-exceptions -fno-rtti)
find_library(dl-lib dl)
target_link_libraries(dsp_jni PRIVATE dsp_engine ${log-lib} ${dl-lib})
