#!/bin/bash

######## HOME BACKGROUND script -- See VERSION # below.
###### Code written by Tadd Torborg  (callsign KA2DEW)  in February 2016 in support of
###### NC4FG's TARPN-HOME project.  This runs on a Raspberry PI

## This script is called from home.service, which is a service control file.
## home.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/local/sbin and is redeployed by "tarpn update".
##
## This script makes sure the nc4fg tarpn-home application is always running if the run token file is present.
PATH_TO_TARPNHOME="/usr/local/sbin/home_web_app"
LOGFILE="/var/log/tarpn_home.log"
MYTOKEN="/usr/local/etc/home.ini"
templocalfile="/tmp/tarpn/tempHomeBackground.tmp"
check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

waste_time_if_not_running() {
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];                     #### Does UPDATE.SH want this stopped?
   then
      exit 0;                                                              #### Wants us stopped.   Exit immediately
   fi
   if grep -q "BACKGROUND:OFF" $MYTOKEN;
   then
      ### TARPN HOME shouldn't be running right now.  Stop it right now.
      if [ -d /tmp/tarpn ]; then
         if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
           sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
         fi
      fi
      sleep 2;
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
      sleep 0.1
   else
      ### node is not running.  Waste some time.
      ### TARPN HOME shouldn't be running right now.  Stop it right now.
      if [ -d /tmp/tarpn ]; then
         if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
           echo -ne $(date) "" >> $LOGFILE
           echo "linbpq is not running.  delete go.flag" >> $LOGFILE
           sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
         fi
      fi
      sleep 30;
   fi
}


waste_time_if_node_not_service() {
if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi
   if grep -q "BACKGROUND:ON" /usr/local/etc/background.ini;
   then
      echo -n
   else
      ### node service is not running.  Waste some time.
      ### TARPN HOME shouldn't be running right now.  Stop it if it is.
      if [ -d /tmp/tarpn ]; then
         if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
           sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
         fi
      fi
      sleep 5;
   fi
}

manual_op_loop()
{
   while [ -e /tmp/tarpn/manual-op.flag ]
   do
       echo -ne $(date) "" >> $LOGFILE
       echo "Doing manual loop so long as /tmp/tarpn/manual-op.flag exists" >> $LOGFILE
       sleep 30;
   done
}


STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   exit 0;
fi



######################################################################################## VERSION INFO ####################################################################################################
####  2-11-2017 j001  Start from pi_shutdown_background.sh
####  2-12-2017 j002  Check to make sure node is up before launching HOME web-app
####  2-12-2017 j003  Remote the remote-me file if we get back from HOME web-app.  Add > logfile when running HOME python
####  2-12-2017 j004  run the python program as user PI
####  2-12-2017 j005  run the python program with python!  doh
####  2-12-2017 j006  move the web app to /usr/local/sbin/home_web_app
####  2-12-2017 j007  check to make sure "dateinstalled.txt" exists in the appropriate folder
####  3-26-2017 j008  fix version print so tarpn sysinfo can find it.
####  1-10-2019 j009  call tarpn_home.pyc instead of server.pyc.
####  1-13-2019 j010  delete remove-me-to-stop-server all over the place if linbpq isn't running.
####  1-13-2019 j011  do killall python variously when tarpn-home should not be running.
####  1-14-2019 j012  conditionally do the killall and remove remove-me file
####  1-31-2019 j013  if not scheduled to run, leave it alone instead of doing kills
####  2-17-2019 j014  put back kills if not scheduled to run, but check if running first and use remove-me file to stop.
#### 10-22-2019 b001  add 2>%1 to the Python call so stderr also goes to the copylog.
####  9-02-2020 b002  be more choosey about detecting the Tarpn Home python task so we don't blow away other python programs
####  5-19-2021 b003  add support for tarpn_home_go flag
####  5-20-2021 b004  move the temp file used in this module to /tmp/tarpn
####  5-23-2021 b005  Fix check_process() {
####  5-23-2021 b006  create the /tmp/tarpn/temp directory while creationg /tmp/tarpn
####  6-06-2021 b007  Create better logging
####  6-07-2021 b008  get rid of some python-hostile killalls and depend more on the .go flag to stop the program
####  6-07-2021 b009  directory needs to be set to the folder containing the python program.
####  6-08-2021 b010  added manual loop.
####  6-08-2021 b011  call tarpn home as user root.
####  6-08-2021 b012  speed up calling when tarpn home auto is set to enable.
####  6-17-2021 b013  Move old chat history log file to new /usr/local/etc location with new name.  Make backup
####  6-18-2021 b014  SED the linkquality file to remove $ and ~ characters.  Also truncate the file.  Keep a backup.
#### 12-03-2023 b015  reduce the down-time for TARPN HOME when all is well and TARPN HOME exits, from 60 to 10.
#### 11-22-2025 Bullseye016  respect the STOP SERVICE SCRIPT SEMAPHORE to exit ASAP during delays.

