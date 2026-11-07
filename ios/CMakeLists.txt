# =============================================================================
#  Fight Night Champion - Native iOS Static Recompilation App ("FNC Reborn iOS")
#  Xbox 360 Title ID: 45410915 / Media ID: 2DC50868 (arm64, iOS 16.0+)
#
#  Configure: cmake --preset ios
#  Build:     cmake --build --preset ios
#  Package:   cmake --build --preset ios --target ipa
# =============================================================================

cmake_minimum_required(VERSION 3.25)

if(NOT CMAKE_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME "iOS")
endif()
if(NOT CMAKE_SYSTEM_PROCESSOR)
    set(CMAKE_SYSTEM_PROCESSOR "arm64")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()
if(NOT CMAKE_OSX_SYSROOT)
    set(CMAKE_OSX_SYSROOT "iphoneos")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0")
endif()
set(REX_PLATFORM_IOS 1 CACHE BOOL "Build for iOS platform" FORCE)
add_compile_definitions(REX_PLATFORM_IOS=1)

# Ensure clang from iphoneos SDK toolchain is preferred
if(APPLE AND NOT CMAKE_C_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang
        OUTPUT_VARIABLE _IOS_CLANG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANG AND EXISTS "${_IOS_CLANG}")
        set(CMAKE_C_COMPILER "${_IOS_CLANG}" CACHE FILEPATH "C compiler" FORCE)
    endif()
endif()
if(APPLE AND NOT CMAKE_CXX_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang++
        OUTPUT_VARIABLE _IOS_CLANGXX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANGXX AND EXISTS "${_IOS_CLANGXX}")
        set(CMAKE_CXX_COMPILER "${_IOS_CLANGXX}" CACHE FILEPATH "CXX compiler" FORCE)
    endif()
endif()

project(fnc_ios LANGUAGES C CXX OBJC OBJCXX ASM)

if(NOT IOS)
    message(FATAL_ERROR "This CMakeLists.txt is for iOS: configure with cmake --preset ios")
endif()

