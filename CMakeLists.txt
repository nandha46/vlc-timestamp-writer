cmake_minimum_required(VERSION 3.10)
project(vlc_timestamp_writer C)

set(CMAKE_C_STANDARD 99)

# Locate VLC SDK (LibVLC & VLC Core headers)
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(VLC vlc-plugin)
endif()

if(NOT VLC_FOUND)
    # Manual fallback if pkg-config is not available (e.g. Windows)
    set(VLC_INCLUDE_DIRS "" CACHE PATH "Path to VLC include directory (containing vlc/vlc.h and vlc_common.h)")
    set(VLC_LIB_DIRS "" CACHE PATH "Path to VLC lib directory (containing vlccore.lib / libvlccore.dll.a)")
    
    if(VLC_INCLUDE_DIRS)
        include_directories(${VLC_INCLUDE_DIRS})
    endif()
    if(VLC_LIB_DIRS)
        link_directories(${VLC_LIB_DIRS})
    endif()
else()
    include_directories(${VLC_INCLUDE_DIRS})
    link_directories(${VLC_LIBRARY_DIRS})
endif()

add_library(timestamp_writer_plugin MODULE src/timestamp_writer.c)

# VLC modules must have specific naming conventions and definition flags
set_target_properties(timestamp_writer_plugin PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "timestamp_writer_plugin"
)

target_compile_definitions(timestamp_writer_plugin PRIVATE
    __PLUGIN__
    _FILE_OFFSET_BITS=64
    __LIBVLC__
)

if(WIN32)
    target_link_libraries(timestamp_writer_plugin PRIVATE vlccore)
else()
    target_link_libraries(timestamp_writer_plugin PRIVATE vlccore)
endif()
