cmake_minimum_required(VERSION 3.22)

project(AccessXI_PolPlugin LANGUAGES CXX)

enable_testing()

option(ACCESSXI_COLLISION_ONLY "Configure the collision-navigation targets without requiring the Ashita SDK" OFF)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "AccessXI PlayOnline in-process targets must be configured as 32-bit Win32.")
endif()

add_library(accessxi_pol_hook SHARED
    src/accessxi_pol.cpp
    src/accessxi_pol.def
    src/pol_accessibility/prelogin_semantics.cpp
    src/pol_pml/native_popup_text.cpp
    src/pol_pml/native_selected_text.cpp
    src/pol_pml/native_text_field.cpp
    src/pol_trace/postlogin_trace.cpp
)

target_compile_features(accessxi_pol_hook PRIVATE cxx_std_20)
target_compile_definitions(accessxi_pol_hook PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

if(NOT ACCESSXI_COLLISION_ONLY AND NOT DEFINED ENV{ASHITA4_SDK_PATH})
    message(FATAL_ERROR "ASHITA4_SDK_PATH must point to Ashita v4 plugins/sdk, for example C:/Users/buu42/Ashita/plugins/sdk")
endif()

target_include_directories(accessxi_pol_hook PRIVATE
    "$ENV{ASHITA4_SDK_PATH}"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(accessxi_pol_hook PRIVATE
    oleacc
    oleaut32
)

set_target_properties(accessxi_pol_hook PROPERTIES
    OUTPUT_NAME "accessxi_pol_native"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

add_library(accessxi_pol_native_asi SHARED
    src/pol_native/diagnostics.cpp
    src/pol_native/native_host.cpp
    src/pol_native/pol_native_asi.cpp
    src/pol_native/pol_native_asi.def
    src/pol_native/prism_runtime.cpp
    src/pol_native/speech_queue.cpp
    src/pol_native/speech_worker.cpp
)
target_compile_features(accessxi_pol_native_asi PRIVATE cxx_std_20)
target_compile_definitions(accessxi_pol_native_asi PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(accessxi_pol_native_asi PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(accessxi_pol_native_asi PRIVATE user32)
set_target_properties(accessxi_pol_native_asi PROPERTIES
    PREFIX ""
    OUTPUT_NAME "AccessXI.PolNative"
    SUFFIX ".asi"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

add_executable(pol_native_queue_tests
    src/pol_native/speech_queue.cpp
    tests/pol_native_queue_tests.cpp
)

target_compile_features(pol_native_queue_tests PRIVATE cxx_std_20)
target_compile_definitions(pol_native_queue_tests PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(pol_native_queue_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_test(NAME pol_native_queue_tests COMMAND pol_native_queue_tests)

add_executable(pol_postlogin_trace_tests
    src/pol_trace/postlogin_trace.cpp
    tests/pol_postlogin_trace_tests.cpp
)
target_compile_features(pol_postlogin_trace_tests PRIVATE cxx_std_20)
target_compile_definitions(pol_postlogin_trace_tests PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(pol_postlogin_trace_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME pol_postlogin_trace_tests COMMAND pol_postlogin_trace_tests)

add_executable(pol_prelogin_semantics_tests
    src/pol_accessibility/prelogin_semantics.cpp
    tests/pol_prelogin_semantics_tests.cpp
)
target_compile_features(pol_prelogin_semantics_tests PRIVATE cxx_std_20)
target_include_directories(pol_prelogin_semantics_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME pol_prelogin_semantics_tests COMMAND pol_prelogin_semantics_tests)

add_executable(pol_pml_selected_text_tests
    src/pol_pml/native_selected_text.cpp
    tests/pol_pml_selected_text_tests.cpp
)
target_compile_features(pol_pml_selected_text_tests PRIVATE cxx_std_20)
target_include_directories(pol_pml_selected_text_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME pol_pml_selected_text_tests COMMAND pol_pml_selected_text_tests)

add_executable(pol_pml_text_field_tests
    src/pol_pml/native_text_field.cpp
    tests/pol_pml_text_field_tests.cpp
)
target_compile_features(pol_pml_text_field_tests PRIVATE cxx_std_20)
target_include_directories(pol_pml_text_field_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME pol_pml_text_field_tests COMMAND pol_pml_text_field_tests)

add_executable(pol_pml_popup_text_tests
    src/pol_pml/native_popup_text.cpp
    tests/pol_pml_popup_text_tests.cpp
)
target_compile_features(pol_pml_popup_text_tests PRIVATE cxx_std_20)
target_include_directories(pol_pml_popup_text_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_test(NAME pol_pml_popup_text_tests COMMAND pol_pml_popup_text_tests)

add_library(fake_prism SHARED
    tests/fakes/fake_prism.cpp
    tests/fakes/fake_prism.def
)
target_compile_features(fake_prism PRIVATE cxx_std_20)
target_compile_definitions(fake_prism PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    PRISM_BUILDING
)
target_include_directories(fake_prism PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/prism/include"
)
set_target_properties(fake_prism PROPERTIES
    OUTPUT_NAME "fake_prism"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
)

add_executable(pol_native_speech_worker_tests
    src/pol_native/diagnostics.cpp
    src/pol_native/prism_runtime.cpp
    src/pol_native/speech_queue.cpp
    src/pol_native/speech_worker.cpp
    tests/pol_native_speech_worker_tests.cpp
)
target_compile_features(pol_native_speech_worker_tests PRIVATE cxx_std_20)
target_compile_definitions(pol_native_speech_worker_tests PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(pol_native_speech_worker_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(pol_native_speech_worker_tests PRIVATE user32)
add_dependencies(pol_native_speech_worker_tests fake_prism)

add_test(
    NAME pol_native_speech_worker_tests
    COMMAND pol_native_speech_worker_tests "$<TARGET_FILE:fake_prism>"
)

add_library(fake_pol_hook SHARED
    tests/fakes/fake_pol_hook.cpp
    tests/fakes/fake_pol_hook.def
)
target_compile_features(fake_pol_hook PRIVATE cxx_std_20)
target_compile_definitions(fake_pol_hook PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(fake_pol_hook PROPERTIES
    OUTPUT_NAME "fake_pol_hook"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
)

add_library(fake_pol_hook_no_sink SHARED
    tests/fakes/fake_pol_hook.cpp
    tests/fakes/fake_pol_hook_no_sink.def
)
target_compile_features(fake_pol_hook_no_sink PRIVATE cxx_std_20)
target_compile_definitions(fake_pol_hook_no_sink PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    ACCESSXI_FAKE_HOOK_OMIT_SINK
)
set_target_properties(fake_pol_hook_no_sink PROPERTIES
    OUTPUT_NAME "fake_pol_hook_no_sink"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
)

add_library(fake_pol_hook_no_init SHARED
    tests/fakes/fake_pol_hook.cpp
    tests/fakes/fake_pol_hook_no_init.def
)
target_compile_features(fake_pol_hook_no_init PRIVATE cxx_std_20)
target_compile_definitions(fake_pol_hook_no_init PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    ACCESSXI_FAKE_HOOK_OMIT_INIT
)
set_target_properties(fake_pol_hook_no_init PROPERTIES
    OUTPUT_NAME "fake_pol_hook_no_init"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test-bin"
)

add_executable(pol_native_host_tests
    src/pol_native/diagnostics.cpp
    src/pol_native/native_host.cpp
    src/pol_native/prism_runtime.cpp
    src/pol_native/speech_queue.cpp
    src/pol_native/speech_worker.cpp
    tests/pol_native_host_tests.cpp
)
target_compile_features(pol_native_host_tests PRIVATE cxx_std_20)
target_compile_definitions(pol_native_host_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(pol_native_host_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(pol_native_host_tests PRIVATE user32)
add_dependencies(
    pol_native_host_tests
    fake_prism
    fake_pol_hook
    fake_pol_hook_no_sink
    fake_pol_hook_no_init
)
add_test(
    NAME pol_native_host_tests
    COMMAND pol_native_host_tests
        "$<TARGET_FILE:fake_prism>"
        "$<TARGET_FILE:fake_pol_hook>"
        "$<TARGET_FILE:fake_pol_hook_no_sink>"
        "$<TARGET_FILE:fake_pol_hook_no_init>"
        "C:/Program Files (x86)/PlayOnline/SquareEnix/PlayOnlineViewer/viewer/com/app.dll"
)

set(ACCESSXI_RECAST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/external/recastnavigation" CACHE PATH
    "Pinned Recast Navigation checkout")
set(ACCESSXI_BULLET_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/external/bullet3" CACHE PATH
    "Pinned Bullet checkout")

if(NOT EXISTS "${ACCESSXI_RECAST_ROOT}/Recast/Include/Recast.h")
    message(FATAL_ERROR "Pinned Recast checkout is missing. Run tools/fetch_collision_dependencies.ps1.")
endif()
if(NOT EXISTS "${ACCESSXI_BULLET_ROOT}/src/btBulletCollisionCommon.h")
    message(FATAL_ERROR "Pinned Bullet checkout is missing. Run tools/fetch_collision_dependencies.ps1.")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build collision dependencies statically" FORCE)
set(RECASTNAVIGATION_DEMO OFF CACHE BOOL "Do not build Recast demo" FORCE)
set(RECASTNAVIGATION_TESTS OFF CACHE BOOL "Do not build upstream Recast tests" FORCE)
set(RECASTNAVIGATION_EXAMPLES OFF CACHE BOOL "Do not build Recast examples" FORCE)
set(RECASTNAVIGATION_ENABLE_FAST_MATH OFF CACHE BOOL "Keep deterministic collision math" FORCE)
add_subdirectory("${ACCESSXI_RECAST_ROOT}" "${CMAKE_BINARY_DIR}/recast" EXCLUDE_FROM_ALL)

set(BUILD_BULLET2_DEMOS OFF CACHE BOOL "Do not build Bullet demos" FORCE)
set(BUILD_BULLET3 OFF CACHE BOOL "Do not build Bullet 3 experiments" FORCE)
set(BUILD_CPU_DEMOS OFF CACHE BOOL "Do not build Bullet CPU demos" FORCE)
set(BUILD_EXTRAS OFF CACHE BOOL "Do not build Bullet extras" FORCE)
set(BUILD_OPENGL3_DEMOS OFF CACHE BOOL "Do not build Bullet OpenGL demos" FORCE)
set(BUILD_UNIT_TESTS OFF CACHE BOOL "Do not build upstream Bullet tests" FORCE)
set(BUILD_PYBULLET OFF CACHE BOOL "Do not build PyBullet" FORCE)
set(USE_DOUBLE_PRECISION OFF CACHE BOOL "Use 32-bit Bullet coordinates" FORCE)
set(USE_MSVC_FAST_FLOATINGPOINT OFF CACHE BOOL "Keep deterministic collision math" FORCE)
add_subdirectory("${ACCESSXI_BULLET_ROOT}" "${CMAKE_BINARY_DIR}/bullet" EXCLUDE_FROM_ALL)

add_library(accessxi_collision_core STATIC
    src/collision_native/file_snapshot.cpp
    src/collision_native/rom_resolver.cpp
)
target_compile_features(accessxi_collision_core PUBLIC cxx_std_20)
target_compile_definitions(accessxi_collision_core PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(accessxi_collision_core PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(accessxi_collision_core PUBLIC
    RecastNavigation::Recast
    RecastNavigation::Detour
    BulletCollision
    LinearMath
    bcrypt
)

add_library(accessxi_collision_native SHARED
    src/collision_native/collision_exports.cpp
    src/collision_native/accessxi_collision_native.def
)
target_compile_features(accessxi_collision_native PRIVATE cxx_std_20)
target_compile_definitions(accessxi_collision_native PRIVATE
    ACCESSXI_COLLISION_NATIVE_EXPORTS
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(accessxi_collision_native PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(accessxi_collision_native PRIVATE
    accessxi_collision_core
)
set_target_properties(accessxi_collision_native PROPERTIES
    PREFIX ""
    OUTPUT_NAME "accessxi_collision_native"
    DEBUG_POSTFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

add_executable(collision_context_tests
    tests/collision_context_tests.cpp
)
target_compile_features(collision_context_tests PRIVATE cxx_std_20)
target_include_directories(collision_context_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(collision_context_tests PRIVATE accessxi_collision_native)
set_target_properties(collision_context_tests PROPERTIES
    DEBUG_POSTFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
add_test(NAME collision_context_tests COMMAND collision_context_tests)

add_executable(collision_rom_resolver_tests
    tests/collision_rom_resolver_tests.cpp
)
target_compile_features(collision_rom_resolver_tests PRIVATE cxx_std_20)
target_include_directories(collision_rom_resolver_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(collision_rom_resolver_tests PRIVATE accessxi_collision_core)
set_target_properties(collision_rom_resolver_tests PROPERTIES
    DEBUG_POSTFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
add_test(
    NAME collision_rom_resolver_tests
    COMMAND collision_rom_resolver_tests
        "C:/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI"
)

