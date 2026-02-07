#!/bin/bash

######## STATUSMONITOR script -- See VERSION # below.
## This script is called from statusmonitor.service, which is a service control file.
## statusmonitor.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/local/sbin and is redeployed by "tarpn update".
##
## This script checks /usr/local/etc/background.ini for a token.
## The token can either be BACKGROUND:OFF  or  BACKGROUND:ON
## If off, wait a while, then repeat the test.
## If on, then goes through a sequence of launching apps and checking apps
# If running, log an error and repeat the test for tokens.

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

waste_time_if_node_ini_missing() {
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       exit 0;
    fi
    if [ -f $NODE_INIT ];
    then
        echo -n
    else
        sleep 15
    fi
}


waste_time_if_node_not_up() {
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      exit 0;
   fi
   check_process "linbpq"
   if [ $? -ge 1 ]; then
      ### node IS running.  waste very little time.
      echo -n
   else
      ### node is not running.  Waste some time.
      sleep 15
   fi
}


waste_time_if_node_not_service() {
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      exit 0;
   fi
   if grep -q "BACKGROUND:ON" $NODE_BACKGROUND_STARTSTOP;
   then
      ### BACKGROUND is ON.  waste very little time.
      echo -n
   else
      sleep 15
   fi
}



STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log";
SOURCE_URL="/usr/local/sbin/source_url.txt"
NODE_INIT="/home/pi/node.ini"
BAD_LINK_WAV="/home/pi/badlinksound.wav"
NODE_BACKGROUND_STARTSTOP="/usr/local/etc/background.ini";

STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi



if [ -f $STATUSMONITOR_LOGFILE ];
then
    sudo chmod 666 $STATUSMONITOR_LOGFILE
else
    echo "statusmonitor.sh: Create log" > /tmp/statusmonitor_sh.tmp
    sudo mv /tmp/statusmonitor_sh.tmp > $STATUSMONITOR_LOGFILE
    sudo chown root $STATUSMONITOR_LOGFILE
    sudo chmod 666 $STATUSMONITOR_LOGFILE
fi

######################################################################################## VERSION INFO ####################################################################################################
#### 11-22-2018 s101  Create to keep the check-bbs app running once in a while
#### 12-08-2018 s102  Improve error output.  Add output of the version number from the application.
#### 12-09-2018 s103  If node is enabled as a service, but not found running, wait 90 seconds and check again.
#### 12-14-2018 s104  Get version of sendroutestocq and output it to the log before entering while
#### 12-15-2018 s105  Speed up the sendroutestocq calls to get it closer to 15 minutes.  Add killall for bbs_checker
####  2-26-2018 s106  Fewer check-bbs-calls between sendroutestocq, to get it closer to 15 minutes.
####  5-23-2021 b107  Fix check_process()
####  6-09-2021 b108  remove a semicolon from the while loop statement.
####  1-21-2025 b109  Only do grep on bbshasmail if the file exists. .
####  5-07-2025 b110  Add a ; after the DO loop start.  This shouldn't have worked before.  Hopefully I didn't just break it!
####  5-07-2025 b111  use $STATUSMONITOR_LOGFILE instead of $LOGFILE
####  5-09-2025 b112  Create the logfile if it doesn't exist  -- change the way node.ini file existance is checked to make change discovery faster.
####  5-11-2025 b113  Fix bug where NODE_BACKGROUND_STARTSTOP was not defined.   Also, use a waste-time function in a couple of places instead of sleeping for a long time.
#### 11-23-2025 Bullseye114  Respect STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE

echo "--VERSION--statusmonitor.sh          Bullseye114-  START" >> $STATUSMONITOR_LOGFILE

date >> $STATUSMONITOR_LOGFILE
uptime >> $STATUSMONITOR_LOGFILE


###### Make sure we have a listed URL on the Internet for getting updates and configuration.  If not, wait 3 minutes and then exit
if [ -f $SOURCE_URL ];
then
    echo -n "source URL is " >> $STATUSMONITOR_LOGFILE
    cat $SOURCE_URL >> $STATUSMONITOR_LOGFILE
else
    echo -n "ERROR0: source URL file not found.  wait 1200 seconds starting @" >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    sleep 1200
    echo -n "ERROR0: exit script @ " >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    exit 1
fi

###### Make sure we have a node.ini config file.  If not, wait 3 minutes and then exit
### If NODE.INI file doesn't exist, sleep for a while and then exit
if [ -f $NODE_INIT ];
then
    echo -n
else
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "node.ini file is not found.  Sleep up to 15 minutes, then exit" >> $STATUSMONITOR_LOGFILE
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
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "node background start-stop is not found.  Sleep 15 minutes, then exit" >> $STATUSMONITOR_LOGFILE
    sleep 900
    exit 0;
fi



