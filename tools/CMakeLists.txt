# Host tools for the Linux build of Nebula: galaxy_native_spirv and galaxy_utility_spirv.
#
# On Windows both tools come from Nebula's top-level CMakeLists (WIN32 + NEBULA_VULKAN). The SDL/Vulkan host
# (platform/sdl/CMakeLists.txt) expects them prebuilt in NEBULA_HOST_TOOLS, so this file builds them on Linux with
# the same dependency checkouts and the same glslang settings.
#
#   cmake -S tools -B <build>/tools -DNEBULA_ROOT=<nebula checkout> -DNEBULA_DEPS=<dependency checkouts>
cmake_minimum_required(VERSION 3.24)
project(NebulaHostTools LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(NEBULA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../nebula" CACHE PATH "Nebula source checkout")
get_filename_component(nebula_root "${NEBULA_ROOT}" ABSOLUTE)
if(NOT EXISTS "${nebula_root}/CMakeLists.txt")
    message(FATAL_ERROR "Set NEBULA_ROOT to the Nebula checkout (no CMakeLists.txt in ${nebula_root})")
endif()

set(NEBULA_DEPS "" CACHE PATH "Folder of the dependency checkouts")
if(NOT IS_DIRECTORY "${NEBULA_DEPS}")
    message(FATAL_ERROR "Set NEBULA_DEPS to the folder of the dependency checkouts")
endif()
set(NEBULA_VULKAN_HEADERS_DIR "${NEBULA_DEPS}/Vulkan-Headers-vulkan-sdk-1.4.350.1" CACHE PATH "Vulkan-Headers")
set(NEBULA_VOLK_DIR "${NEBULA_DEPS}/volk-vulkan-sdk-1.4.350.1" CACHE PATH "volk")
set(NEBULA_VMA_DIR "${NEBULA_DEPS}/VulkanMemoryAllocator-v3.4.0" CACHE PATH "VulkanMemoryAllocator")
set(NEBULA_GLSLANG_SOURCE_DIR "${NEBULA_DEPS}/glslang-src" CACHE PATH "glslang source (External/spirv-tools inside)")

set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
set(ENABLE_HLSL ON CACHE BOOL "" FORCE)
set(ENABLE_OPT ON CACHE BOOL "" FORCE)
set(GLSLANG_TESTS OFF CACHE BOOL "" FORCE)
set(GLSLANG_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(SPIRV_SKIP_TESTS ON CACHE BOOL "" FORCE)
set(SPIRV_SKIP_EXECUTABLES ON CACHE BOOL "" FORCE)
set(SPIRV_TOOLS_BUILD_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory("${NEBULA_GLSLANG_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/glslang" EXCLUDE_FROM_ALL)

file(GLOB nebula_glslang_spirv_headers "${NEBULA_GLSLANG_SOURCE_DIR}/SPIRV/*.h" "${NEBULA_GLSLANG_SOURCE_DIR}/SPIRV/*.hpp")
file(COPY ${nebula_glslang_spirv_headers} DESTINATION "${CMAKE_BINARY_DIR}/glslang-include/glslang/SPIRV")

add_library(nebula_shader_compiler INTERFACE)
target_include_directories(nebula_shader_compiler SYSTEM INTERFACE
    "${CMAKE_BINARY_DIR}/glslang-include" "${NEBULA_GLSLANG_SOURCE_DIR}"
    "${NEBULA_GLSLANG_SOURCE_DIR}/External/spirv-tools/include")
target_link_libraries(nebula_shader_compiler INTERFACE glslang SPIRV glslang-default-resource-limits
    SPIRV-Tools-opt SPIRV-Tools-static)

add_library(nebula_vulkan_deps INTERFACE)
target_include_directories(nebula_vulkan_deps INTERFACE
    "${NEBULA_VULKAN_HEADERS_DIR}/include" "${NEBULA_VOLK_DIR}" "${NEBULA_VMA_DIR}/include")
target_compile_definitions(nebula_vulkan_deps INTERFACE NEBULA_GPU_VULKAN VK_NO_PROTOTYPES)

add_executable(galaxy_native_spirv
    "${nebula_root}/tools/dev/native_spirv.cpp"
    "${nebula_root}/runtime/src/render/vk/shader_compile_vk.cpp")
target_include_directories(galaxy_native_spirv PRIVATE
    "${nebula_root}/runtime/include" "${nebula_root}/runtime/include/galaxy" "${nebula_root}/native/include")
target_compile_features(galaxy_native_spirv PRIVATE cxx_std_20)
target_link_libraries(galaxy_native_spirv PRIVATE nebula_vulkan_deps nebula_shader_compiler)

include("${nebula_root}/cmake/post_shader_sources.cmake")
set(galaxy_post_embed_cpp "${CMAKE_BINARY_DIR}/generated/post_shader_embed.cpp")
galaxy_embed_post_sources("${galaxy_post_embed_cpp}" "${nebula_root}")

add_executable(galaxy_utility_spirv
    "${nebula_root}/tools/dev/utility_spirv.cpp"
    "${nebula_root}/runtime/src/render/vk/shader_compile_vk.cpp"
    "${nebula_root}/runtime/src/render/renderer_common.cpp"
    "${galaxy_post_embed_cpp}")
target_include_directories(galaxy_utility_spirv PRIVATE
    "${nebula_root}/runtime/include" "${nebula_root}/runtime/include/galaxy" "${nebula_root}/native/include")
target_compile_features(galaxy_utility_spirv PRIVATE cxx_std_20)
target_link_libraries(galaxy_utility_spirv PRIVATE nebula_vulkan_deps nebula_shader_compiler)
