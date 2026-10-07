cmake_minimum_required(VERSION 3.16)
project(dsp_engine VERSION 0.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(dsp_engine SHARED
    src/dsp_engine_core.cpp
    src/dsp_stress.cpp
)

target_include_directories(dsp_engine
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

target_compile_options(dsp_engine PRIVATE
    -O3
    -fno-exceptions
    -fno-rtti
    -Wall
    -Wextra
)

add_executable(dsp_stress_runner tools/stress_main.cpp)
target_link_libraries(dsp_stress_runner PRIVATE dsp_engine)

install(TARGETS dsp_engine
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)
install(DIRECTORY include/ DESTINATION include)
