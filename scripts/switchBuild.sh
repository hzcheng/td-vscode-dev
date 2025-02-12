#!/bin/bash

PROJ_HOME_DIR=$1

if [ -z "$2" ]; then
    echo "Error: BUILD_TAG not specified"
    exit 1
fi
BUILD_TAG=$2

echo "Project home directory: ${PROJ_HOME_DIR}"
echo "Switching to build tag: ${BUILD_TAG}"

# Remove existing debug link if it exists
rm -f "${PROJ_HOME_DIR}/debug"

# Create build directory if it doesn't exist
mkdir -p "${PROJ_HOME_DIR}/build/${BUILD_TAG}"

# Create symbolic link from debug to build directory
ln -s "${PROJ_HOME_DIR}/build/${BUILD_TAG}" "${PROJ_HOME_DIR}/debug"