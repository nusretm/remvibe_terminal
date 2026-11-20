cmake_minimum_required(VERSION 3.20)
project(remvibe_terminal LANGUAGES CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "TERM-01A supports Windows x64 only")
endif()

add_library(remvibe_terminal_windows SHARED
    native/src/platform/windows/remvibe_terminal_windows.cpp)
target_compile_features(remvibe_terminal_windows PRIVATE cxx_std_17)
target_compile_definitions(remvibe_terminal_windows PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(remvibe_terminal_windows PUBLIC native/include)
target_link_libraries(remvibe_terminal_windows PRIVATE kernel32)
if(MSVC)
  target_compile_options(remvibe_terminal_windows PRIVATE /W4 /WX /EHsc)
endif()

option(RVTERM_BUILD_TESTS "Build Windows ConPTY integration tests" ON)
if(RVTERM_BUILD_TESTS)
  enable_testing()
  add_executable(remvibe_terminal_windows_test
      native/tests/platform/windows/remvibe_terminal_windows_test.cpp)
  target_compile_features(remvibe_terminal_windows_test PRIVATE cxx_std_17)
  target_link_libraries(remvibe_terminal_windows_test PRIVATE remvibe_terminal_windows)
  if(MSVC)
    target_compile_options(remvibe_terminal_windows_test PRIVATE /W4 /WX /EHsc)
  endif()
  add_test(NAME remvibe_terminal_windows_test
      COMMAND remvibe_terminal_windows_test)
  set_tests_properties(remvibe_terminal_windows_test PROPERTIES TIMEOUT 90)
endif()
