cmake_minimum_required(VERSION 3.13)
add_executable(${BINARY_NAME} main.cc "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc")
apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE APPLICATION_ID="${APPLICATION_ID}")
# Resolve LuaJIT's exception unwinding through libgcc before Flutter's bundled
# unwinder. The latter crashes libmpv's built-in Lua scripts on Linux.
target_link_libraries(${BINARY_NAME} PRIVATE
  "-Wl,--push-state,--no-as-needed" gcc_s "-Wl,--pop-state"
  flutter PkgConfig::GTK)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
