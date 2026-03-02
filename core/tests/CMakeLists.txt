cmake_minimum_required(VERSION 3.20)
project(term-tests LANGUAGES C)

set(CMAKE_C_STANDARD 11)

add_executable(core_api_test api_test.c)
add_test(NAME core_api_test COMMAND core_api_test)

target_include_directories(core_api_test PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src/internal
)

target_link_libraries(core_api_test PRIVATE
    openterm_core
    ${OPENTERM_LIBSSH_TARGET}
    OpenSSL::SSL
    OpenSSL::Crypto
    ZLIB::ZLIB
)

if(OPENTERM_GSS_FRAMEWORK)
    target_link_libraries(core_api_test PRIVATE ${OPENTERM_GSS_FRAMEWORK})
endif()

option(BUILD_INTEGRATION_TESTS "Build local integration tests that use an ephemeral sshd" OFF)

if(BUILD_INTEGRATION_TESTS)
    add_executable(core_integration_test integration_test.c)
    target_include_directories(core_integration_test PRIVATE
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(core_integration_test PRIVATE
        openterm_core
        ${OPENTERM_LIBSSH_TARGET}
        OpenSSL::SSL
        OpenSSL::Crypto
        ZLIB::ZLIB
    )

    if(OPENTERM_GSS_FRAMEWORK)
        target_link_libraries(core_integration_test PRIVATE ${OPENTERM_GSS_FRAMEWORK})
    endif()

    add_test(
        NAME core_integration_test
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run_integration_test.sh" "${CMAKE_BINARY_DIR}"
    )
endif()
