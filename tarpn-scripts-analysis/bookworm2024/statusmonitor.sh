#!/bin/bash

######## STATUSMONITOR script -- See VERSION # below.
## Check the BBS to see if we have new mail.
## This script is called from statusmonitor.service, which is a service control file.
## statusmonitor.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/tarpn/sbin and is redeployed by "tarpn update".
##
## This script checks /usr/tarpn/etc/background.ini for a token.
## The token can either be BACKGROUND:OFF  or  BACKGROUND:ON
## If off, wait a while, then repeat the test.
## If on, then goes through a sequence of launching apps and checking apps
# If running, log an error and repeat the test for tokens.

VALUE_IS_TEXT_1 1


check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

waste_time_if_node_ini_missing() {
    if [ -f $NODE_INIT ];
    then
        echo -n
    else
        sleep 15
    fi
}


waste_time_if_node_not_up() {
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
   if grep -q "BACKGROUND:ON" $NODE_BACKGROUND_STARTSTOP;
   then
      ### BACKGROUND is ON.  waste very little time.
      echo -n
   else
      sleep 15
   fi
}



STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log"
SOURCE_URL="/usr/tarpn/etc/source_url.txt"
NODE_INIT="/home/pi/node.ini"
BAD_LINK_WAV="/home/pi/badlinksound.wav"
NODE_BACKGROUND_STARTSTOP="/usr/tarpn/etc/background.ini";


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
####  1-26-2025 b109  only do grep on bbschecker if the file exists.
####  1-26-2025 b110  rename statusmonitor logfile to follow the tarpn_XXX.log  naming convention.
####  5-11-2025 Bookworm111  Add a faster method of recovering when node.ini is finally created.
####  5-11-2025 Bookworm112  use a bookworm-specific version of bbs-checker so the path to the etc files are correct.
####  2-06-2026 Bookworm113  Add a log entry when using aplay.
####  2-06-2026 Bookworm114  Modify the grep statement in you-have-mail detect
####  2-06-2026 Bookworm115  modify all log output statements to put time preceding the statement
####  2-07-2026 Bookworm116  try nto stop BBSchecker falsing
echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo  "=STATUSMONITOR.SH          Bookworm116=   start:" >> $STATUSMONITOR_LOGFILE   ; #  --VERSION--#########
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
if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
    echo "BPQ node is enabled to be run as a service" >> $STATUSMONITOR_LOGFILE
else
    date >> $STATUSMONITOR_LOGFILE
    echo -n "ERROR2: BPQ node is NOT enabled to be run as a service.  Waiting..." >> $STATUSMONITOR_LOGFILE
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
    if grep -q "BACKGROUND:ON" $NODE_BACKGROUND_STARTSTOP;
    then
        date >> $STATUSMONITOR_LOGFILE
        echo -n "Background has been turned on after we delayed.  Recycle Statusmonitor to recheck everythign." >> $STATUSMONITOR_LOGFILE
    else
        date >> $STATUSMONITOR_LOGFILE
        echo -n "Background is still not enabled.  Recycle Statusmonitor script." >> $STATUSMONITOR_LOGFILE
        exit 1
    fi
fi


###### Check to see that the node is actually running.
check_process "linbpq"
if [ $? -ge 1 ]; then
    echo "BPQ node is running"  >> $STATUSMONITOR_LOGFILE
else
    echo -n "ERROR3: BPQ node is not running.  wait 90 seconds starting @" >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    sleep 90
    echo -n "Re-check BPQ node @" >> $STATUSMONITOR_LOGFILE
    date >> $STATUSMONITOR_LOGFILE
    check_process "linbpq"
    if [ $? -ge 1 ]; then
        echo "BPQ node is running on second check"  >> $STATUSMONITOR_LOGFILE
    else
        echo -n "ERROR3: BPQ node is still not running.  wait 1200 seconds starting @" >> $STATUSMONITOR_LOGFILE
        date >> $STATUSMONITOR_LOGFILE
        sleep 1200
        echo -n "ERROR3: exit script @ " >> $STATUSMONITOR_LOGFILE
        date >> $STATUSMONITOR_LOGFILE
        exit 1
    fi
