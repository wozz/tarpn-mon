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
## If on, then goes through a sequence of launching apps and checking apps to make sure they are running unless it is already running.  If running, log an error and repeat the token test.

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
        sleep 5
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



LOGFILE="/var/log/tarpn_rx_tarpnstat_service.log"
SOURCE_URL="/usr/local/sbin/source_url.txt"
NODE_INIT="/home/pi/node.ini"

STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi



######################################################################################## VERSION INFO ####################################################################################################
####  2-26-2019        s101  Create for RX-TARPNSTAT from Statusmonitor service.
####  2-26-2019        s102  rename rx-tarpnstat to rx-tarpnstatapp.
####  2-28-2019        s103  set the permissions of tarpn_home_linkquality.dat to RWRWRW just before launching rx_tarpnstatapp
####  5-23-2021        b104  Fix check_process()
####  6-10-2021        b105  Modernize the logfile including changing its name
####  6-11-2021        b106  turn on full debugging in rx_tarpnstatapp
####  6-12-2021        b107  change no-bpq delay from 1200 seconds to 400 seconds
####  6-12-2021        b108  Change the delay process so we wait many shorter delays
####  6-17-2021        b109  add RX-TARPNSTATAPP not-found check
####  6-17-2021        b110  stop calling rx_tarpnstatapp with verbose prints
####  6-27-2021        b111  if tarpn_home_linkquality.dat does not exist, create it.
#### 11-22-2025 Bullseye112  Respect the STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE

uptime >> $LOGFILE
sudo chmod 666 $LOGFILE
sudo chown pi $LOGFILE
date >> $LOGFILE
echo "--VERSION--rx_tarpnstat.sh           Bullseye112 - start" >> $LOGFILE
echo "rx_tarpnstat.sh  started"

###### Make sure we have a listed URL on the Internet for getting updates and configuration.  If not, wait 3 minutes and then exit
if [ -f $SOURCE_URL ];
then
    echo -ne $(date) " " >> $LOGFILE
    echo -n "source URL is " >> $LOGFILE
    cat $SOURCE_URL >> $LOGFILE
else
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR0: source URL file not found.  wait 1200 seconds" >> $LOGFILE
    sleep 1200
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR0: exit script" >> $LOGFILE
    exit 1
fi

###### Make sure we have a node.ini config file.  If not, wait 3 minutes and then exit
if [ -f $NODE_INIT ];
then
    echo "got NODE_INIT" >> $LOGFILE
else
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR1: NODE INIT file not found.  wait 8 x 30 seconds" >> $LOGFILE
    date >> $LOGFILE
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
    echo -n "ERROR1: exit script" >> $LOGFILE
    date >> $LOGFILE
    exit 1
fi

####### Check Node background service.  If not enabled, don't do the statusmonitoring.
if grep -q "BACKGROUND:ON" /usr/local/etc/background.ini; then
    echo -ne $(date) " " >> $LOGFILE
    echo "BPQ node is enabled to be run as a service" >> $LOGFILE
else
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR2: BPQ node is NOT enabled to be run as a service.  wait 10x20 seconds" >> $LOGFILE
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
    waste_time_if_node_not_service 0
    waste_time_if_node_not_service 0
    waste_time_if_node_not_service 0
    waste_time_if_node_not_service 0
    waste_time_if_node_not_service 0
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR2: exit script" >> $LOGFILE
    exit 1
fi


###### Check to see that the node is actually running.
check_process "linbpq"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $LOGFILE
    echo "BPQ node is running"  >> $LOGFILE
else
    echo -ne $(date) " " >> $LOGFILE
    echo "BPQ node is not running." >> $LOGFILE
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
    echo -ne $(date) " " >> $LOGFILE
    echo "exit script" >> $LOGFILE
    exit 1
fi

######## Make sure somebody else isn't running rx_tarpnstatapp application.  If there is, then dump out of this script.

check_process "rx_tarpnstatapp"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR4: RX_TARPNSTATAPP was already running!  wait 60 seconds starting" >> $LOGFILE
    date >> $LOGFILE
    sleep 60
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR4: exit script" >> $LOGFILE
    exit 1
fi

if [ -f /usr/local/sbin/rx_tarpnstatapp ];
then
   echo -ne $(date) " " >> $LOGFILE
   echo "rx-tarpnstatapp is present"  >> $LOGFILE
else
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR5: RX_TARPNSTATAPP is not found" >> $LOGFILE
    sleep 15
    echo -ne $(date) " " >> $LOGFILE
    echo "ERROR4: exit script" >> $LOGFILE
    exit 1
fi

echo -ne $(date) " " >> $LOGFILE
echo "Get version of RX_TARPNSTAT application"  >> $LOGFILE
/usr/local/sbin/rx_tarpnstatapp version >> $LOGFILE
echo -ne $(date) " " >> $LOGFILE
echo "Starting RX_TARPNSTAT" >> $LOGFILE


#### make sure we can write to the linkquality data file.
if [ -f /usr/local/sbin/rx_tarpnstatapp ];
then
    sudo chmod 666 /usr/local/etc/tarpn_home_linkquality.dat
else
    sudo date > /usr/local/etc/tarpn_home_linkquality.dat
    sudo chmod 666 /usr/local/etc/tarpn_home_linkquality.dat
fi

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi
/usr/local/sbin/rx_tarpnstatapp
echo -ne $(date) " " >> $LOGFILE
echo "Back to script from RX_TARPNSTATAPP" >> $LOGFILE


exit 0;



