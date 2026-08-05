#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <process_name> <output_log_file.csv>"
    echo "Example: $0 rathole rathole_iran.csv"
    exit 1
fi

PROCESS_NAME="$1"
LOG_FILE="$2"

echo "Timestamp,CPU_Core_Count,Process_CPU_Pct,Process_RAM_MB,Process_RAM_Pct,System_CPU_Pct,System_RAM_Used_MB,System_RAM_Free_MB" > "$LOG_FILE"

echo "Monitoring process '$PROCESS_NAME' -> Saving logs to '$LOG_FILE'..."
echo "Press CTRL+C to stop logging."

while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CORE_COUNT=$(nproc)
    
    PID=$(pgrep -o -x "$PROCESS_NAME")
    
    if [ -n "$PID" ]; then
        PROC_STATS=$(ps -p "$PID" -o %cpu,%mem,rss --no-headers)
        PROC_CPU=$(echo "$PROC_STATS" | awk '{print $1}')
        PROC_MEM_PCT=$(echo "$PROC_STATS" | awk '{print $2}')
        PROC_RSS_KB=$(echo "$PROC_STATS" | awk '{print $3}')
        PROC_RAM_MB=$(echo "scale=2; $PROC_RSS_KB / 1024" | bc 2>/dev/null || echo "0")
    else
        PROC_CPU="0.0"
        PROC_MEM_PCT="0.0"
        PROC_RAM_MB="0.0"
    fi

    SYS_CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    MEM_INFO=$(free -m | grep Mem)
    SYS_RAM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    SYS_RAM_FREE=$(echo "$MEM_INFO" | awk '{print $4}')

    echo "$TIMESTAMP,$CORE_COUNT,$PROC_CPU,$PROC_RAM_MB,$PROC_MEM_PCT,$SYS_CPU,$SYS_RAM_USED,$SYS_RAM_FREE" >> "$LOG_FILE"
    
    sleep 1
done
