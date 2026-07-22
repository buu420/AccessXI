cmake_minimum_required(VERSION 3.22)

project(AccessXI_PolPlugin LANGUAGES CXX)

enable_testing()

add_library(accessxi_pol_nvda SHARED
    src/accessxi_pol.cpp
    src/accessxi_pol.def
)

target_compile_features(accessxi_pol_nvda PRIVATE cxx_std_20)
target_compile_definitions(accessxi_pol_nvda PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

if(NOT DEFINED ENV{ASHITA4_SDK_PATH})
    message(FATAL_ERROR "ASHITA4_SDK_PATH must point to Ashita v4 plugins/sdk, for example C:/Users/buu42/Ashita/plugins/sdk")
endif()

target_include_directories(accessxi_pol_nvda PRIVATE
    "$ENV{ASHITA4_SDK_PATH}"
)

target_link_libraries(accessxi_pol_nvda PRIVATE
    oleacc
    oleaut32
)

set_target_properties(accessxi_pol_nvda PROPERTIES
    OUTPUT_NAME "accessxi_pol_nvda"
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