####
echo -ne "\n --VERSION--home_background           Bullseye016 - start:" >> $LOGFILE
date >> $LOGFILE
uptime >> $LOGFILE

sudo chmod 666 $LOGFILE
sudo chown pi $LOGFILE

if [ -f $PATH_TO_TARPNHOME/dateinstalled.txt ];
then
      echo -ne $(date) "" >> $LOGFILE
      echo "TARPN-HOME folder exists.  Good.. moving forward" >> $LOGFILE
else
      echo -ne $(date) "" >> $LOGFILE
      echo "TARPN-HOME does not exist! Exit/abort/run-for-the-hills! (for 3 minutes)" >> $LOGFILE
      sleep 180
      exit 1
fi

LINKQUALITY="/usr/local/etc/tarpn_home_linkquality.dat"
LINKQUALTEMP="/tmp/tarpn/tarpn_home_linkquality.tmp"
LINKQUALITYBACKUP="/home/pi/old_tarpn_home_linkquality.dat"

#### In transition from TAPRN-HOME 2.03 to 2.10, the tarpn-home-chat logfile needed to be moved and renamed.
if [ -e /usr/local/etc/tarpn_home_chat.log ]; then
   echo -ne $(date) "" >> $LOGFILE
   echo "/usr/local/etc/tarpn_home_chat.log already in place" >> $LOGFILE
   echo -ne $(date) "" >> $LOGFILE
   ls -l /usr/local/etc/tarpn_home_chat.log >> $LOGFILE
else
   echo -ne $(date) "" >> $LOGFILE
   echo "/usr/local/etc/tarpn_home_chat.log is not found.  Look for old log file" >> $LOGFILE
   if [ -e /var/log/TARPN_Home_Chat.log ]; then                   ##new log file doesn't exist.  Check if old format log file existed

      echo -ne $(date) "" >> $LOGFILE
      echo "Old /var/log/TARPN_Home_Chat.log was found" >> $LOGFILE

      echo -ne $(date) "" >> $LOGFILE
      ls -l /var/log/TARPN_Home_Chat.log >> $LOGFILE

      sudo chmod 666 /usr/local/etc/tarpn_home_chat.log

      echo -ne $(date) "" >> $LOGFILE
      echo "/usr/local/etc/tarpn_home_chat.log does not exist, but the old TARPN_Home_Chat.log was found" >> $LOGFILE

      sudo mv /var/log/TARPN_Home_Chat.log /usr/local/etc/tarpn_home_chat.log
      sudo cp /usr/local/etc/tarpn_home_chat.log /home/pi/backup_copy_tarpn_home_chat_log.txt

      ## also backup the linkquality file this one time.
      cp $LINKQUALITY $LINKQUALITYBACKUP
   else
      echo -ne $(date) "" >> $LOGFILE
      echo "No Chat history log file found.  Creating new log file" >> $LOGFILE

      echo -ne $(date) "" >> /usr/local/etc/tarpn_home_chat.log
      echo "Creating new TARPN Chat-History log file" >> /usr/local/etc/tarpn_home_chat.log
   fi
fi


########## TARPN HOME can only use a linkquality file of up to 200 lines per callsign.  So truncate it to 2400 lines (200 lines x 12 callsigns maximum)
tail -n2400 $LINKQUALITY > $LINKQUALTEMP
sed -i 's/[$]//g' $LINKQUALTEMP       ## This is only necessary when updating from apr2020 or nov2020test to the jun2021 or later forks of our program
sed -i 's/~/,/g' $LINKQUALTEMP        ## this too. It doesn't hurt though.
mv $LINKQUALTEMP $LINKQUALITY



