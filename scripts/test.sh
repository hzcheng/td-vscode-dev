#!/bin/bash
#
# TDengine Cluster Management Script
# Description: Automated script for building, deploying, and testing TDengine clusters
# Usage: ./test.sh
# Author: TDengine Team
#

set -e # Exit on any error

# =============================================================================
# Configuration Variables
# =============================================================================
readonly SERVERS=("u1-43" "u1-54" "u1-58")
readonly PORT=8030
readonly BUILD_DIR="build"
readonly LOCAL_SOURCE="/mnt/workspace/TDinternal"
readonly MOUNT_SOURCE="/root/workspace/TDinternal"
readonly REMOTE_BASE_DIR="/root/hzcheng"
readonly DOCKER_IMAGE="ghcr.io/hzcheng/toolkit/centos:7.x86_64"
readonly BUILD_TYPE="Release" # Change to Debug if needed
readonly BUILD_SANITIZER=0    # Enable AddressSanitizer and UndefinedBehaviorSanitizer

# Color output for better readability
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# =============================================================================
# Build TDengine binaries using Docker
# =============================================================================
build_tdengine() {
    log_step "Building TDengine binaries..."

    local build_dir="$BUILD_DIR"
    local binaries=("taosd" "taos" "taosBenchmark")
    local libraries=("libtaos.so" "libtaosnative.so" "libasan.so.5.0.0" "libubsan.so.1.0.0")

    # Build TDengine in Docker container
    log_info "Compiling TDengine in Docker container..."
    docker run \
        -it --rm \
        -v "${LOCAL_SOURCE}:${MOUNT_SOURCE}" \
        "$DOCKER_IMAGE" \
        bash -c "
            cd ${MOUNT_SOURCE} 
            rm -rf .externals
            rm -rf ${build_dir}
            mkdir ${build_dir}
            cd ${build_dir}
            cmake .. \
                -DCMAKE_BUILD_TYPE=${BUILD_TYPE}\
                -DASSERT_NOT_CORE=true \
                -DCPUTYPE=x64 \
                -DOSTYPE=Linux \
                -DSOMODE=dynamic \
                -DDBNAME=taos \
                -DVERTYPE=stable \
                -DBUILD_SANITIZER=${BUILD_SANITIZER} \
                -DJEMALLOC_ENABLED=false\
                -DBUILD_WITH_UDF=OFF \
                -DBUILD_S3=false \
                -DBUILD_TOOLS=true
            make -j\$(nproc) taosBenchmark taosd taos shell taosnative
            cp /usr/local/gcc-9.3.0/lib64/libasan.so.5.0.0 build/lib
            cp /usr/local/gcc-9.3.0/lib64/libubsan.so.1.0.0 build/lib
        "

    # Upload binaries to remote servers
    for server in "${SERVERS[@]}"; do
        log_info "Uploading binaries to ${server}..."

        # Prepare remote directories
        ssh "${server}" "
            cd ${REMOTE_BASE_DIR}/
            rm -rf bin lib build
            mkdir -p build/bin build/lib
        "

        # Copy binaries
        for binary in "${binaries[@]}"; do
            scp "/root/workspace/TDinternal/${build_dir}/build/bin/${binary}" \
                "${server}:${REMOTE_BASE_DIR}/build/bin/"
        done

        # Copy libraries
        for library in "${libraries[@]}"; do
            scp "/root/workspace/TDinternal/${build_dir}/build/lib/${library}" \
                "${server}:${REMOTE_BASE_DIR}/build/lib/"
        done
    done

    log_info "TDengine build and upload completed successfully"
}

# =============================================================================
# Generate TDengine configuration file
# =============================================================================
generate_taos_config() {
    local server="$1"
    local port="$2"

    # Generate base configuration
    cat <<EOF
firstEp                     u1-43:${port}
fqdn                        ${server}
serverPort                  ${port}
dataDir                     /data1/mydata 0 1
dataDir                     /data3/mydata 0 0
dataDir                     /data4/mydata 0 0
logDir                      ${REMOTE_BASE_DIR}/dnode/log
tmpDir                      /data4/taos_tmp
SupportVnodes               128
numofCommitThreads          32
timezone                    UTC-8
locale                      en_US.UTF-8
charset                     UTF-8
logKeepDays                 -3
shellActivityTimer          120
numOfRpcSessions            30000
monitor                     0
monitorFQDN                 u1-43
audit                       0
compressMsgSize             -1
slowLogScope                ALL
slowLogThreshold            10
slowLogMaxLen               4096
forceReadConfig             1
bypassFlag                  0
maxRetryWaitTime            10000
ratioOfVnodeStreamThreads   1
# numOfRpcThreads           100
shareConnLimit              2
syncLogHeartbeat            1
numOfLogLines               200000000
EOF
}

