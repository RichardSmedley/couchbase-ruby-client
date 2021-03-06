cmake_minimum_required(VERSION 3.15)
project(ruby_client LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)

find_program(CCACHE ccache)
if(CCACHE)
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE})
endif()

add_subdirectory(third_party/gsl)
add_subdirectory(third_party/json)
add_subdirectory(third_party/spdlog)
add_subdirectory(third_party/snappy)

include_directories(BEFORE SYSTEM third_party/gsl/include)
include_directories(BEFORE SYSTEM third_party/asio/asio/include)
include_directories(BEFORE SYSTEM third_party/json/include)
include_directories(BEFORE SYSTEM third_party/spdlog/include)
include_directories(BEFORE SYSTEM third_party/http_parser)

add_library(project_warnings INTERFACE)
add_library(project_options INTERFACE)

target_compile_features(project_options INTERFACE cxx_std_17)
target_include_directories(project_options INTERFACE include)

if(MSVC)
    target_compile_options(project_warnings INTERFACE /W4 /WX "/permissive-")
else()
    option(ONLY_COVERAGE "Build only tests necessary for coverage" FALSE)
    option(STATIC_STDLIB "Statically link C++ standard library" FALSE)
    option(ENABLE_COVERAGE "Enable coverage reporting for gcc/clang" FALSE)
    option(ENABLE_FUZZERS "Enable fuzz testing tools" FALSE)

    if(ONLY_COVERAGE OR ENABLE_COVERAGE)
        target_compile_options(project_options INTERFACE --coverage -O0 -g)
        target_link_libraries(project_options INTERFACE --coverage)
    endif()

    option(ENABLE_ASAN "Enable address sanitizer" FALSE)

    if(ENABLE_ASAN)
        target_compile_options(project_options INTERFACE -fsanitize=address)
        target_link_libraries(project_options INTERFACE -fsanitize=address)
    endif()

    option(ENABLE_TSAN "Enable thread sanitizer" FALSE)

    if(ENABLE_TSAN)
        target_compile_options(project_options INTERFACE -fsanitize=thread)
        target_link_libraries(project_options INTERFACE -fsanitize=thread)
    endif()

    if(STATIC_STDLIB)
        target_compile_options(project_options INTERFACE -static-libgcc -static-libstdc++)
        target_link_options(project_options INTERFACE -static-libgcc -static-libstdc++)
    endif()

    target_compile_options(
        project_warnings
        INTERFACE -Wall
                  -Werror # treat all warnings as errors
                  -Wextra # reasonable and standard
                  -Wshadow # warn the user if a variable declaration shadows one from a parent
                  # context
                  -Wnon-virtual-dtor # warn the user if a class with virtual functions has a non-
                  # virtual destructor. This helps catch hard to track down memory errors
                  -Wcast-align # warn for potential performance problem casts
                  -Wunused # warn on anything being unused
                  -Woverloaded-virtual # warn if you overload (not override) a virtual function
                  -Wpedantic # warn if non-standard C++ is used
                  -Wold-style-cast # warn for c-style casts
                  -Wconversion # warn on type conversions that may lose data
                  -Wsign-conversion # warn on sign conversions
                  -Wnull-dereference # warn if a null dereference is detected
                  -Wformat=2 # warn on security issues around functions that format output (ie
                  # printf)
    )

    if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
        target_compile_options(
            project_warnings
            INTERFACE -Wmisleading-indentation # warn if indentation implies blocks where blocks do
                      # not exist
                      -Wduplicated-cond # warn if if / else chain has duplicated conditions
                      -Wduplicated-branches # warn if if / else branches have duplicated code
                      -Wlogical-op # warn about logical operations being used where bitwise were
                      # probably wanted
                      -Wuseless-cast # warn if you perform a cast to the same type
        )
    endif()
endif()

# Read more at https://wiki.wireshark.org/TLS
option(TLS_KEY_LOG_FILE "Path to file to write per-session secrets (Useful for Wireshark SSL/TLS dissection)")

