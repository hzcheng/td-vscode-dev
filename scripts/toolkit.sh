#!/bin/bash
#
# A toolkit script helping with TDengine build operations and some common tasks like tmux session management.
# Usages:
#   ./toolkit.sh <object> <command> [args...]
#
# Examples:
#   TDengine build:
#       ./toolkit.sh tdengine build [--build-type Release|Debug] [--build-sanitizer <sanitizer>] [--externals <path>] [--docker-image <image>] [--build-dir <path>] [--local-source <path>] [--mount-source <path>] [--rebuild-externals true|false]
#
#   TDengine setup:
#       ./toolkit.sh tdengine setup [--num] [--bin-dir <path>] [--lib_dir <path>]
#
#   TMUX session management:
#      ./toolkit.sh tmux new

set -e

# =============================================================================
# Global variables
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/debug"
COMMUNITY_DIR="${PROJECT_ROOT}/community"
SIM_DIR="${PROJECT_ROOT}/sim"

# Default values
BUILD_TYPE="Debug"
BUILD_SANITIZER=""
EXTERNALS_PATH=""
DOCKER_IMAGE=""
LOCAL_SOURCE=""
MOUNT_SOURCE=""
REBUILD_EXTERNALS="false"
NUM_NODES=1
BIN_DIR="${BUILD_DIR}/build/bin"
LIB_DIR="${BUILD_DIR}/build/lib"

# =============================================================================
# Utility functions
# =============================================================================
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# =============================================================================
# TDengine build functions
# =============================================================================
tdengine_clean() {
    log_info "Cleaning build directory..."
    if [[ -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"/*
        log_info "Build directory cleaned"
    else
        log_warn "Build directory does not exist"
    fi
}

tdengine_configure() {
    log_info "Configuring TDengine build..."
    
    # Create build directory if it doesn't exist
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    
    # Prepare cmake arguments
    CMAKE_ARGS=(
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"
        "-DBUILD_TOOLS=TRUE"
        "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
    )
    
    if [[ -n "${BUILD_SANITIZER}" ]]; then
        CMAKE_ARGS+=("-DBUILD_SANITIZER=1")
        log_info "Building with sanitizer: ${BUILD_SANITIZER}"
    fi
    
    if [[ -n "${EXTERNALS_PATH}" ]]; then
        CMAKE_ARGS+=("-DEXTERNALS_PATH=${EXTERNALS_PATH}")
        log_info "Using externals path: ${EXTERNALS_PATH}"
    fi
    
    CMAKE_ARGS+=("${PROJECT_ROOT}")
    
    log_info "Running cmake with args: ${CMAKE_ARGS[*]}"
    cmake "${CMAKE_ARGS[@]}"
    
    log_info "Configuration completed"
}

tdengine_build() {
    log_info "Building TDengine..."
    
    if [[ ! -f "${BUILD_DIR}/Makefile" ]]; then
        log_warn "Build not configured, running configuration first..."
        tdengine_configure
    fi
    
    cd "${BUILD_DIR}"
    
    # Determine number of parallel jobs
    if command -v nproc &> /dev/null; then
        JOBS=$(nproc)
    else
        JOBS=4
    fi
    
    log_info "Building with ${JOBS} parallel jobs..."
    make -j"${JOBS}"
    
    log_info "Build completed successfully"
}

tdengine_install() {
    log_info "Installing TDengine..."
    
    if [[ ! -f "${BUILD_DIR}/Makefile" ]]; then
        log_error "Build not configured. Please run build first."
        exit 1
    fi
    
    cd "${BUILD_DIR}"
    make install
    
    log_info "Installation completed"
}

tdengine_rebuild() {
    log_info "Rebuilding TDengine from scratch..."
    tdengine_clean
    tdengine_configure
    tdengine_build
    tdengine_install
}

# =============================================================================
# TDengine setup functions
# =============================================================================
tdengine_setup() {
    log_info "Setting up TDengine environment..."
    
    # Parse arguments
    local num_nodes=${NUM_NODES}
    local bin_dir=${BIN_DIR}
    local lib_dir=${LIB_DIR}
    
    # Validate directories
    if [[ ! -d "${bin_dir}" ]]; then
        log_error "Binary directory does not exist: ${bin_dir}"
        log_error "Please build TDengine first"
        exit 1
    fi
    
    if [[ ! -d "${lib_dir}" ]]; then
        log_error "Library directory does not exist: ${lib_dir}"
        log_error "Please build TDengine first"
        exit 1
    fi
    
    # Setup nodes
    for ((i=1; i<=num_nodes; i++)); do
        log_info "Setting up node ${i}..."
        bash "${SCRIPT_DIR}/setEnv.sh" "${PROJECT_ROOT}" "${i}"
    done
    
    log_info "TDengine setup completed for ${num_nodes} node(s)"
    log_info "Binary directory: ${bin_dir}"
    log_info "Library directory: ${lib_dir}"
}

# =============================================================================
# TMUX functions
# =============================================================================
tmux_new_session() {
    check_command tmux
    
    local session_name="tdengine-dev"
    
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        log_warn "Session '${session_name}' already exists"
        tmux attach-session -t "${session_name}"
    else
        log_info "Creating new tmux session: ${session_name}"
        tmux new-session -d -s "${session_name}" -c "${PROJECT_ROOT}"
        
        # Create windows
        tmux rename-window -t "${session_name}:0" "main"
        tmux new-window -t "${session_name}" -n "build" -c "${BUILD_DIR}"
        tmux new-window -t "${session_name}" -n "run" -c "${PROJECT_ROOT}"
        tmux new-window -t "${session_name}" -n "test" -c "${PROJECT_ROOT}/tests"
        
        # Select main window
        tmux select-window -t "${session_name}:main"
        
        # Attach to session
        tmux attach-session -t "${session_name}"
    fi
}

tmux_kill_session() {
    check_command tmux
    
    local session_name="tdengine-dev"
    
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        log_info "Killing tmux session: ${session_name}"
        tmux kill-session -t "${session_name}"
    else
        log_warn "Session '${session_name}' does not exist"
    fi
}

tmux_list_sessions() {
    check_command tmux
    
    log_info "Active tmux sessions:"
    tmux list-sessions 2>/dev/null || log_info "No active sessions"
}

# =============================================================================
# Help function
# =============================================================================
show_help() {
    cat << EOF
TDengine Toolkit Script

USAGE:
    ./toolkit.sh <object> <command> [options...]

OBJECTS AND COMMANDS:

    tdengine:
        build       - Build TDengine
        clean       - Clean build directory
        configure   - Configure build system
        install     - Install TDengine
        rebuild     - Clean, configure, build and install
        setup       - Setup TDengine environment

    tmux:
        new         - Create new development session
        kill        - Kill development session
        list        - List active sessions

OPTIONS:

    TDengine build options:
        --build-type <type>           Build type (Release|Debug) [default: Debug]
        --build-sanitizer <sanitizer> Enable sanitizer build
        --externals <path>            Path to externals directory
        --docker-image <image>        Docker image for build
        --build-dir <path>            Build directory [default: debug]
        --local-source <path>         Local source directory
        --mount-source <path>         Mount source directory
        --rebuild-externals <bool>    Rebuild externals (true|false)

    TDengine setup options:
        --num <number>                Number of nodes to setup [default: 1]
        --bin-dir <path>              Binary directory [default: debug/build/bin]
        --lib-dir <path>              Library directory [default: debug/build/lib]

EXAMPLES:

    # Build TDengine in Debug mode
    ./toolkit.sh tdengine build

    # Build TDengine in Release mode with sanitizer
    ./toolkit.sh tdengine build --build-type Release --build-sanitizer address

    # Setup 3 node environment
    ./toolkit.sh tdengine setup --num 3

    # Create new tmux development session
    ./toolkit.sh tmux new

    # Clean and rebuild everything
    ./toolkit.sh tdengine rebuild

EOF
}

# =============================================================================
# Argument parsing
# =============================================================================
parse_tdengine_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-type)
                BUILD_TYPE="$2"
                shift 2
                ;;
            --build-sanitizer)
                BUILD_SANITIZER="$2"
                shift 2
                ;;
            --externals)
                EXTERNALS_PATH="$2"
                shift 2
                ;;
            --docker-image)
                DOCKER_IMAGE="$2"
                shift 2
                ;;
            --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --local-source)
                LOCAL_SOURCE="$2"
                shift 2
                ;;
            --mount-source)
                MOUNT_SOURCE="$2"
                shift 2
                ;;
            --rebuild-externals)
                REBUILD_EXTERNALS="$2"
                shift 2
                ;;
            --num)
                NUM_NODES="$2"
                shift 2
                ;;
            --bin-dir)
                BIN_DIR="$2"
                shift 2
                ;;
            --lib-dir)
                LIB_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

