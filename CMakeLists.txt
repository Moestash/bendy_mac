cmake_minimum_required(VERSION 3.20)
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version" FORCE)
endif()
project(BENDY VERSION 2.0 LANGUAGES CXX)

if(NOT APPLE)
    message(FATAL_ERROR "This CMake build targets macOS. Use bendy_redo.sln on Windows.")
endif()
enable_language(OBJCXX)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 14)

set(BENDY_CORE_SOURCES
    src/Plugin.cpp src/Parameter.cpp src/Preset.cpp src/Scale.cpp
    src/Serializable.cpp src/State.cpp src/StreamWrapper.cpp
    src/fl/fp_cplug.cpp src/fl/fp_plugclass.cpp src/fl/fp_extra.cpp)
add_library(bendy_core OBJECT ${BENDY_CORE_SOURCES})
target_include_directories(bendy_core PUBLIC src src/fl)
target_compile_options(bendy_core PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_compile_options(bendy_core PRIVATE -Wno-inconsistent-missing-override)

add_library(BENDY SHARED $<TARGET_OBJECTS:bendy_core> src/mac/PluginGUI.mm)
target_include_directories(BENDY PRIVATE src src/fl)
target_compile_options(BENDY PRIVATE -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-inconsistent-missing-override)
target_link_libraries(BENDY PRIVATE "-framework Cocoa")
set_target_properties(BENDY PROPERTIES PREFIX "" OUTPUT_NAME "BENDY_x64"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/BENDY")
configure_file(src/mac/Plugin.nfo "${CMAKE_BINARY_DIR}/BENDY/Plugin.nfo" COPYONLY)
add_custom_command(TARGET BENDY POST_BUILD
    COMMAND /usr/bin/codesign --force --sign - "$<TARGET_FILE:BENDY>"
    COMMENT "Ad-hoc signing BENDY for local use" VERBATIM)

include(CTest)
if(BUILD_TESTING)
    add_executable(bendy_tests tests/mac_tests.mm $<TARGET_OBJECTS:bendy_core> src/mac/PluginGUI.mm)
    target_include_directories(bendy_tests PRIVATE src src/fl)
    target_compile_options(bendy_tests PRIVATE -fobjc-arc -Wno-inconsistent-missing-override)
    target_link_libraries(bendy_tests PRIVATE "-framework Cocoa")
    add_test(NAME bendy_core COMMAND bendy_tests)
    add_executable(bendy_load_test tests/load_plugin.cpp)
    target_include_directories(bendy_load_test PRIVATE src src/fl)
    target_compile_options(bendy_load_test PRIVATE -Wno-inconsistent-missing-override)
    add_dependencies(bendy_load_test BENDY)
    add_test(NAME bendy_load COMMAND bendy_load_test $<TARGET_FILE:BENDY>)
endif()
