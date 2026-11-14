cmake_minimum_required(VERSION 3.21)
# C is needed for the wayland-scanner generated protocol tables (*-protocol.c).
project(ambxst-input LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Where the QML module is installed, relative to CMAKE_INSTALL_PREFIX. Must be
# on Quickshell's QML import path (the Nix launcher exports <env>/lib/qt-6/qml).
set(AMBXST_QML_DIR "lib/qt-6/qml" CACHE STRING "QML module install directory")

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml WaylandClient)
find_package(PkgConfig REQUIRED)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
if(NOT WAYLAND_PROTOCOLS_DIR)
    message(FATAL_ERROR "wayland-protocols not found (pkg-config)")
endif()

qt_policy(SET QTP0001 NEW)

qt_add_qml_module(ambxst-input
    URI Ambxst.Input
    VERSION 1.0
    PLUGIN_TARGET ambxst-input
    NO_PLUGIN_OPTIONAL
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Ambxst/Input"
    SOURCES
        relativepointer.h
        relativepointer.cpp
)

qt6_generate_wayland_protocol_client_sources(ambxst-input
    FILES "${WAYLAND_PROTOCOLS_DIR}/unstable/relative-pointer/relative-pointer-unstable-v1.xml"
)

target_link_libraries(ambxst-input PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::WaylandClient)

set(module_dir "${AMBXST_QML_DIR}/Ambxst/Input")
install(TARGETS ambxst-input LIBRARY DESTINATION "${module_dir}")
install(DIRECTORY "${CMAKE_BINARY_DIR}/qml/Ambxst/Input/"
    DESTINATION "${module_dir}"
    FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes"
)
