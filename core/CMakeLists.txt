cmake_minimum_required(VERSION 3.20)
project(openterm-core VERSION 0.1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(OPENTERM_APPLE_OPENSSL_ROOT "" CACHE PATH "Root directory of a prepared Apple OpenSSL artifact containing include/ and lib/")

# ============================================
# Resolve libssh from the vendored copy
# ============================================
set(OPENTERM_LIBSSH_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../vendor/libssh" CACHE PATH "Root directory of the vendored libssh installation")

find_path(OPENTERM_LIBSSH_INCLUDE_DIR
    NAMES libssh/libssh.h
    PATHS "${OPENTERM_LIBSSH_ROOT}/include"
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

if(EXISTS "${OPENTERM_LIBSSH_ROOT}/lib/libssh.dylib")
    set(OPENTERM_LIBSSH_LIBRARY "${OPENTERM_LIBSSH_ROOT}/lib/libssh.dylib")
elseif(EXISTS "${OPENTERM_LIBSSH_ROOT}/lib/libssh.a")
    set(OPENTERM_LIBSSH_LIBRARY "${OPENTERM_LIBSSH_ROOT}/lib/libssh.a")
else()
    find_library(OPENTERM_LIBSSH_LIBRARY
        NAMES libssh libssh.a
        PATHS "${OPENTERM_LIBSSH_ROOT}/lib"
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH
    )
endif()

if(NOT OPENTERM_LIBSSH_INCLUDE_DIR OR NOT OPENTERM_LIBSSH_LIBRARY)
    message(FATAL_ERROR "Vendored libssh not found at ${OPENTERM_LIBSSH_ROOT}. Update vendor/libssh before building.")
endif()

get_filename_component(OPENTERM_LIBSSH_EXT "${OPENTERM_LIBSSH_LIBRARY}" EXT)
if(OPENTERM_LIBSSH_EXT STREQUAL ".a")
    set(OPENTERM_LIBSSH_KIND STATIC)
else()
    set(OPENTERM_LIBSSH_KIND SHARED)
endif()

add_library(openterm_libssh ${OPENTERM_LIBSSH_KIND} IMPORTED)
set_target_properties(openterm_libssh PROPERTIES
    IMPORTED_LOCATION "${OPENTERM_LIBSSH_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${OPENTERM_LIBSSH_INCLUDE_DIR}"
)

set(OPENTERM_LIBSSH_TARGET openterm_libssh)
set(OPENTERM_LIBSSH_INCLUDE_DIRS "${OPENTERM_LIBSSH_INCLUDE_DIR}")

# ============================================
# Source files
# ============================================
set(SOURCES
    src/ssh_core.c
    src/ssh_connection.c
    src/ssh_auth.c
    src/ssh_sftp.c
    src/ssh_hostkey.c
)

set(HEADERS
    include/term_ssh.h
    src/internal/ssh_core.h
    src/internal/ssh_connection.h
    src/internal/ssh_auth.h
    src/internal/ssh_sftp.h
    src/internal/ssh_hostkey.h
)

# ============================================
# Create static library
# ============================================
add_library(openterm_core STATIC ${SOURCES} ${HEADERS})

target_include_directories(openterm_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
    ${OPENTERM_LIBSSH_INCLUDE_DIRS}
)

target_include_directories(openterm_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/internal
)

target_link_libraries(openterm_core PUBLIC
    ${OPENTERM_LIBSSH_TARGET}
)

target_compile_options(openterm_core PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-deprecated-declarations
)
# OpenSSL detection for libssh
if(APPLE AND OPENTERM_APPLE_OPENSSL_ROOT)
    find_path(OPENTERM_OPENSSL_INCLUDE_DIR
        NAMES openssl/ssl.h
        PATHS "${OPENTERM_APPLE_OPENSSL_ROOT}/include"
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH
    )

    find_library(OPENTERM_OPENSSL_SSL_LIBRARY
        NAMES ssl libssl.a
        PATHS "${OPENTERM_APPLE_OPENSSL_ROOT}/lib"
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH
    )

    find_library(OPENTERM_OPENSSL_CRYPTO_LIBRARY
        NAMES crypto libcrypto.a
        PATHS "${OPENTERM_APPLE_OPENSSL_ROOT}/lib"
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH
    )

    if(NOT OPENTERM_OPENSSL_INCLUDE_DIR OR NOT OPENTERM_OPENSSL_SSL_LIBRARY OR NOT OPENTERM_OPENSSL_CRYPTO_LIBRARY)
        message(FATAL_ERROR "Apple OpenSSL artifact not found at ${OPENTERM_APPLE_OPENSSL_ROOT}. Expected include/ and lib/ with libssl and libcrypto.")
    endif()

    if(NOT TARGET OpenSSL::SSL)
        add_library(OpenSSL::SSL UNKNOWN IMPORTED)
        set_target_properties(OpenSSL::SSL PROPERTIES
            IMPORTED_LOCATION "${OPENTERM_OPENSSL_SSL_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${OPENTERM_OPENSSL_INCLUDE_DIR}"
        )
    endif()

    if(NOT TARGET OpenSSL::Crypto)
        add_library(OpenSSL::Crypto UNKNOWN IMPORTED)
        set_target_properties(OpenSSL::Crypto PROPERTIES
            IMPORTED_LOCATION "${OPENTERM_OPENSSL_CRYPTO_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${OPENTERM_OPENSSL_INCLUDE_DIR}"
        )
    endif()
else()
    find_package(OpenSSL REQUIRED)
endif()

find_package(ZLIB REQUIRED)
find_library(OPENTERM_GSS_FRAMEWORK GSS)

target_link_libraries(openterm_core PUBLIC OpenSSL::SSL OpenSSL::Crypto ZLIB::ZLIB)

if(OPENTERM_GSS_FRAMEWORK)
    target_link_libraries(openterm_core PUBLIC ${OPENTERM_GSS_FRAMEWORK})
endif()

# ============================================
# Install targets
# ============================================
install(TARGETS openterm_core
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)

install(FILES include/term_ssh.h
    DESTINATION include/term
)

# ============================================
# Build example
# ============================================
option(BUILD_EXAMPLE "Build example application" ON)

if(BUILD_EXAMPLE)
    add_executable(openterm_cli ../tools/openterm_cli.c)
    
    target_include_directories(openterm_cli PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
    
    target_link_libraries(openterm_cli PRIVATE
        openterm_core
        ${OPENTERM_LIBSSH_TARGET}
        OpenSSL::SSL
        OpenSSL::Crypto
        ZLIB::ZLIB
    )

    if(OPENTERM_GSS_FRAMEWORK)
        target_link_libraries(openterm_cli PRIVATE ${OPENTERM_GSS_FRAMEWORK})
    endif()
endif()

# ============================================
# Tests
# ============================================
option(BUILD_TESTS "Build tests" OFF)

if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