fi

######## Make sure somebody else isn't running bbs_checker app.  If there is, then dump out of this script.
check_process "bbs_checker_bw"
if [ $? -ge 1 ]; then
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR4: bbs_checker_bw.app was already running!  wait 60 seconds" >> $STATUSMONITOR_LOGFILE
    sleep 60
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "ERROR4: exit script" >> $STATUSMONITOR_LOGFILE
    exit 1
fi

echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "Get version of bbs_checker_bw.app"  >> $STATUSMONITOR_LOGFILE
/usr/tarpn/sbin/bbs_checker_bw.app version >> $STATUSMONITOR_LOGFILE

echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "Get version of sendroutestocq application"  >> $STATUSMONITOR_LOGFILE
/usr/tarpn/sbin/sendroutestocq version >> $STATUSMONITOR_LOGFILE

echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "Starting WHILE(1) loop to run bbs_checker_bw.app every 30 seconds or so" >> $STATUSMONITOR_LOGFILE


################# LOOP HERE FOREVER
#### Top of loop -- check if we should be calling check_bbs or just waiting for a while.
while [ 1 ];
do
   #### Now get a local R R table, share it via CQ, and generate a log of the link-status for our node
   check_process "sendroutestocq"
   if [ $? -ge 1 ]; then
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "ERROR7: in while loop, sendroutestocq redundantly running!  wait 60 seconds" >> $STATUSMONITOR_LOGFILE
       sleep 60
       echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
       echo "ERROR7: exit script" >> $STATUSMONITOR_LOGFILE
       exit 1
   fi

   ### Generate the CQs and add to the log file
   /usr/tarpn/sbin/sendroutestocq

   ### See if the operator wants a WAV file played if the log file has a bad link
   if [ -f $BAD_LINK_WAV ];
      then
      if tail -1 /var/log/tarpn_linkstatus.log | grep -q "BAD"; then
         echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
         echo "$BAD_LINK_WAVEis present.  linkstatus log shows a BAD event.  aplay $BAD_LINK_WAV file" >> $STATUSMONITOR_LOGFILE
         aplay $BAD_LINK_WAV
      fi
   fi

   # Now loop for the BBS checker, every 30+ seconds, for 15 minutes
   x=1
   while [ $x -le 22 ]
   do
      x=$(( $x + 1 ))


      ########### 30 second loop
      check_process "linbpq"
      if [ $? -ge 1 ]; then
          echo
      else
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "ERROR5: in while loop, BPQ node is not running!  wait 1200 seconds" >> $STATUSMONITOR_LOGFILE
          date >> $STATUSMONITOR_LOGFILE
          sleep 1200
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "ERROR5: exit script" >> $STATUSMONITOR_LOGFILE
          date >> $STATUSMONITOR_LOGFILE
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

      check_process "bbs_checker_bw"
      if [ $? -ge 1 ]; then
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "ERROR7: in while loop, bbs_checker_bw.app redundantly running!" >> $STATUSMONITOR_LOGFILE
          date >> $STATUSMONITOR_LOGFILE
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "ERROR7: do killall and wait 60secs" >> $STATUSMONITOR_LOGFILE
          sudo killall bbs_checker_bw
          sleep 60
          echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
          echo "ERROR7: did killall bbs_checker_bw - exit script" >> $STATUSMONITOR_LOGFILE
          exit 1
      fi

      /usr/tarpn/sbin/bbs_checker_bw.app
      if [ -f /usr/tarpn/etc/bbshasmail.txt ];
      then
         if [ $(grep -c "BBS_HAS_MAIL" /usr/tarpn/etc/bbshasmail.txt) -eq $VALUE_IS_TEXT_1 ]; then
            echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
            echo "BBS_HAS_MAIL found in /usr/tarpn/etc/bbshasmail.txt - aplay ring.wav file" >> $STATUSMONITOR_LOGFILE
            aplay /usr/tarpn/sbin/ring.wav
         fi
      fi
      sleep 30

   done


done

exit 0;



