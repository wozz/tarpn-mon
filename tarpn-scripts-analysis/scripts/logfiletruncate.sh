#!/bin/bash
### TRUNCATE LOG FILES

###               bullseye 002 -- the log file passed into truncate_log_file() will already have a fully qualified path
### 2022-01-22 -- bullseye 003 -- write to the tarpn-service log when we actually do a truncate.
### 2022-02-09 -- bullseye 004 -- turn off debug prints to STDOUT for when we do NOT do a truncate.
### 2025-11-21 -- Bullseye 005 -- Fix a bug where the truncate was off the bottom, instead of off the top.  Add prints to the top and bottom of the remaining region.


#### =logfiletruncate           Bullseye004 = #--VERSION--
LOGFILE="/var/log/tarpn_service.log"

#### truncate_log_file() {
#### __trim_log_file_size=100000000;
#### __trigger_log_file_size=150000000;
#### __log_file_length=$(wc -c $1 | cut -d' ' -f1);
#### ##echo "__log_file_length="$__log_file_length;
#### ##echo "logfiletruncate.sh: log file of interest="$1
#### ls -lrts $1
#### if [ $__log_file_length -gt $__trigger_log_file_size ];
#### then
####    echo "logfiletruncate.sh: log file " $1 "is too long at " $__trigger_log_file_size
####    echo -ne $(date) " " >> $LOGFILE
####    echo "logfiletruncate.sh: log file " $1 "is too long at " $__log_file_length >> $LOGFILE
####    ls -lrts $1   >> $LOGFILE
####    sudo truncate -s $__trim_log_file_size $1
####    ls -lrts $1   >> $LOGFILE
#### else
####    ##echo "logfiletruncate.sh: log file " $1 "is short enough already"
####    ls -lrts $1
#### fi
#### }


truncate_log_file() {
if [ -f $1 ];
then
    __trim_log_file_size=30000000
    __trigger_log_file_size=40000000
    __log_file_length=$(wc -c $1 | cut -d' ' -f1);
    #echo "__log_file_length=" $__log_file_length;
    #echo "__trigger_log_file_size" $__trigger_log_file_size
    #echo "logfiletruncate.sh: log file of interest="$1
    #ls -lrts $1
    if [ $__log_file_length -gt $__trigger_log_file_size ];
    then
       #echo "logfiletruncate.sh: log file " $1 "is too long at " $__log_file_length
       echo -ne $(date) " "  >> $LOGFILE
       echo "logfiletruncate.sh: log file " $1 "is too long at " $__log_file_length    >> $LOGFILE
       ls -lrts $1  >> $LOGFILE
       #echo "doing a TAIL of $1 for $__trim_log_file_size bytes"
       sudo echo -ne $(date) "" > /tmp/tarpn/temp_logfile_tail.txt
       sudo echo "Logfile Trimmed to $__trim_log_file_size" >> /tmp/tarpn/temp_logfile_tail.txt
       sudo echo "Logfile length was $__log_file_length" >> /tmp/tarpn/temp_logfile_tail.txt
       sudo echo -e "\n\n\n" >> /tmp/tarpn/temp_logfile_tail.txt
       sudo tail -c$__trim_log_file_size $1 >> /tmp/tarpn/temp_logfile_tail.txt
       #echo "tailed last 1000 lines of $1 to the temp file"
       #ls -l /tmp/tarpn/temp_logfile_tail.txt
       #ls -l $1
       rm $1
       #echo "deleted the original file $1"
       #ls -l $1
       sudo echo -e "\n\n\n\n\n\n" >> /tmp/tarpn/temp_logfile_tail.txt
       #echo "added carriage returns to the temp file"
       #ls -l /tmp/tarpn/temp_logfile_tail.txt
       #ls -l $1
       sudo echo -ne $(date) "" >> /tmp/tarpn/temp_logfile_tail.txt
       #echo "added the date to the temp file"
       #ls -l /tmp/tarpn/temp_logfile_tail.txt
       #ls -l $1
       sudo echo "Logfile $1 Trimmed to $__trim_log_file_size" >> /tmp/tarpn/temp_logfile_tail.txt
       sudo echo "                                Logfile $1 length was $__log_file_length"    >> /tmp/tarpn/temp_logfile_tail.txt
       sudo echo -e "\n\n\n\n\n\n" >> /tmp/tarpn/temp_logfile_tail.txt
       #echo "added a note to the temp file"
       #ls -l /tmp/tarpn/temp_logfile_tail.txt
       #ls -l $1
       chmod 666 /tmp/tarpn/temp_logfile_tail.txt
       #echo "changed the chmod of the temp file"
       #ls -l /tmp/tarpn/temp_logfile_tail.txt
       sudo mv /tmp/tarpn/temp_logfile_tail.txt $1
       #echo "moved the temp file back to $1"
       #sudo truncate -s $__trim_log_file_size $1
       #ls -lrts $1
    else
       echo "logfiletruncate.sh: log file " $1 "is short enough already"
       ls -lrts $1
    fi
else
    sudo echo -e "\n\n\n" >> $LOGFILE
    echo -ne $(date) " "  >> $LOGFILE
    echo "logfiletruncate.sh: ERROR: log file is not found!! =" $1   >> $LOGFILE
    sudo echo -e "\n\n\n" >> $LOGFILE
fi
}