####### Check Node background service.  If not enabled, don't do the statusmonitoring.
if grep -q "BACKGROUND:ON" /usr/local/etc/background.ini; then
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "BPQ node is enabled to be run as a service" >> $STATUSMONITOR_LOGFILE
else
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR2: BPQ node is NOT enabled to be run as a service. EXIT" >> $STATUSMONITOR_LOGFILE
    exit 1
fi


###### Check to see that the node is actually running.
check_process "linbpq"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "BPQ node is running"  >> $STATUSMONITOR_LOGFILE
else
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR3: BPQ node is not running.  wait 90 seconds" >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    sleep 15
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
       exit 0;
    fi
    echo -n "Re-check BPQ node @" >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    check_process "linbpq"
    if [ $? -ge 1 ]; then
        date >> $STATUSMONITOR_LOGFILE
        echo "BPQ node is running on second check"  >> $STATUSMONITOR_LOGFILE
    else
        date >> $STATUSMONITOR_LOGFILE
        echo "ERROR3: BPQ node is still not running.  exit script " >> $STATUSMONITOR_LOGFILE
        exit 1
    fi
fi

######## Make sure somebody else isn't running bbs_checker app.  If there is, then dump out of this script.

check_process "bbs_checker"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR4: BPQ-checker was already running!  wait 10" >> $STATUSMONITOR_LOGFILE
    sleep 10
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR4: exit script" >> $STATUSMONITOR_LOGFILE
    exit 1
fi

echo "Get version of BBS checker application"  >> $STATUSMONITOR_LOGFILE
/usr/local/sbin/bbs_checker version >> $STATUSMONITOR_LOGFILE
echo "Get version of sendroutestocq application"  >> $STATUSMONITOR_LOGFILE
/usr/local/sbin/sendroutestocq version >> $STATUSMONITOR_LOGFILE
echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "Starting WHILE(1) loop to run bbschecker every 30 seconds or so @ " >> $STATUSMONITOR_LOGFILE


################# LOOP HERE FOREVER
#### Top of loop -- check if we should be calling check_bbs or just waiting for a while.
while [ 1 ];
do
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
      echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
      exit 0;
   fi
   #### Now get a local R R table, share it via CQ, and generate a log of the link-status for our node
   check_process "sendroutestocq"
   if [ $? -ge 1 ]; then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "ERROR7: in while loop, sendroutestocq redundantly running!  wait 10 seconds starting" >> $STATUSMONITOR_LOGFILE
       sleep 10
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo " exit script" >> $STATUSMONITOR_LOGFILE
       exit 1
   fi

   ### Generate the CQs and add to the log file
   /usr/local/sbin/sendroutestocq

   ### See if the operator wants a WAV file played if the log file has a bad link
   if [ -f $BAD_LINK_WAV ];
      then
      if tail -1 /var/log/tarpn_linkstatus.log | grep -q "BAD"; then
         aplay $BAD_LINK_WAV
      fi
   fi

   # Now loop for the BBS checker, every 30+ seconds, for 15 minutes
   x=1
   while [ $x -le 22 ]
   do
      x=$(( $x + 1 ))

      if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
      then
         echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
         echo "STOP-SERVICE-SEMAPHORE" >> $STATUSMONITOR_LOGFILE
         exit 0;
      fi

      ########### 30 second loop
      check_process "linbpq"
      if [ $? -ge 1 ]; then
          echo
      else
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "in while loop, BPQ node is not running!" >> $STATUSMONITOR_LOGFILE
          exit 1
      fi


     # check_process "request_ninotnc_diags"
     # if [ $? -ge 1 ]; then
     #     echo -n "ERROR6: in while loop, request_ninotnc_diags redundantly running!  @" >> $STATUSMONITOR_LOGFILE
     #     date >> $STATUSMONITOR_LOGFILE
     #     echo -n "ERROR6: do killall and wait 60secs @" >> $STATUSMONITOR_LOGFILE
     #     date >> $STATUSMONITOR_LOGFILE
     #     sudo killall request_ninotnc_diags
     #     sleep 60
     #     echo -n "ERROR6: did killall request_ninotnc_diags - exit script @ " >> $STATUSMONITOR_LOGFILE
     #     date >> $STATUSMONITOR_LOGFILE
     #     exit 1
     # fi

      check_process "bbs_checker"
      if [ $? -ge 1 ]; then
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "in while loop, bbs_checker redundantly running! " >> $STATUSMONITOR_LOGFILE
          sudo killall bbs_checker
          sleep 10
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "exit script " >> $STATUSMONITOR_LOGFILE
          exit 1
      fi

      /usr/local/sbin/bbs_checker
      if [ -f /usr/local/etc/bbshasmail.txt ];
      then
         if grep -q "BBS_HAS_MAIL" /usr/local/etc/bbshasmail.txt; then
            aplay /usr/local/sbin/ring.wav
         fi
      fi
      sleep 10

   done


done

exit 0;



