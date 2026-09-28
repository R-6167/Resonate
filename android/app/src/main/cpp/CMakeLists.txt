cmake_minimum_required(VERSION 3.22.1)
project(dsp_jni LANGUAGES CXX)

add_library(dsp_jni SHARED dsp_engine_jni.cpp)

target_compile_features(dsp_jni PRIVATE cxx_std_17)
target_compile_options(dsp_jni PRIVATE -O3 -fPIC -fno-exceptions -fno-rtti)

find_library(log-lib log)
find_library(dl-lib dl)
target_link_libraries(dsp_jni PRIVATE ${log-lib} ${dl-lib})
