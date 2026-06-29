cmake_minimum_required(VERSION 3.22)

project(AccessXI_PolPlugin LANGUAGES CXX)

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