################# LOOP HERE FOREVER
#### Top of loop -- check if we should be calling home or just waiting for a while.
while [ 1 ];
do
   ### TARPN HOME shouldn't be running at the start of this loop.  Stop it right now.
   #   if [ -d /tmp/tarpn ]; then
   #      if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
   #        sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
   #      fi
   #   fi
   ### See if the file indicated by $MYTOKEN exists at all.
   if grep -q "BACKGROUND" $MYTOKEN; then
      ### yes.. it exists
      sleep 0.5
   else
      ### it did not exist or it was corrupted
      rm -rf $MYTOKEN
      echo "BACKGROUND:OFF" >> $MYTOKEN
      echo -ne $(date) "" >> $LOGFILE
      echo " ERROR!! token file did not exist or did not contain BACKGROUND token" >> $LOGFILE
      echo -ne $(date) "" >> $LOGFILE
      echo  "  I took action to recreate the token file" >> $LOGFILE
   fi


   if grep -q "BACKGROUND:ON" $MYTOKEN; then
      echo -ne $(date) "" >> $LOGFILE
      echo " NC4FG TARPN-HOME is enabled to be run as a service" >> $LOGFILE
      #### See if the node is up.  If not, then we need to not launch HOME
      check_process "linbpq"
      if [ $? -ge 1 ]; then
         echo -ne $(date) "" >> $LOGFILE
         echo "  node is running. Check if running as a service." >> $LOGFILE
         if grep -q "BACKGROUND:OFF" /usr/local/etc/background.ini;
         then
            echo -ne $(date) "" >> $LOGFILE
            echo " node is running, but not as a service -- no TARPN-HOME." >> $LOGFILE
            date >> $LOGFILE
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
            waste_time_if_node_not_service 0
            waste_time_if_node_not_service 0
            waste_time_if_node_not_service 0
            waste_time_if_node_not_service 0
         else
	    date >> $LOGFILE
	    cd $PATH_TO_TARPNHOME
             if [ -d /tmp/tarpn ]; then
                if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
                  sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
                fi
             fi
            if [ -d /tmp/tarpn ]; then
               echo -ne $(date) "" >> $LOGFILE
               echo " /tmp/tarpn exists" >> $LOGFILE
            else
               sudo mkdir /tmp/tarpn
               sudo chown pi /tmp/tarpn
               sudo chmod 777 /tmp/tarpn
               sudo mkdir /tmp/tarpn/temp
               sudo chown pi /tmp/tarpn/temp
               sudo chmod 777 /tmp/tarpn/temp
            fi
            echo -ne $(date) "" >> $LOGFILE
            echo "  Creating tarpn-home-go flag in /tmp/tarpn" >> $LOGFILE
            sudo date > /tmp/tarpn/tarpn_home_go.flag
            sudo chown pi /tmp/tarpn/tarpn_home_go.flag
            sudo chmod 666 /tmp/tarpn/tarpn_home_go.flag

            #### run TARPN HOME here
            #### run TARPN HOME here
            #### run TARPN HOME here
            echo -ne $(date) "" >> $LOGFILE
            echo -ne "pwd="  >> $LOGFILE
            pwd  >> $LOGFILE
            if [ -e /tmp/tarpn/manual-op.flag ];
            then
               echo -ne $(date) "" >> $LOGFILE
               echo "Calling manual-op-loop" >> $LOGFILE
               manual_op_loop;
            else
               echo -ne $(date) "" >> $LOGFILE
               echo "Calling tarpn_home.pyc  log to /var/log/tarpn_home_webapp_copylog.log" >> $LOGFILE
               python3 tarpn_home.pyc >> /var/log/tarpn_home_webapp_copylog.log 2>&1
            fi
            echo -ne $(date) "" >> $LOGFILE
            echo "   back from NC4FG TARPN-HOME" >> $LOGFILE
            sleep 10
         fi


         #### Back from TARPN HOME
         ls -lrat  >> $LOGFILE
         sleep 10
         exit 0;
      else
         echo -ne $(date) "" >> $LOGFILE
         echo "Node is not running.  Hold off on running HOME" >> $LOGFILE
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
      fi
   else
      echo -ne $(date) "" >> $LOGFILE
      echo "  NC4FG TARPN-HOME is NOT enabled to be run as a service" >> $LOGFILE
      if [ -d /tmp/tarpn ]; then
         if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
           sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
         fi
      fi
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
      waste_time_if_not_running 0
   fi
done
