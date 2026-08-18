#!/bin/bash

######## STATUSMONITOR script -- See VERSION # below.
## This script is called from statusmonitor.service, which is a service control file.
## statusmonitor.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/tarpn/sbin and is redeployed by "tarpn update".
##
## This script checks /usr/tarpn/etc/background.ini for a token.
## The token can either be BACKGROUND:OFF  or  BACKGROUND:ON
## If off, wait a while, then repeat the test.
## If on, then goes through a sequence of launching apps and checking apps to make sure they are running unless it is already running.  If running, log an error and repeat the token test.

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}


RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rxtarpnstat_service.log"
SOURCE_URL="/usr/tarpn/etc/source_url.txt"
NODE_INIT="/home/pi/node.ini"
######################################################################################## VERSION INFO ####################################################################################################
####  2-26-2019 s101  Create for RX-TARPNSTAT from Statusmonitor service.
####  2-26-2019 s102  rename rx-tarpnstat to rx-tarpnstatapp.
####  2-28-2019 s103  set the permissions of tarpn_home_linkquality.dat to RWRWRW just before launching rx_tarpnstatapp
####  5-23-2021 b104  Fix check_process()
####  6-10-2021 b105  Modernize the logfile including changing its name
####  6-11-2021 b106  turn on full debugging in rx_tarpnstatapp
####  6-12-2021 b107  change no-bpq delay from 1200 seconds to 400 seconds
####  6-12-2021 b108  Change the delay process so we wait many shorter delays
####  6-17-2021 b109  add RX-TARPNSTATAPP not-found check
####  6-17-2021 b110  stop calling rx_tarpnstatapp with verbose prints
####  6-27-2021 b111  if tarpn_home_linkquality.dat does not exist, create it.
####  5-09-2025 bookworm111 Change logfile alias from LOGFILE to RX_TARPNSTAT_LOGFILE.   Change log file name from rx_tarpnstat_service.log to tarpn_rxtarpnstat_service.log

uptime >> $RX_TARPNSTAT_LOGFILE
sudo chmod 666 $RX_TARPNSTAT_LOGFILE
sudo chown pi $RX_TARPNSTAT_LOGFILE
date >> $RX_TARPNSTAT_LOGFILE
echo " =RX_TARPNSTAT.SH           Bookworm111= " >> $RX_TARPNSTAT_LOGFILE; #  --VERSION--#########
echo "rx_tarpnstat.sh  started"

###### Make sure we have a listed URL on the Internet for getting updates and configuration.  If not, wait 3 minutes and then exit
if [ -f $SOURCE_URL ];
then
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo -n "source URL is " >> $RX_TARPNSTAT_LOGFILE
    cat $SOURCE_URL >> $RX_TARPNSTAT_LOGFILE
else
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR0: source URL file not found.  wait 1200 seconds" >> $RX_TARPNSTAT_LOGFILE
    sleep 1200
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR0: exit script" >> $RX_TARPNSTAT_LOGFILE
    exit 1
fi

###### Make sure we have a node.ini config file.  If not, wait 3 minutes and then exit
if [ -f $NODE_INIT ];
then
    echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
else
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR1: NODE INIT file not found.  wait 8 x 30 seconds" >> $RX_TARPNSTAT_LOGFILE
    date >> $RX_TARPNSTAT_LOGFILE
    if [ -f $NODE_INIT ];
    then
        echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
    else
        sleep 30
        if [ -f $NODE_INIT ];
        then
            echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
        else
            sleep 30
            if [ -f $NODE_INIT ];
            then
                echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
            else
                sleep 30
                if [ -f $NODE_INIT ];
                then
                    echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
                else
                    sleep 30
                    if [ -f $NODE_INIT ];
                    then
                        echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
                    else
                        sleep 30
                        if [ -f $NODE_INIT ];
                        then
                            echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
                        else
                            sleep 30
                            if [ -f $NODE_INIT ];
                            then
                                echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
                            else
                                sleep 30
                                if [ -f $NODE_INIT ];
                                then
                                    echo "got NODE_INIT" >> $RX_TARPNSTAT_LOGFILE
                                else
                                    sleep 30
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
    echo -n "ERROR1: exit script" >> $RX_TARPNSTAT_LOGFILE
    date >> $RX_TARPNSTAT_LOGFILE
    exit 1
fi

