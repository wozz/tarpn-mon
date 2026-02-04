#!/bin/bash

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}


#### Stop TARPN-MON if it is running.   This is used to shut-down tarpn-mon because the node isn't up.
stop_tarpnmon() {
    check_process "tarpn-mon"
    if [ $? -ge 1 ];
    then
        echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
        echo "tarpn-mon is running and we don't want it to be" >> $TARPNMON_RUNNER_LOG
        sudo killall tarpn-mon
        sleep 5
        check_process "tarpn-mon"
        if [ $? -ge 1 ];
        then
            echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
            echo "tarpn-mon is running and we don't want it to be #2" >> $TARPNMON_RUNNER_LOG
            sudo killall tarpn-mon
            sleep 5
            check_process "tarpn-mon"
            if [ $? -ge 1 ];
            then
                echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
                echo "tarpn-mon is running and we don't want it to be #3" >> $TARPNMON_RUNNER_LOG
                sudo killall tarpn-mon
                sleep 5
            fi
        fi
    fi
}

waste_time_if_node_ini_missing() {
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
       echo "tarpnmon-runner.sh: STOP-SERVICE-SEMAPHORE" >> $TARPNMON_RUNNER_LOG
       exit 0;
    fi
    if [ -f $NODE_INIT ];
    then
        exit 0;
    fi

    check_process "tarpn-mon"
    if [ $? -ge 1 ];
    then
        echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
        echo "tarpn-mon is running and we don't want it to be #7" >> $TARPNMON_RUNNER_LOG
        sudo killall tarpn-mon
    fi
    sleep 15
}


waste_time_if_node_not_up() {
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
      echo "tarpnmon-runner.sh: STOP-SERVICE-SEMAPHORE" >> $TARPNMON_RUNNER_LOG
      exit 0;
   fi
   check_process "linbpq"
   if [ $? -ge 1 ]; then
      ### node IS running.  waste very little time.
      echo -n
   else
      ### node is not running.  Waste some time.
      ### TARPN MON shouldn't be running right now.  Stop it right now.
      check_process "tarpn-mon"
      if [ $? -ge 1 ];
      then
          echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
          echo "tarpnmon-runner.sh: linbpq not running.  stop tarpn-mon #4" >> $TARPNMON_RUNNER_LOG
          sudo killall tarpn-mon
      fi
      sleep 5
   fi
}


waste_time_if_node_not_service() {
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
      echo "tarpnmon-runner.sh: STOP-SERVICE-SEMAPHORE" >> $TARPNMON_RUNNER_LOG
      exit 0;
   fi
   if grep -q "BACKGROUND:ON" $NODE_BACKGROUND_STARTSTOP;
   then
      ### BACKGROUND is ON.  waste very little time.
      echo -n
   else
      ### node service is not running.  Waste some time.
      ### TARPN MON shouldn't be running right now.  Stop it right now.
      check_process "tarpn-mon"
      if [ $? -ge 1 ];
      then
          echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
          echo "tarpnmon-runner.sh: node service is off - stop tarpn-mon #5" >> $TARPNMON_RUNNER_LOG
          sudo killall tarpn-mon
      fi
      sleep 5
   fi
}


RUNBPQLOG="/var/log/tarpn_runbpq.log";
START_STOP_LOGFILE="/var/log/tarpn_startstop.log";
TARPNMON_RUNNER_LOG="/var/log/tarpn_mon.log";

TARPNMON_EXECUTABLE="/usr/local/sbin/tarpn-mon";

NODE_INIT="/home/pi/node.ini";
NODE_BACKGROUND_STARTSTOP="/usr/local/etc/background.ini";


STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi


echo "  " >> $TARPNMON_RUNNER_LOG;
echo "  " >> $TARPNMON_RUNNER_LOG;
echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
echo "tarpnmon-runner.sh: Background Script File starting." >> $TARPNMON_RUNNER_LOG;

### vbullseye002 2025-05-08 -- Rewrite for background operation.  Remove some excess log files.  Add version # display
### vbullseye003 2025-05-08 -- use delay loop calls from tarpn-home if linbpq is not up or if background is not set to ON
### vbullseye004 2025-05-09 -- Clean up many warning messages and improve wake-up performance
###  Bullseye005 2025-11-22 -- Respect STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE
echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
echo "--VERSION--tarpnmon_runner.sh        Bullseye005 - START" >> $TARPNMON_RUNNER_LOG






####### If tarpnmon log does not exist, create it.
if [ -f $TARPNMON_RUNNER_LOG ];
then
    sudo chmod 666 $TARPNMON_RUNNER_LOG
else
    echo "RUNBPQ LOG does not exist.  Create it."
    echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
    echo "tarpnmon-runner creating tarpn-mon log" >> $TARPNMON_RUNNER_LOG
    sudo chmod 666 $TARPNMON_RUNNER_LOG
    echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
fi

### If tarpn-mon file doesn't exist, sleep for a while and then exit
if [ -f $TARPNMON_EXECUTABLE ];
then
    echo -n
else
    echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
    echo "tarpn-mon file is not found.  Sleep 15 minutes, then exit" >> $TARPNMON_RUNNER_LOG
    stop_tarpnmon
    sleep 900
    exit 0;
fi

### If NODE.INI file doesn't exist, sleep for a while and then exit
if [ -f $NODE_INIT ];
then
    echo -n
else
    echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
    echo "node.ini file is not found.  Sleep up to 15 minutes, then exit" >> $TARPNMON_RUNNER_LOG
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    waste_time_if_node_ini_missing 0
    exit 0;
fi



### If $NODE_BACKGROUND_STARTSTOP file doesn't exist, sleep for a while and then exit
if [ -f $NODE_BACKGROUND_STARTSTOP ];
then
    echo -n
else
    echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
    echo "node background start-stop is not found.  Sleep 15 minutes, then exit" >> $TARPNMON_RUNNER_LOG
    stop_tarpnmon
    sleep 900
    exit 0;
fi



### Loop forever
echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG;
echo "tarpnmon-runner.sh: -- enter WHILE 1 loop" >> $TARPNMON_RUNNER_LOG;
while [ 1 ];
do
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
        exit 0;
    fi
    #echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG;
    #echo "tarpnmon-runner.sh: -- TOP of WHILE 1 loop" >> $TARPNMON_RUNNER_LOG;

### If node is NOT set to run AUTO, then don't run the tarpn-mon.  Turn Sleep and then exit.
    if grep -q "BACKGROUND:ON" $NODE_BACKGROUND_STARTSTOP;
    then
        ## background is set to ON.  Check LINBPQ
        ### If LINBPQ is not running, sleep for a while and then exit
        check_process "linbpq"
        if [ $? -ge 1 ];
        then              ### linbpq process IS found
            #### If TARPN-MON is not running, fork it now.
            check_process "tarpn-mon"
            if [ $? -ge 1 ];
            then
                sleep 10
            else
                echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
                echo "tarpn-mon is NOT running.  We want it to be.  Call/fork it now." >> $TARPNMON_RUNNER_LOG

                sudo -u pi $TARPNMON_EXECUTABLE &
                sleep 5
            fi
        else     ### linbpq process not found
            echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
            echo "tarpn service enabled but LINBPQ is not running." >> $TARPNMON_RUNNER_LOG
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            waste_time_if_node_not_up 0
            exit 0
        fi
    else           ## BACKGROUND is NOT set to on
        echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
        echo "TARPN-service is not enabled." >> $TARPNMON_RUNNER_LOG
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        waste_time_if_node_not_service 0
        exit 0
    fi
done

exit 0

