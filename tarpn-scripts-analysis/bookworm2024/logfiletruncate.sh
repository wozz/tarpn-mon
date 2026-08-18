#!/bin/bash
### TRUNCATE LOG FILES

###               bullseye 002 -- the log file passed into truncate_log_file() will already have a fully qualified path
### 2022-01-22 -- bullseye 003 -- write to the tarpn-service log when we actually do a truncate.
### 2022-02-09 -- bullseye 004 -- turn off debug prints to STDOUT for when we do NOT do a truncate.
### 2025-05-09 -- bookworm005 -- change the name of the tarpn-service.log alias to match the other script files.

#### =LOGFILETRUNCATE.SH        Bookworm005=" #  --VERSION--#########

TARPN_SERVICE_LOG="/var/log/tarpn_service.log"

truncate_log_file() {
__trim_log_file_size=10000000;
__trigger_log_file_size=15000000;
__log_file_length=$(wc -c $1 | cut -d' ' -f1);
##echo "__log_file_length="$__log_file_length;
##echo "logfiletruncate.sh: log file of interest="$1
ls -lrts $1
if [ $__log_file_length -gt $__trigger_log_file_size ];
then
   echo "logfiletruncate.sh: log file " $1 "is too long at " $__log_file_length
   echo -ne $(date) " " >> $TARPN_SERVICE_LOG
   echo "logfiletruncate.sh: log file " $1 "is too long at " $__log_file_length > $LOGFILE
   ls -lrts $1   > $TARPN_SERVICE_LOG
   sudo truncate -s $__trim_log_file_size $1
   ls -lrts $1   > $TARPN_SERVICE_LOG
else
   ##echo "logfiletruncate.sh: log file " $1 "is short enough already"
   ls -lrts $1
fi
}