####### Check Node background service.  If not enabled, don't do the statusmonitoring.
if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
else
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR2: BPQ node is NOT enabled to be run as a service.  wait 10x20 seconds" >> $RX_TARPNSTAT_LOGFILE
    sleep 20
    if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
        echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
    else
        sleep 20
        if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
            echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
            echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
        else
            sleep 20
            if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
            else
                sleep 20
                if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                    echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                else
                    sleep 20
                    if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                        echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                    else
                        sleep 20
                        if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                            echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                            echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                        else
                            sleep 20
                            if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                                echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                                echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                            else
                                sleep 20
                                if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                                    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                                    echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                                else
                                    sleep 20
                                    if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
                                        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                                        echo "BPQ node is enabled to be run as a service" >> $RX_TARPNSTAT_LOGFILE
                                    else
                                        sleep 20
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR2: exit script" >> $RX_TARPNSTAT_LOGFILE
    exit 1
fi


###### Check to see that the node is actually running.
check_process "linbpq"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
else
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo -n "ERROR3: BPQ node is not running.  wait 9x10 seconds starting" >> $RX_TARPNSTAT_LOGFILE
    sleep 10
    check_process "linbpq"
    if [ $? -ge 1 ]; then
        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
        echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
    else
        sleep 10
        check_process "linbpq"
        if [ $? -ge 1 ]; then
            echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
            echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
        else
            sleep 10
            check_process "linbpq"
            if [ $? -ge 1 ]; then
                echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
            else
                sleep 10
                check_process "linbpq"
                if [ $? -ge 1 ]; then
                    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                    echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
                else
                    sleep 10
                    check_process "linbpq"
                    if [ $? -ge 1 ]; then
                        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                        echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
                    else
                        sleep 10
                        check_process "linbpq"
                        if [ $? -ge 1 ]; then
                            echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                            echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
                        else
                            sleep 10
                            check_process "linbpq"
                            if [ $? -ge 1 ]; then
                                echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                                echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
                            else
                                sleep 10
                                check_process "linbpq"
                                if [ $? -ge 1 ]; then
                                    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
                                    echo "BPQ node is running"  >> $RX_TARPNSTAT_LOGFILE
                                else
                                    sleep 10
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    check_process "linbpq"
    if [ $? -ge 1 ]; then
        echo -n ""
    else
        echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
        echo "ERROR3: BPQ node is still not running.  exit script" >> $RX_TARPNSTAT_LOGFILE
        exit 1
    fi
fi

######## Make sure somebody else isn't running rx_tarpnstatapp application.  If there is, then dump out of this script.

check_process "rx_tarpnstatapp"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR4: RX_TARPNSTATAPP was already running!  wait 60 seconds starting" >> $RX_TARPNSTAT_LOGFILE
    date >> $RX_TARPNSTAT_LOGFILE
    sleep 60
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR4: exit script" >> $RX_TARPNSTAT_LOGFILE
    exit 1
fi

if [ -f /usr/tarpn/sbin/rx_tarpnstatapp ];
then
   echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
   echo "rx-tarpnstatapp is present"  >> $RX_TARPNSTAT_LOGFILE
else
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR5: RX_TARPNSTATAPP is not found" >> $RX_TARPNSTAT_LOGFILE
    sleep 60
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "ERROR4: exit script" >> $RX_TARPNSTAT_LOGFILE
    exit 1
fi

echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
echo "Get version of RX_TARPNSTAT application"  >> $RX_TARPNSTAT_LOGFILE
/usr/tarpn/sbin/rx_tarpnstatapp version >> $RX_TARPNSTAT_LOGFILE
echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
echo "Starting RX_TARPNSTAT" >> $RX_TARPNSTAT_LOGFILE


#### make sure we can write to the linkquality data file.
if [ -f /usr/tarpn/sbin/rx_tarpnstatapp ];
then
    sudo chmod 666 /usr/tarpn/etc/tarpn_home_linkquality.dat
else
    sudo date > /usr/tarpn/etc/tarpn_home_linkquality.dat
    sudo chmod 666 /usr/tarpn/etc/tarpn_home_linkquality.dat
fi

/usr/tarpn/sbin/rx_tarpnstatapp
echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
echo "Back to script from RX_TARPNSTATAPP" >> $RX_TARPNSTAT_LOGFILE


exit 0;



