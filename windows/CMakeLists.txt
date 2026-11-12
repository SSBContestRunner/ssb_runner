# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(ssb_runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "ssb_runner")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Microsoft Visual C++ runtime, taken from the toolset that compiles this build.
# The app links the CRT dynamically (/MD is the CMake default here), so without
# these DLLs next to the executable the portable zip only starts on machines
# that already have the VC++ Redistributable installed.
#
# Why not a checked-in copy: Windows always loads the DLL next to the
# executable, so a copy older than the compiler wins over the system one. That
# is how 0.3.0-alpha02 died with 0xC0000005 inside msvcp140.dll before the first
# frame -- the bundle shipped 14.36 while the runner was compiled by 14.51, and
# the new std::ostringstream/std::thread code in the runner tripped over the old
# runtime. The file versions are asserted below, so a toolset or image upgrade
# fails here instead of at startup.
if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
  message(FATAL_ERROR
    "The Windows bundle ships the MSVC redistributable, but the compiler is "
    "${CMAKE_CXX_COMPILER_ID}. Build with MSVC.")
endif()

# MSVC 19.51 maps to the 14.51 toolset, which is the version in the DLLs.
if(NOT CMAKE_CXX_COMPILER_VERSION MATCHES "^19\\.([0-9]+)")
  message(FATAL_ERROR
    "Unexpected MSVC version '${CMAKE_CXX_COMPILER_VERSION}'; expected 19.x so it "
    "can be mapped to the 14.x toolset version.")
endif()
set(SSB_TOOLSET_MINOR "${CMAKE_MATCH_1}")

if(DEFINED ENV{VCToolsRedistDir})
  # Set by a Developer Command Prompt; may point at .../Redist/MSVC or at the
  # versioned .../Redist/MSVC/<ver> folder.
  file(TO_CMAKE_PATH "$ENV{VCToolsRedistDir}" SSB_REDIST_ROOT)
else()
  # Visual Studio generators do not export VCToolsRedistDir. Derive the same
  # folder from the compiler CMake selected, so two installed toolsets cannot
  # make the bundle use the other one's runtime.
  # <VC>/Tools/MSVC/<toolset>/bin/Hostx64/x64/cl.exe
  get_filename_component(SSB_CL_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
  get_filename_component(SSB_HOST_DIR "${SSB_CL_DIR}" DIRECTORY)
  get_filename_component(SSB_BIN_DIR "${SSB_HOST_DIR}" DIRECTORY)
  get_filename_component(SSB_TOOLSET_DIR "${SSB_BIN_DIR}" DIRECTORY)
  get_filename_component(SSB_MSVC_DIR "${SSB_TOOLSET_DIR}" DIRECTORY)
  get_filename_component(SSB_TOOLS_DIR "${SSB_MSVC_DIR}" DIRECTORY)
  get_filename_component(SSB_VC_DIR "${SSB_TOOLS_DIR}" DIRECTORY)
  set(SSB_REDIST_ROOT "${SSB_VC_DIR}/Redist/MSVC")
endif()

# The redistributable's own version differs from the toolset's in its last
# component (a 14.51.36231 toolset ships a 14.51.36247 runtime), so every
# installed redist is a candidate and the newest one that is not older than the
# compiler wins. Only the first two components are compared.
file(GLOB SSB_CRT_DIRS
  "${SSB_REDIST_ROOT}/x64/Microsoft.VC*.CRT"
  "${SSB_REDIST_ROOT}/*/x64/Microsoft.VC*.CRT")

# Reads the leading "major.minor" of a DLL's file version.
function(SSB_READ_RUNTIME_VERSION DLL OUT_MAJOR OUT_MINOR)
  execute_process(
    COMMAND powershell -NoProfile -NonInteractive -Command
      "[IO.FileInfo]::new('${DLL}').VersionInfo.FileVersion"
    OUTPUT_VARIABLE version
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE error
    RESULT_VARIABLE result)
  if(NOT result EQUAL 0 OR version STREQUAL "")
    message(FATAL_ERROR "could not read the file version of ${DLL}: ${error}")
  endif()
  if(NOT version MATCHES "^([0-9]+)\\.([0-9]+)")
    message(FATAL_ERROR "unexpected file version '${version}' in ${DLL}")
  endif()
  set(${OUT_MAJOR} "${CMAKE_MATCH_1}" PARENT_SCOPE)
  set(${OUT_MINOR} "${CMAKE_MATCH_2}" PARENT_SCOPE)
endfunction()

set(SSB_CRT_DIR "")
set(SSB_CRT_MINOR -1)
foreach(crt_dir IN LISTS SSB_CRT_DIRS)
  set(candidate "${crt_dir}/msvcp140.dll")
  if(NOT EXISTS "${candidate}")
    continue()
  endif()
  SSB_READ_RUNTIME_VERSION("${candidate}" candidate_major candidate_minor)
  if(NOT candidate_major EQUAL 14 OR candidate_minor LESS SSB_TOOLSET_MINOR)
    continue()
  endif()
  if(SSB_CRT_MINOR LESS candidate_minor)
    set(SSB_CRT_MINOR "${candidate_minor}")
    set(SSB_CRT_DIR "${crt_dir}")
  endif()
endforeach()
if(SSB_CRT_DIR STREQUAL "")
  message(FATAL_ERROR
    "No MSVC redistributable at or above 14.${SSB_TOOLSET_MINOR} under "
    "${SSB_REDIST_ROOT}. Install the VC++ Redistributable matching the compiler; "
    "shipping an older msvcp140.dll next to the executable crashes at startup.")
endif()

set(SSB_RUNTIME_DLLS "")
foreach(runtime msvcp140 vcruntime140 vcruntime140_1)
  set(dll "${SSB_CRT_DIR}/${runtime}.dll")
  if(NOT EXISTS "${dll}")
    message(FATAL_ERROR "${runtime}.dll is missing from ${SSB_CRT_DIR}")
  endif()
  SSB_READ_RUNTIME_VERSION("${dll}" runtime_major runtime_minor)
  if(NOT runtime_major EQUAL 14 OR runtime_minor LESS SSB_TOOLSET_MINOR)
    message(FATAL_ERROR
      "${runtime}.dll is ${runtime_major}.${runtime_minor}, older than the "
      "14.${SSB_TOOLSET_MINOR} toolset that built this bundle. The loader would "
      "prefer it over the system copy and crash at startup.")
  endif()
  list(APPEND SSB_RUNTIME_DLLS "${dll}")
endforeach()

install(FILES ${SSB_RUNTIME_DLLS}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
