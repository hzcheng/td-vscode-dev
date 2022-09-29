#!/bin/bash

PROJ_HOME_DIR=$1
NODE_ID=$2

NODE_HOME_DIR="${PROJ_HOME_DIR}/sim/dnode${NODE_ID}"

echo ${NODE_HOME_DIR}

rm -rf ${NODE_HOME_DIR}/*
mkdir -p ${NODE_HOME_DIR}/cfg ${NODE_HOME_DIR}/data ${NODE_HOME_DIR}/log
touch ${NODE_HOME_DIR}/cfg/taos.cfg

echo "fqdn                   localhost" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "firstEp                localhost:6100" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "serverPort             6${NODE_ID}00" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "supportVnodes          128" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "dataDir                ${NODE_HOME_DIR}/data" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "logDir                 ${NODE_HOME_DIR}/log" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "debugFlag              131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "mDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "dDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "vDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "tsdbDebugFlag          131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "cDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "jniDebugFlag           131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "qDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "rpcDebugFlag           131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "tmrDebugFlag           131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "uDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "sDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "wDebugFlag             131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "tqDebugFlag            131" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "numOfLogLines          20000000" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "statusInterval         1" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "asyncLog               0" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "locale                 en_US.UTF-8" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "telemetryReporting     0" >>${NODE_HOME_DIR}/cfg/taos.cfg
echo "multiProcess           0" >>${NODE_HOME_DIR}/cfg/taos.cfg