set(FNC_REPO "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "FNC Reborn repository root")
set(FNC_SDK "${FNC_REPO}/../rexglue-sdk-ios" CACHE PATH
    "ReXGlue SDK prepared for iOS (tools/ios/prepare_sdk.py)")
set(FNC_BUNDLE_ID "com.recomp.fncreborn.ios" CACHE STRING "App bundle identifier")
set(FNC_GEN_DIR "${FNC_REPO}/generated/default" CACHE PATH
    "Generated recompilation code (tools/generate_code.py)")
set(FNC_JOBS_RECOMP "2" CACHE STRING "Generated files compiled at once")
get_filename_component(FNC_REPO "${FNC_REPO}" ABSOLUTE)
get_filename_component(FNC_SDK "${FNC_SDK}" ABSOLUTE)

# Locate MoltenVK.framework
set(_mvk_marker "${FNC_SDK}/.fnc-ios/MoltenVK/v1.4.1.ready")
if(NOT EXISTS "${_mvk_marker}")
    set(_mvk_marker "${FNC_SDK}/.nfsc-ios/MoltenVK/v1.4.1.ready")
endif()
if(NOT EXISTS "${_mvk_marker}")
    set(_mvk_marker "${FNC_SDK}/.nfsmw-ios/MoltenVK/v1.4.1.ready")
endif()

if(EXISTS "${_mvk_marker}")
    file(STRINGS "${_mvk_marker}" _mvk_rel LIMIT_COUNT 1)
    set(FNC_MOLTENVK_FW "${FNC_SDK}/.fnc-ios/MoltenVK/${_mvk_rel}/ios-arm64/MoltenVK.framework")
    if(NOT EXISTS "${FNC_MOLTENVK_FW}/MoltenVK")
        set(FNC_MOLTENVK_FW "${FNC_SDK}/.nfsc-ios/MoltenVK/${_mvk_rel}/ios-arm64/MoltenVK.framework")
    endif()
endif()

# Fallback auto-discovery
if(NOT EXISTS "${FNC_MOLTENVK_FW}/MoltenVK")
    file(GLOB_RECURSE _found_mvk
        "${FNC_SDK}/.fnc-ios/*/ios-arm64/MoltenVK.framework"
        "${FNC_SDK}/.nfsc-ios/*/ios-arm64/MoltenVK.framework"
        "${FNC_SDK}/.nfsmw-ios/*/ios-arm64/MoltenVK.framework"
        "${FNC_SDK}/*/ios-arm64/MoltenVK.framework"
    )
    if(_found_mvk)
        list(GET _found_mvk 0 FNC_MOLTENVK_FW)
    endif()
endif()

if(EXISTS "${FNC_MOLTENVK_FW}")
    message(STATUS "FNC Reborn: Found MoltenVK.framework at ${FNC_MOLTENVK_FW}")
else()
    message(WARNING "FNC Reborn: MoltenVK.framework not found in SDK; will not be bundled")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(REXGLUE_USE_VULKAN ON CACHE BOOL "" FORCE)
set(REXGLUE_USE_D3D12 OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_DESKTOP_SDL_BACKENDS OFF CACHE BOOL "" FORCE)

if(EXISTS "${FNC_SDK}/CMakeLists.txt")
    add_subdirectory("${FNC_SDK}" rexglue-sdk)
endif()

# Header-only interface library for SDK dependencies
add_library(fnc_headers INTERFACE)
if(TARGET imgui)
    target_include_directories(fnc_headers INTERFACE
        $<TARGET_PROPERTY:imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()
if(TARGET Vulkan::Headers)
    target_link_libraries(fnc_headers INTERFACE Vulkan::Headers)
endif()
if(TARGET GPUOpen::VulkanMemoryAllocator)
    target_link_libraries(fnc_headers INTERFACE GPUOpen::VulkanMemoryAllocator)
endif()
if(TARGET spirv-tools-headers)
    target_link_libraries(fnc_headers INTERFACE spirv-tools-headers)
endif()

# -----------------------------------------------------------------------------
#  Generated Game Code (PowerPC to ARM64 C++)
# -----------------------------------------------------------------------------
set(FNC_WITH_GAME OFF)
if(EXISTS "${FNC_GEN_DIR}/sources.cmake")
    include("${FNC_GEN_DIR}/sources.cmake")
    if(GENERATED_SOURCES)
        set(FNC_WITH_GAME ON)

        add_library(fnc_recomp STATIC ${GENERATED_SOURCES})
        target_include_directories(fnc_recomp PRIVATE
            "${FNC_REPO}"
            "${FNC_REPO}/src"
            "${FNC_GEN_DIR}")
        if(TARGET rex::runtime)
            target_link_libraries(fnc_recomp PUBLIC rex::runtime fnc_headers)
            rexglue_apply_target_settings(fnc_recomp)
        endif()

        if(EXISTS "${FNC_GEN_DIR}/fnc_pch.h")
            target_precompile_headers(fnc_recomp PRIVATE "${FNC_GEN_DIR}/fnc_pch.h")
        endif()
        target_compile_options(fnc_recomp PRIVATE -gline-tables-only -Wno-unused-variable -ffp-contract=fast)
        if(EXISTS "${FNC_GEN_DIR}/fnc_register.cpp")
            set_source_files_properties("${FNC_GEN_DIR}/fnc_register.cpp"
                PROPERTIES COMPILE_OPTIONS "-O1")
        endif()
        if(EXISTS "${FNC_GEN_DIR}/fnc_init.cpp")
            set_source_files_properties("${FNC_GEN_DIR}/fnc_init.cpp"
                PROPERTIES COMPILE_OPTIONS "-O1")
        endif()
        set_property(GLOBAL APPEND PROPERTY JOB_POOLS recomp=${FNC_JOBS_RECOMP})
        set_target_properties(fnc_recomp PROPERTIES JOB_POOL_COMPILE recomp)
        message(STATUS "FNC Reborn: Compiling with statically recompiled PowerPC code (${FNC_GEN_DIR})")
    else()
        message(FATAL_ERROR "FNC Reborn: sources.cmake found but GENERATED_SOURCES is empty in ${FNC_GEN_DIR}")
    endif()
else()
    message(FATAL_ERROR "FNC Reborn: No generated code found in ${FNC_GEN_DIR}. Codegen is mandatory.")
endif()

# -----------------------------------------------------------------------------
#  Application Target (FNCReborn.app)
# -----------------------------------------------------------------------------
set(FNC_VERSION "1.0.11")
set(FNC_VERSION_CODE "11")
set(FNC_DISPLAY_NAME "Fight Night Champion")
set(FNC_IOS_MIN "${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(FNC_EXECUTABLE "FNCReborn")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
               "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)

set(FNC_APP_SOURCES
    src/ios_main.mm
    # ReXApp is implemented by the consuming executable, not librexruntime.
    "${FNC_SDK}/src/ui/rex_app.cpp"
    src/launcher.mm
    src/touch_controls.mm
    src/save_manager.mm
    src/boot_trace.cpp
    src/battery.mm
    src/lifecycle.mm
    src/memory_report.mm
    src/ios_haptics.mm
    src/display_rate.mm
    src/audio/coreaudio_driver.mm
    # Game Overrides & Hooks
    ${FNC_REPO}/src/fnc_hooks.cpp
    ${FNC_REPO}/src/player_camera.cpp
    ${FNC_REPO}/src/fnc_fps_overlay.cpp
    ${FNC_REPO}/src/fnc_settings_menu.cpp
    ${FNC_REPO}/src/fnc_sampler.cpp
)

add_executable(fncreborn ${FNC_APP_SOURCES})

set_target_properties(fncreborn PROPERTIES
    MACOSX_BUNDLE YES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "${FNC_DISPLAY_NAME}"
    MACOSX_BUNDLE_EXECUTABLE_NAME "${FNC_EXECUTABLE}"
    OUTPUT_NAME "${FNC_EXECUTABLE}"
    INSTALL_RPATH "@loader_path/Frameworks;@executable_path/Frameworks"
    BUILD_WITH_INSTALL_RPATH TRUE
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${FNC_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
)

target_include_directories(fncreborn PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${FNC_REPO}/src"
    "${FNC_REPO}"
    "${FNC_GEN_DIR}"
)

target_compile_definitions(fncreborn PRIVATE
    REX_PLATFORM_IOS=1
    TITLE_ID="45410915"
    MEDIA_ID="2DC50868"
    REXGLUE_BUILD_CONFIG="Release"
)

target_compile_options(fncreborn PRIVATE
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
    $<$<CXX_COMPILER_ID:Clang,AppleClang>:-gline-tables-only>
)

target_link_libraries(fncreborn PRIVATE
    fnc_headers
    "-framework Foundation"
    "-framework UIKit"
    "-framework Metal"
    "-framework MetalFX"
    "-framework QuartzCore"
    "-framework CoreImage"
    "-framework UniformTypeIdentifiers"
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework GameController"
    "-framework CoreHaptics"
    z
)

if(TARGET rex::runtime)
    target_link_libraries(fncreborn PRIVATE rex::runtime)
endif()

if(FNC_WITH_GAME)
    # Prevent linker dead-stripping of statically recompiled guest functions
    add_dependencies(fncreborn fnc_recomp)
    target_link_libraries(fncreborn PRIVATE fnc_recomp -Wl,-force_load,$<TARGET_FILE:fnc_recomp>)
endif()

if(TARGET rexgpu-xenos)
    add_dependencies(fncreborn rexgpu-xenos)
endif()

# -----------------------------------------------------------------------------
#  Native Metal Shader Compilation (FNCShaders.metallib)
# -----------------------------------------------------------------------------
set(_metal_src "${CMAKE_CURRENT_SOURCE_DIR}/resources/shaders/FNCShaders.metal")
set(_air_out "${CMAKE_CURRENT_BINARY_DIR}/FNCShaders.air")
set(_metallib_out "${CMAKE_CURRENT_BINARY_DIR}/FNCShaders.metallib")

add_custom_command(
    OUTPUT "${_metallib_out}"
    COMMAND xcrun -sdk iphoneos metal -c -std=metal3.0 "${_metal_src}" -o "${_air_out}"
    COMMAND xcrun -sdk iphoneos metallib "${_air_out}" -o "${_metallib_out}"
    DEPENDS "${_metal_src}"
    COMMENT "FNC Reborn: Compiling Apple Metal shader library (FNCShaders.metallib)"
    VERBATIM
)
add_custom_target(fnc_metal_shaders DEPENDS "${_metallib_out}")
add_dependencies(fncreborn fnc_metal_shaders)

# -----------------------------------------------------------------------------
#  Packaging & Code Signing Target (Ad-Hoc for Sideloading)
# -----------------------------------------------------------------------------
set(_app "$<TARGET_BUNDLE_DIR:fncreborn>")
set(_fw "${_app}/Frameworks")

if(TARGET rexruntime)
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexruntime>" "${_fw}/")
    set(_sign_rexruntime COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexruntime>" 2>/dev/null || true)
    set(_dep_rexruntime rexruntime)
else()
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexruntime "")
endif()

if(TARGET rexgpu-xenos)
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexgpu-xenos>" "${_fw}/")
    set(_sign_rexgpu COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexgpu-xenos>" 2>/dev/null || true)
    set(_dep_rexgpu rexgpu-xenos)
else()
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexgpu "")
endif()

if(EXISTS "${FNC_MOLTENVK_FW}")
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E copy_directory "${FNC_MOLTENVK_FW}" "${_fw}/MoltenVK.framework")
    set(_sign_mvk_cmd COMMAND codesign --force --sign - --timestamp=none "${_fw}/MoltenVK.framework" 2>/dev/null || true)
else()
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
endif()

# Prewarmed pipeline cache
set(_vkcache_src "${CMAKE_CURRENT_SOURCE_DIR}/resources/shaders/45410915.fbo.vkcache")
set(_title_icon_src "${CMAKE_CURRENT_SOURCE_DIR}/resources/title_icon_64x64.png")

add_custom_target(fncreborn_package ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_fw}"
    ${_copy_rexruntime}
    ${_copy_rexgpu}
    ${_copy_mvk_cmd}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_vkcache_src}" "${_app}/45410915.fbo.vkcache"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_metallib_out}" "${_app}/FNCShaders.metallib"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_title_icon_src}" "${_app}/title_icon_64x64.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../config/FNCReborn.toml" "${_app}/FNCReborn.toml"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/../config/FNCReborn.toml" "${_app}/config.toml"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon-1024.png" "${_app}/AppIcon-1024.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon1024x1024.png" "${_app}/AppIcon1024x1024.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon60x60@2x.png" "${_app}/AppIcon60x60@2x.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon60x60@3x.png" "${_app}/AppIcon60x60@3x.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon76x76@2x~ipad.png" "${_app}/AppIcon76x76@2x~ipad.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon83.5x83.5@2x~ipad.png" "${_app}/AppIcon83.5x83.5@2x~ipad.png"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon.png" "${_app}/AppIcon.png"
    COMMAND xcrun actool "${CMAKE_CURRENT_SOURCE_DIR}/resources/Assets.xcassets"
            --compile "${_app}" --platform iphoneos
            --minimum-deployment-target "${CMAKE_OSX_DEPLOYMENT_TARGET}"
            --target-device iphone --target-device ipad --app-icon AppIcon
            --output-partial-info-plist "${CMAKE_CURRENT_BINARY_DIR}/actool-partial.plist"
            --output-format human-readable-text --errors --warnings || true
    COMMAND /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon60x60" "${_app}/Info.plist" || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon60x60" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles array" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:0 string AppIcon60x60" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:1 string AppIcon76x76" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:2 string AppIcon83.5x83.5" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:3 string AppIcon1024x1024" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:4 string AppIcon-1024" "${_app}/Info.plist" || true
    COMMAND /usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles:5 string AppIcon" "${_app}/Info.plist" || true
    COMMAND xattr -cr "${_app}" || true
    ${_sign_mvk_cmd}
    ${_sign_rexruntime}
    ${_sign_rexgpu}
    COMMAND codesign --force --sign - --timestamp=none
            --entitlements "${CMAKE_CURRENT_SOURCE_DIR}/fncreborn.entitlements" "${_app}" || true
    COMMENT "FNC Reborn: Packaging and signing FNCReborn.app"
    VERBATIM
)
add_dependencies(fncreborn_package fncreborn ${_dep_rexruntime} ${_dep_rexgpu} fnc_metal_shaders)

# -----------------------------------------------------------------------------
#  IPA Generation Target
# -----------------------------------------------------------------------------
add_custom_target(ipa
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_CURRENT_BINARY_DIR}/ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload"
    COMMAND ditto "${_app}" "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload/FNCReborn.app"
    COMMAND chmod 755 "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload/FNCReborn.app/FNCReborn"
    COMMAND find "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload/FNCReborn.app/Frameworks" -type f -exec chmod 755 {} + || true
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn.ipa"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E chdir "${CMAKE_CURRENT_BINARY_DIR}/ipa"
            ditto -c -k --sequesterRsrc --keepParent Payload "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn-iOS-unsigned.ipa"
            "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn.ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/build"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn-iOS-unsigned.ipa"
            "${CMAKE_CURRENT_SOURCE_DIR}/build/FNCReborn-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/FNCReborn.ipa"
            "${CMAKE_CURRENT_SOURCE_DIR}/build/FNCReborn.ipa"
    COMMENT "FNC Reborn: Generated unsigned IPA package at build/FNCReborn-iOS-unsigned.ipa"
    VERBATIM
)
add_dependencies(ipa fncreborn_package)