include(FindOpenSSL)
message(STATUS "OPENSSL_VERSION: ${OPENSSL_VERSION}")
message(STATUS "OPENSSL_INCLUDEDIRS: ${OPENSSL_INCLUDE_DIR}")
message(STATUS "OPENSSL_LIBRARIES: ${OPENSSL_LIBRARIES}")

include_directories(${CMAKE_SOURCE_DIR}/couchbase)

add_library(platform OBJECT couchbase/platform/string_hex.cc couchbase/platform/uuid.cc couchbase/platform/random.cc
                            couchbase/platform/base64.cc)

add_library(cbcrypto OBJECT couchbase/cbcrypto/cbcrypto.cc)

add_library(http_parser OBJECT third_party/http_parser/http_parser.c)
set_target_properties(http_parser PROPERTIES C_VISIBILITY_PRESET hidden POSITION_INDEPENDENT_CODE TRUE)

add_library(
    cbsasl OBJECT
    couchbase/cbsasl/client.cc couchbase/cbsasl/context.cc couchbase/cbsasl/mechanism.cc
    couchbase/cbsasl/plain/plain.cc couchbase/cbsasl/scram-sha/scram-sha.cc couchbase/cbsasl/scram-sha/stringutils.cc)

if(RUBY_HDR_DIR)
    set(RUBY_INCLUDE_DIR ${RUBY_HDR_DIR} ${RUBY_ARCH_HDR_DIR})
else()
    find_package(Ruby REQUIRED)
    message(STATUS "RUBY_VERSION: ${RUBY_VERSION}")
    message(STATUS "RUBY_EXECUTABLE: ${RUBY_EXECUTABLE}")
endif()
message(STATUS "RUBY_INCLUDE_DIR: ${RUBY_INCLUDE_DIR}")
message(STATUS "RUBY_LIBRARY: ${RUBY_LIBRARY}")
include_directories(BEFORE SYSTEM "${RUBY_INCLUDE_DIR}")

find_program(GIT git)
if(GIT)
    execute_process(
        COMMAND git rev-parse HEAD
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        OUTPUT_STRIP_TRAILING_WHITESPACE
        OUTPUT_VARIABLE BACKEND_GIT_REVISION)
endif()

string(TIMESTAMP BACKEND_BUILD_TIMESTAMP "%Y-%m-%d %H:%M:%S" UTC)
configure_file(${PROJECT_SOURCE_DIR}/build_version.hxx.in ${PROJECT_BINARY_DIR}/generated/build_version.hxx @ONLY)
configure_file(${PROJECT_SOURCE_DIR}/build_config.hxx.in ${PROJECT_BINARY_DIR}/generated/build_config.hxx @ONLY)
add_library(couchbase SHARED couchbase/couchbase.cxx)
target_include_directories(couchbase PRIVATE ${PROJECT_BINARY_DIR}/generated)
target_link_libraries(
    couchbase
    PRIVATE project_options
            project_warnings
            OpenSSL::SSL
            OpenSSL::Crypto
            platform
            cbcrypto
            cbsasl
            http_parser
            snappy
            spdlog::spdlog_header_only)
set_target_properties(cbcrypto cbsasl platform snappy PROPERTIES POSITION_INDEPENDENT_CODE TRUE)

if(APPLE)
    target_link_options(couchbase PRIVATE -Wl,-undefined,dynamic_lookup)
else()
    set_target_properties(cbcrypto cbsasl platform PROPERTIES CXX_VISIBILITY_PRESET hidden)
endif()

if(BUILD_EXAMPLES)
    file(
        GENERATE
        OUTPUT ${PROJECT_BINARY_DIR}/generated/generated_config.hxx
        CONTENT "#pragma once\n#define LIBCOUCHBASE_EXT_PATH \"$<TARGET_FILE:couchbase>\"")
    add_executable(main test/main.cxx)
    target_include_directories(main PRIVATE ${PROJECT_BINARY_DIR}/generated)
    target_link_libraries(main PRIVATE project_options project_warnings ${RUBY_LIBRARY} spdlog::spdlog_header_only)
    add_dependencies(main couchbase)
endif()
