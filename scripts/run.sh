#!/bin/bash
set -x

search_pattern="Out of memory in queue"
count=0
max_loops=10
while [ $count -lt $max_loops ]; do
    count=$((count+1))
    echo "Loop count: $count" | tee -a /root/hzcheng/log/loop_count.log

    # Kill all taosd
    ssh u1-43 'pid=$(pidof taosd) && [ -n "$pid" ] && kill -9 $pid || true'
    ssh u1-54 'pid=$(pidof taosd) && [ -n "$pid" ] && kill -9 $pid || true'
    ssh u1-58 'pid=$(pidof taosd) && [ -n "$pid" ] && kill -9 $pid || true'

    # Remove old data
    ssh u1-43 'rm -rf /data1/mydata/* /data3/mydata/* /data4/mydata/*'
    ssh u1-54 'rm -rf /data1/mydata/* /data3/mydata/* /data4/mydata/*'
    ssh u1-58 'rm -rf /data1/mydata/* /data3/mydata/* /data4/mydata/*'

    # Remove old log
    ssh u1-43 'rm -rf /root/hzcheng/log/*'
    ssh u1-54 'rm -rf /root/hzcheng/log/*'
    ssh u1-58 'rm -rf /root/hzcheng/log/*'

    # Run taosd
    ssh u1-43 "tmux send-keys -t hzcheng:1.0 '/root/hzcheng/bin/taosd -c /root/hzcheng/cfg' C-m"
    ssh u1-54 "tmux send-keys -t hzcheng:1.0 '/root/hzcheng/bin/taosd -c /root/hzcheng/cfg' C-m"
    ssh u1-58 "tmux send-keys -t hzcheng:1.0 '/root/hzcheng/bin/taosd -c /root/hzcheng/cfg' C-m"

    sleep 2

    # Add dnode
    ssh u1-43 "LD_PRELOAD=/root/hzcheng/lib/libtaos.so /root/hzcheng/bin/taos -c /root/hzcheng/cfg -s 'create dnode \"u1-54:6030\"'"
    sleep 5

    ssh u1-43 "LD_PRELOAD=/root/hzcheng/lib/libtaos.so /root/hzcheng/bin/taos -c /root/hzcheng/cfg -s 'create dnode \"u1-58:6030\"'"
    sleep 5

    # Run taosBenchmark
    scp /root/workspace/TDinternal/sim/ins200w.json u1-43:/root/hzcheng/
    ssh u1-43 'cd /root/hzcheng/ && LD_PRELOAD=/root/hzcheng/lib/libtaos.so /root/hzcheng/bin/taosBenchmark -f ./ins200w.json' > >(tee /tmp/taosBenchmark.log) 2> >(tee /tmp/taosBenchmark.err >&2)
    if grep -q "${search_pattern}" /tmp/taosBenchmark.log || grep -q "${search_pattern}" /tmp/taosBenchmark.err; then
        echo "Found \"${search_pattern}\" in taosBenchmark output after $count loops" | tee -a /root/workspace/TDinternal/.vscode/benchmark_sync.log 

        # Kill all taosd
        ssh u1-54 'kill -9 $(pidof taosd)'
        ssh u1-58 'kill -9 $(pidof taosd)'
        break
    fi
    sleep 1  # Optional: wait before retrying

done
