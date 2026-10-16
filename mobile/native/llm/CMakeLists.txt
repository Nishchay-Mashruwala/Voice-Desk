# The task AI's native library: llama.cpp, pinned to the desktop's build, and the
# vd_llm shim over it, as one shared library (libvd_llm.so / vd_llm.dll).
#
# The Android app builds it through Gradle. The PC builds it with
# build_windows.ps1, for the tests that run the real model.
#
# -DVD_LLAMA_SOURCE=<folder> uses an unpacked llama.cpp b11320 instead of
# downloading it. -DVD_LLM_TOOLS=ON adds vd_llm_bench (speed and memory on a
# phone) and vd_llm_grammar (makes task_grammar.dart's grammar from the schema).
cmake_minimum_required(VERSION 3.22)
project(vd_llm CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(VD_LLM_TOOLS "Build vd_llm_bench and vd_llm_grammar" OFF)

# llama.cpp b11320 (commit b8f96c3e82284028cb077811ed1666caac3c5bac), the
# desktop's LLAMA_BUILD in desktop/backend/core/src/llm.rs.
include(FetchContent)
if(VD_LLAMA_SOURCE)
  set(FETCHCONTENT_SOURCE_DIR_LLAMA "${VD_LLAMA_SOURCE}")
endif()
FetchContent_Declare(llama
  URL https://github.com/ggml-org/llama.cpp/archive/refs/tags/b11320.tar.gz
  URL_HASH SHA256=edd777f61c1d3704456f01bbb9a77b4bd71a1b39d9b8fe0109c3d65c2c4ece74
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ${VD_LLM_TOOLS} CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
# As the 2026-10-12 speed test built it for the M31: no OpenMP (ggml's own
# threads), and a plain armv8-a build that runs on any 64-bit Android phone.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama)

add_library(vd_llm SHARED vd_llm.cpp)
target_link_libraries(vd_llm PRIVATE llama)
set_target_properties(vd_llm PROPERTIES CXX_VISIBILITY_PRESET hidden)
if(ANDROID)
  target_link_options(vd_llm PRIVATE "-Wl,-z,max-page-size=16384")
endif()

if(VD_LLM_TOOLS)
  add_executable(vd_llm_bench tools/vd_llm_bench.cpp)
  target_link_libraries(vd_llm_bench PRIVATE vd_llm)
  add_executable(vd_llm_grammar tools/vd_llm_grammar.cpp)
  target_link_libraries(vd_llm_grammar PRIVATE llama-common)
endif()