# =============================================================================
# Setup and start TDengine cluster
# =============================================================================
build_tdengine_cluster() {
    log_step "Setting up TDengine cluster..."

    local port="$PORT"

    # Setup configuration on each server
    for server in "${SERVERS[@]}"; do
        log_info "Configuring TDengine on ${server}..."

        ssh "$server" "
            # Stop existing services
            service taosd stop 2>/dev/null || true
            killall -9 taosd 2>/dev/null || true

            # Prepare directories
            cd ${REMOTE_BASE_DIR}/
            rm -rf log dnode
            mkdir -p dnode/cfg dnode/log
        "

        # Generate and upload configuration
        generate_taos_config "$server" "$port" | ssh "$server" "cat > ${REMOTE_BASE_DIR}/dnode/cfg/taos.cfg"
    done

    # Start TDengine on each server
    for server in "${SERVERS[@]}"; do
        log_info "Starting TDengine on ${server}..."

        ssh "$server" "
            # Setup tmux sessions
            tmux kill-session -t 'hzcheng' 2>/dev/null || true
            tmux new-session -d -s 'hzcheng' -n 'taosd_run'
            tmux new-window -t 'hzcheng' -n 'taosBenchmark_run'
            tmux new-window -t 'hzcheng' -n 'taos_shell_run'

            # Clean data directories
            for dir in /data1/mydata /data3/mydata /data4/mydata; do
                rm -rf \$dir/* 2>/dev/null || true
            done
        "

        # Start TDengine daemon
        local PRE_LOADS=""
        if [[ "${BUILD_SANITIZER}" -eq 1 ]]; then
            PRE_LOADS="${REMOTE_BASE_DIR}/build/lib/libasan.so.5.0.0:${REMOTE_BASE_DIR}/build/lib/libubsan.so.1.0.0"
        else
            PRE_LOADS="/usr/lib/x86_64-linux-gnu/libtcmalloc.so"
        fi
        local PRE_LOADS="${REMOTE_BASE_DIR}/build/lib/libasan.so.5.0.0:${REMOTE_BASE_DIR}/build/lib/libubsan.so.1.0.0"
        ssh "$server" "
            tmux send-keys -t hzcheng:taosd_run 'cd ${REMOTE_BASE_DIR}/ && LD_PRELOAD=${PRE_LOADS} ./build/bin/taosd -c ${REMOTE_BASE_DIR}/dnode/cfg/taos.cfg' C-m
        "
    done

    local PRE_LOADS=""
    if [[ "${BUILD_SANITIZER}" -eq 1 ]]; then
        PRE_LOADS="${REMOTE_BASE_DIR}/build/lib/libasan.so.5.0.0:${REMOTE_BASE_DIR}/build/lib/libubsan.so.1.0.0"
    else
        PRE_LOADS="/usr/lib/x86_64-linux-gnu/libtcmalloc.so"
    fi
    PRE_LOADS="${PRE_LOADS}:${REMOTE_BASE_DIR}/build/lib/libtaos.so:${REMOTE_BASE_DIR}/build/lib/libtaosnative.so"
    # Configure cluster on primary node
    log_info "Configuring cluster on primary node..."
    ssh "u1-43" "
        sleep 5  # Wait for primary node to be ready
        
        # Add secondary nodes to cluster
        LD_PRELOAD=${PRE_LOADS} \
        ${REMOTE_BASE_DIR}/build/bin/taos -c ${REMOTE_BASE_DIR}/dnode/cfg/taos.cfg \
        -s 'create dnode \"u1-54:${port}\"'
        
        sleep 5

        LD_PRELOAD=${PRE_LOADS} \
        ${REMOTE_BASE_DIR}/build/bin/taos -c ${REMOTE_BASE_DIR}/dnode/cfg/taos.cfg \
        -s 'create dnode \"u1-58:${port}\"'
        
        sleep 5
    "

    log_info "TDengine cluster setup completed"
}

# =============================================================================
# Generate taosBenchmark configuration
# =============================================================================
generate_benchmark_config() {
    cat <<'EOF'
{
    "filetype": "insert",
    "cfgdir": "/root/hzcheng/dnode/cfg",
    "host": "localhost",
    "port": 8030,
    "user": "root",
    "password": "taosdata",
    "connection_pool_size": 100,
    "thread_count": 100,
    "thread_bind_vgroup": "yes",
    "continue_if_fail": "no",
    "create_table_thread_count": 16,
    "result_file": "./res.txt",
    "confirm_parameter_prompt": "no",
    "num_of_records_per_req": 5000,
    "prepared_rand": 10000,
    "chinese": "no",
    "databases": [
        {
            "dbinfo": {
                "name": "benchmark",
                "drop": "yes",
                "replica": 3,
                "wal_level": 1,
                "wal_retention_period": 3600,
                "buffer": 1400,
                "minrows": 20,
                "cachemodel": "none",
                "cachesize": 30,
                "stt_trigger": 3,
                "vgroups ": 100
            },
            "super_tables": [
                {
                    "name": "meters",
                    "child_table_exists": "no",
                    "childtable_count": 2000000,
                    "childtable_prefix": "d",
                    "escape_character": "yes",
                    "auto_create_table": "no",
                    "batch_create_tbl_num": 1000,
                    "data_source": "rand",
                    "insert_mode": "stmt2",
                    "non_stop_mode": "no",
                    "insert_rows": 100,
                    "childtable_limit": 0,
                    "childtable_offset": 0,
                    "interlace_rows": 1,
                    "insert_interval": 0,
                    "partial_col_num": 0,
                    "disorder_ratio": 0,
                    "disorder_range": 0,
                    "timestamp_step": 1000,
                    "start_timestamp": "now",
                    "sample_format": "csv",
                    "sample_file": "./sample.csv",
                    "use_sample_ts": "no",
                    "tags_file": "",
                    "columns": [
                        {
                            "type": "float",
                            "count": 150,
                            "max": 100,
                            "min": 0
                        }
                    ],
                    "tags": [
                        {
                            "type": "varchar",
                            "name": "location",
                            "max": 64,
                            "min": 1,
                            "values": [
                                "San Francisco",
                                "Los Angles",
                                "San Diego",
                                "San Jose",
                                "Palo Alto",
                                "Campbell",
                                "Mountain View",
                                "Sunnyvale",
                                "Santa Clara",
                                "Cupertino"
                            ]
                        },
                        {
                            "name": "groupId",
                            "type": "int",
                            "max": 100000,
                            "min": 1
                        }
                    ]
                }
            ]
        }
    ]
}
EOF
}

# =============================================================================
# Run TDengine benchmark
# =============================================================================
run_taosBenchmark() {
    log_step "Running TDengine benchmark..."

    local server="u1-43"
    local config_file="/tmp/benchmark_config.json"

    # Generate benchmark configuration locally
    log_info "Generating benchmark configuration..."
    generate_benchmark_config >"$config_file"

    # Copy configuration to remote server
    log_info "Uploading benchmark configuration to ${server}..."
    scp "$config_file" "${server}:${REMOTE_BASE_DIR}/test.json"

    local PRE_LOADS=""
    if [[ "${BUILD_SANITIZER}" -eq 1 ]]; then
        PRE_LOADS="${REMOTE_BASE_DIR}/build/lib/libasan.so.5.0.0:${REMOTE_BASE_DIR}/build/lib/libubsan.so.1.0.0"
    else
        PRE_LOADS="/usr/lib/x86_64-linux-gnu/libtcmalloc.so"
    fi
    PRE_LOADS="${PRE_LOADS}:${REMOTE_BASE_DIR}/build/lib/libtaos.so:${REMOTE_BASE_DIR}/build/lib/libtaosnative.so"

    # Run benchmark on remote server
    log_info "Executing benchmark on ${server}..."
    ssh "$server" "
        cd ${REMOTE_BASE_DIR}
        LD_PRELOAD=${PRE_LOADS} ./build/bin/taosBenchmark -f ./test.json
    "

    log_info "Benchmark execution completed"
}

# =============================================================================
# Main execution flow
# =============================================================================
main() {
    log_info "Starting TDengine cluster management script..."

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        --build)
            BUILD_ONLY=true
            shift
            ;;
        --cluster)
            CLUSTER_ONLY=true
            shift
            ;;
        --benchmark)
            BENCHMARK_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        esac
    done

    # Execute based on arguments
    if [[ "${BUILD_ONLY:-false}" == "true" ]]; then
        build_tdengine
    elif [[ "${CLUSTER_ONLY:-false}" == "true" ]]; then
        build_tdengine_cluster
    elif [[ "${BENCHMARK_ONLY:-false}" == "true" ]]; then
        run_taosBenchmark
    else
        # Default: run all steps
        # build_tdengine        # Uncomment to build binaries
        build_tdengine_cluster # Setup and start cluster
        run_taosBenchmark      # Run benchmark
    fi

    log_info "Script execution completed successfully!"
}

# =============================================================================
# Help function
# =============================================================================
show_help() {
    cat <<EOF
TDengine Cluster Management Script

Usage: $0 [OPTIONS]

Options:
    --build      Build TDengine binaries only
    --cluster    Setup TDengine cluster only
    --benchmark  Run benchmark only
    --help       Show this help message

Examples:
    $0                # Run cluster setup and benchmark
    $0 --build        # Build binaries only
    $0 --cluster      # Setup cluster only
    $0 --benchmark    # Run benchmark only

Configuration:
    Servers: ${SERVERS[*]}
    Port: $PORT
    Remote directory: $REMOTE_BASE_DIR
EOF
}

# =============================================================================
# Script execution
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# =============================================================================
# Optional: Interactive shell connection
# =============================================================================
# Uncomment the following line to connect to TDengine shell after execution:
# LD_PRELOAD="$REMOTE_BASE_DIR/build/lib/libtaos.so:$REMOTE_BASE_DIR/build/lib/libtaosnative.so" \
# $REMOTE_BASE_DIR/build/bin/taos -c $REMOTE_BASE_DIR/dnode/cfg/taos.cfg
