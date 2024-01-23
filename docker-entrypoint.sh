#!/bin/bash
set -e

if [[ -n "${LOG_PATH}" ]]; then
  /usr/local/bin/zabbix_exec_db_partitioning.sh >> $LOG_PATH 2>&1
else
  echo "LOG_PATH environment variable is missing. Exiting..."
  exit 1
fi