print_tdengine_config() {
    local configs=(
        "BUILD_TYPE"
        "BUILD_SANITIZER"
        "EXTERNALS_PATH"
        "DOCKER_IMAGE"
        "BUILD_DIR"
        "LOCAL_SOURCE"
        "MOUNT_SOURCE"
        "REBUILD_EXTERNALS"
        "NUM_NODES"
        "BIN_DIR"
        "LIB_DIR"
    )
    log_info "TDengine build configuration:"
    for key in "${configs[@]}"; do
        log_info "  ${key}: ${!key}"
    done
}

# =============================================================================
# Main function
# =============================================================================
main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    local object="$1"
    
    # Handle help as special case
    if [[ "${object}" == "help" || "${object}" == "--help" || "${object}" == "-h" ]]; then
        show_help
        exit 0
    fi
    
    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi
    
    local command="$2"
    shift 2
    
    case "${object}" in
        tdengine)
            parse_tdengine_args "$@"
            print_tdengine_config
            case "${command}" in
                build)
                    tdengine_build
                    ;;
                clean)
                    tdengine_clean
                    ;;
                configure)
                    tdengine_configure
                    ;;
                install)
                    tdengine_install
                    ;;
                rebuild)
                    tdengine_rebuild
                    ;;
                setup)
                    tdengine_setup
                    ;;
                *)
                    log_error "Unknown tdengine command: ${command}"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        tmux)
            case "${command}" in
                new)
                    tmux_new_session
                    ;;
                kill)
                    tmux_kill_session
                    ;;
                list)
                    tmux_list_sessions
                    ;;
                *)
                    log_error "Unknown tmux command: ${command}"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown object: ${object}"
            show_help
            exit 1
            ;;
    esac
}

# =============================================================================
# Script execution
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi