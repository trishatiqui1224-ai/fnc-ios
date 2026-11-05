cmake_minimum_required(VERSION 3.25)

if(APPLE)
    project(fnc_ios LANGUAGES C CXX OBJC OBJCXX ASM)
else()
    project(fnc LANGUAGES C CXX ASM)
endif()

if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_subdirectory(ios)
else()
    set(CMAKE_CXX_STANDARD 23)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    # ReXGlue SDK & recompilation sources for host/desktop targets
    include(generated/rexglue.cmake OPTIONAL)

    set(FNC_SOURCES
        src/main.cpp
        src/fnc_hooks.cpp
        src/player_camera.cpp
        src/fnc_fps_overlay.cpp
        src/fnc_settings_menu.cpp
        src/fnc_sampler.cpp
    )

    if(WIN32)
        add_executable(FNCReborn WIN32 ${FNC_SOURCES})
    else()
        add_executable(FNCReborn ${FNC_SOURCES})
    endif()

    if(COMMAND rexglue_setup_target)
        rexglue_setup_target(FNCReborn GPU_PLUGINS xenos)
    endif()

    target_include_directories(FNCReborn PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/generated/default"
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endif()
