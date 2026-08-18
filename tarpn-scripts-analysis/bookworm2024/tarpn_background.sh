#!/bin/bash

######## TARPN BACKGROUND script -- See VERSION # below.
## This script is called from tarpn.service, which is a service control file.
## tarpn.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/tarpn/sbin and is redeployed by "tarpn update".
##
## This script checks /usr/tarpn/etc/background.ini for a token.
## The token can either be BACKGROUND:OFF  or  BACKGROUND:ON
## If off, wait a while, then repeat the test.
## If on, then launch linbpq unless it is already running.  If running, log an error and repeat the token test.

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

waste_time_if_not_running() {
if grep -q "BACKGROUND:OFF" /usr/tarpn/etc/background.ini;
then
   #echo "  " >> $TARPN_SERVICE_LOG
   #echo "waste-time-if-not-running()" >> $TARPN_SERVICE_LOG

   check_process "tarpn_home.pyc"
   if [ $? -ge 1 ];
   then
      echo -ne $(date) " " >> $TARPN_SERVICE_LOG
      echo "tarpn-home.pyc is running" >> $TARPN_SERVICE_LOG
      if [ -d /tmp/tarpn ];
      then
         if [ -e /tmp/tarpn/tarpn_home_go.flag ];
         then
           echo -ne $(date) "" >> $HOME_LOGFILE
           echo "tarpn-background.sh: node BACKGROUND:OFF   Delete the taprn-home-go.flag" >> $HOME_LOGFILE
           sudo rm -rf /tmp/tarpn/tarpn_home_go.flag      ## added log write
           echo -ne $(date) " " >> $TARPN_SERVICE_LOG
           echo "go-flag exists.  deleting it" >> $TARPN_SERVICE_LOG
           echo "go-flag exists.  deleting it"
         fi
      fi
      #else
         #echo "stage1: some other pyton service?" >> $TARPN_SERVICE_LOG
   fi
   sleep 5
fi


### old way           check_process "python"
### old way           if [ $? -ge 1 ]; then
### old way               echo "not running but PYTHON seems to still be running.  Remove the remove-me file" >> $TARPN_SERVICE_LOG
### old way               sudo rm -rf /usr/tarpn/sbin/home_web_app/remove_me_to_stop_server.txt
### old way     	  date >> $TARPN_SERVICE_LOG
### old way               sleep 5
### old way           fi
check_process "tarpn-home.pyc"
if [ $? -ge 1 ];
then
   echo -ne $(date) " " >> $TARPN_SERVICE_LOG
   echo "tarpn-home.pyc is yet again still running.  Kill all Python" >> $TARPN_SERVICE_LOG
   echo "but tarpn-home.pyc is yet again still running.  Kill all Python"
   sudo killall python
   sleep 10
fi
}

GETALL_LOG="/var/log/tarpn_ninotnc_getall.log"

NPA_LOGFILE="/var/log/tarpn_neighbor_port_association.log"
TARPN_SERVICE_LOG="/var/log/tarpn_service.log"
HOME_LOGFILE="/var/log/tarpn_home.log"
SOURCE_URL="/usr/tarpn/etc/source_url.txt"
START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
NODE_INIT="/home/pi/node.ini"
RUNBPQLOG="/var/log/tarpn_runbpq.log"
TARPN_HOME_COPYLOG="/var/log/tarpn_home_webapp_copylog.log"
TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log"
TARPNMON_RUNNER_LOG="/var/log/tarpn_mon.log";
RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rxtarpnstat_service.log"

### templocalfile="/usr/tarpn/etc/tarpn_ba ckground_tempfile.tmp"
######################################################################################## VERSION INFO ####################################################################################################
#### 11-17-2015 j101  Add DATE prints to once each loop after state is checked
####  2-13-2016 j102  Add comments at the top of the file.  No changes.
####  3-17-2016 j103  Add lots more waste-time-if-not-running( ) calls.
####  6-15-2016 j104  change the path to the log file.
####  2-12-2017 j105  if node is not running, kill off the tarpn-home web-app
####  2-14-2017 j106  Fix tarpn-home-kill to be proper kill file. if node is not enabled but is running, don't kill off tarpn-home.
#### 11-04-2018 j107  Add I2C information to the log file each time this kicks off
#### 01-12-2018 s001  Fix call to grep which logged the port info at node-launch.
#### 01-12-2018 s002  Fix call to grep which logged the port info at node-launch.   Added ports 6 through 12.
#### 01-14-2018 s003  stop complaing about PYTHON running until we actually check.
#### 05-17-2020 s004  use a direct i2cdetect call to read the i2c bus instead of calling tarpn i2c.  Also, add checking for usb devices and scanning for tty in node.ini
#### 09-02-2020 s005  use a direct i2cdetect call to read the i2c bus instead of calling tarpn i2c.  Also, add checking for usb devices and scanning for tty in node.ini
#### 05-19-2021 b001  new TARPN HOME run/don't-run semaphore
#### 05-23-2021 b002  fix check_process()   Create /tmp/tarpn right here, right now, if it doesn't exist yet.
#### 05-24-2021 b003  Some more places to check tarpn-home.pyc instead of python.  Change the logfile name to tarpn_service.log instead of tarpn.log.  Trim down the waste_time_if_not_running().  Add more log entries.
#### 05-30-2021 b020  Start adding support for automatic neighbor-port-association
#### 05-30-2021 b021  removed the SAVED NODES file before launching linbpq
#### 05-30-2021 b022  Fix logging of the neighbors and ttys.
#### 06-07-2021 b023  add writes to TARPN START/STOP log.
#### 06-08-2021 b024  add a write to the tarpn-home.log when killing the tarpn home go flag.
#### 06-09-2021 b025  modernize the lines we're writing to our logfile so time at the start of the line for every log entry
#### 06-12-2021 b026  minor log file tweaks.  Re-arrange the neighbors-in-use listing.
#### 06-13-2021 b027  blow away /tmp/tarpn when the service starts.
#### 06-13-2021 b028  Add a print to logfile if tarpn service is enabled after waiting for a while.
#### 06-21-2021 b029  If LINBPQ is found to have quit, killoff Neighbor Port Association so we recreate routes when we start LINBPQ back up. .
#### 10-22-2021 b030  Re-write two echo strings which were showing up in a version-check grep.
#### 11-10-2021 bullseye 001  Create tarpn_runbpq log if it does not exist.
#### 11-13-2021 bullseye 002  truncate several log files every time through the loop
#### 11-13-2021 bullseye 003  Fix an echo line that used a reserved version of the tarpn backgrond filename
#### 12-03-2021 bullseye 004  Change how we do truncate.  Instead of just using the truncate command, call a function that checks to see if truncate is needed
####  1-23-2022 bullseye 005  CHMOD all tarpn_ logfiles to 777.  Add the name of this script file to a few log file entries.
####  2-09-2022 bullseye 006  Instead of trying to truncate tarpn_home_copylog when it doesn't exist, put an error message in tarpn_service.log
####  4-23-2022 bullseye 007  minor fix on a log line, -n was not necessary.
####  9-13-2022 bullseye 008  change the way we do log file writes at start -- we don't need to start the log file anymore, or set the rights for them --  change the name of the log files.
####  9-27-2022 bullseye 009  Turn off WIFI power save every time this script starts.
####  1-09-2023 bullseye 010  Fix bug from June 2021 where I was blowing away the GETALL log completely when tarpn_background started.
####  1-17-2023 bullseye 011  Add a write to TARPNCOMMANDLOGFILE at start.
#### 12-30-2023 bullseye 012  Add /tmp/tarpn/port_PLACEHOLDER file to help tinfo.sh look nice in TNC status display.
#### 12-30-2023 bullseye 013  if a script called soft.sh is found in the pi home directory, run it.
#### 12-30-2023 bullseye 014  if the soft script is present, do a delete of the /dev/ttyACM files before running the soft script.
####  1-31-2024 bookworm 020  Remove the soft script detector
####  5-09-2025 bookworm 021  Truncate all of the log files.  Add comments to identify what the log files are.
####  5-09-2025 Bookworm022  turn off cups print-server server.
####  2-05-2026 Bookworm023  Modify version string to standarize.

echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
echo "#### =TARPN_BACKGROUND.SH       Bookworm023=  start:" >> $TARPN_SERVICE_LOG;  #  --VERSION--#########
uptime -p >> $TARPN_SERVICE_LOG

echo -ne $(date) "" >> $START_STOP_LOGFILE;
sudo uptime -p >> $START_STOP_LOGFILE;
echo -ne $(date) "" >> $START_STOP_LOGFILE;
echo " tarpn-background starting -- see tarpn_service.log" >> $START_STOP_LOGFILE;

echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
echo "tarpn_background Starting   Uptime:" >> $TARPNCOMMANDLOGFILE
uptime >> $TARPNCOMMANDLOGFILE

## sudo uptime -p > $GETALL_LOG
## sudo chmod 666 $GETALL_LOG
## sudo chown pi $GETALL_LOG
## echo -ne $(date) "" >> $GETALL_LOG;
## echo " tarpn-background starting -- see tarpn_service.log" >> $GETALL_LOG;
sudo service cups stop          ## we don't need to be a print server.

sudo rm -rf /temp/tarpn

if [ -d /tmp/tarpn ]; then
   echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
   echo "/tmp/tarpn exists" >> $TARPN_SERVICE_LOG
   echo "/tmp/tarpn exists"
else
   echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
   echo "Creating /tmp/tarpn and /tmp/tarpn/temp"
   echo "Creating /tmp/tarpn and /tmp/tarpn/temp" >> $TARPN_SERVICE_LOG
   sudo mkdir /tmp/tarpn
   sudo chown pi /tmp/tarpn
   sudo chmod 777 /tmp/tarpn
   sudo mkdir /tmp/tarpn/temp
   sudo chown pi /tmp/tarpn/temp
   sudo chmod 777 /tmp/tarpn/temp
fi

echo "nothing to see here" > /tmp/tarpn/port_PLACEHOLDERstatus.dat

###   if [ -f $SOFTLINK_SMT_NINOTNCS_SCRIPT ];
###   then
###      echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
###      echo "There is a soft-link shell script in home directory.  ls -l the potential TNC files" >> $TARPN_SERVICE_LOG
###      ls -l /dev/ttyUSB*  >> $TARPN_SERVICE_LOG;
###      ls -l /dev/ttyACM*  >> $TARPN_SERVICE_LOG;
###      echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
###      echo "Delete the dev ttyACM files and do the ls -l again" >> $TARPN_SERVICE_LOG
###      sudo rm /dev/ttyACM*
###      ls -l /dev/ttyUSB*  >> $TARPN_SERVICE_LOG;
###      ls -l /dev/ttyACM*  >> $TARPN_SERVICE_LOG;
###      echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
###      echo "Now run the soft-link shell script" >> $TARPN_SERVICE_LOG
###      sudo chmod +x $SOFTLINK_SMT_NINOTNCS_SCRIPT
###      sudo $SOFTLINK_SMT_NINOTNCS_SCRIPT
###      echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
###      echo "We are back to tarpn_background after running the soft-link shell script.  ls -l the devices again." >> $TARPN_SERVICE_LOG
###      ls -l /dev/ttyUSB*  >> $TARPN_SERVICE_LOG;
###      ls -l /dev/ttyACM*  >> $TARPN_SERVICE_LOG;
###   fi

#### Tell WIFI to not be slow
sudo iw wlan0 set power_save off
echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
echo " =WIFI told [sudo iw wlan0 set power_save off]" >> $TARPN_SERVICE_LOG

### TRUNCATE LOG FILES
source logfiletruncate.sh

sudo chmod 666 /var/log/tarpn*.log
truncate_log_file $GETALL_LOG                            #tarpn_ninotnc_getall.log   written to by rx_tarpnstat.c
truncate_log_file $NPA_LOGFILE                           #tarpn_neighbor_port_association.log
truncate_log_file $TARPN_SERVICE_LOG                     #tarpn_service.log
truncate_log_file $HOME_LOGFILE                          #tarpn_home.log
truncate_log_file $START_STOP_LOGFILE                    #tarpn_startstop.log
truncate_log_file $RUNBPQLOG                             #tarpn_runbpq.log
truncate_log_file $TARPNCOMMANDLOGFILE                   #tarpn_command.log
truncate_log_file $STATUSMONITOR_LOGFILE                 #tarpn_statusmonitor.log
truncate_log_file $TARPNMON_RUNNER_LOG                   #tarpn_mon.log
truncate_log_file $RX_TARPNSTAT_LOGFILE                  #tarpn_rxtarpnstat_service.log
truncate_log_file $TARPN_CONTROL_PANEL_LOGFILE           #tarpn_control_panel.log
truncate_log_file /var/log/tarpn_linkstatus.log          # written to by send_routes_via_cq.c
truncate_log_file /var/log/tarpn_tarpnstat.log           # written to by rx_tarpnstat.c
truncate_log_file /var/log/tarpn_home_runtime.log        # written to by TARPN-HOME
truncate_log_file /var/log/tarpn_home_webapp_copylog.log # written to by TARPN-HOME

if [ -f $TARPN_HOME_COPYLOG ];
then
    truncate_log_file $TARPN_HOME_COPYLOG
else
    echo -ne $(date) "" >> $TARPN_SERVICE_LOG
    echo $TARPN_HOME_COPYLOG "does not exist yet - cannot truncate" >> $TARPN_SERVICE_LOG
fi


###### Make sure we have a listed URL on the Internet for getting updates and configuration.  If not, wait 3 minutes and then exit
if [ -f $SOURCE_URL ];
then
    echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
    echo -n "source URL is " >> $TARPN_SERVICE_LOG
    cat $SOURCE_URL >> $TARPN_SERVICE_LOG
else
    echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
	echo "ERROR0: source URL file not found.   Aborting in 180 seconds" >> $TARPN_SERVICE_LOG
	sleep 180
        echo -ne $(date) "" >> $TARPN_SERVICE_LOG;
	echo "ERROR0: EXIT" >> $TARPN_SERVICE_LOG
	exit 1
fi

###### Make sure we have a node.ini config file.  If not, wait 3 minutes and then exit
if [ -f $NODE_INIT ];
then
    echo -ne $(date) " " >> $TARPN_SERVICE_LOG
    echo -n "NODE-INIT file word count= " >> $TARPN_SERVICE_LOG
    wc $NODE_INIT >> $TARPN_SERVICE_LOG
else
        echo -ne $(date) " " >> $TARPN_SERVICE_LOG
	echo "ERROR1: NODE INIT file not found." >> $TARPN_SERVICE_LOG
        echo -ne $(date) " " >> $TARPN_SERVICE_LOG
	echo "ERROR1: Aborting in 180 seconds" >> $TARPN_SERVICE_LOG
	sleep 180
        echo -ne $(date) " " >> $TARPN_SERVICE_LOG
	echo "ERROR1: EXIT" >> $TARPN_SERVICE_LOG
	exit 1
fi

####### If runbpq log does not exist, create it.
if [ -f $RUNBPQLOG ];
then
    sudo chmod 666 $RUNBPQLOG
    echo -ne $(date) " " $RUNBPQLOG
    echo -n "TARPN background starting  node.ini wc=" >> $RUNBPQLOG
    wc $NODE_INIT >> $RUNBPQLOG
else
    echo "RUNBPQ LOG does not exist.  Create it."
    echo -ne $(date) "" >> $RUNBPQLOG
    echo "TARPN background creating runbpq log" >> $RUNBPQLOG
    sudo chmod 666 $RUNBPQLOG
    echo -ne $(date) "" >> $RUNBPQLOG
    echo -n "TARPN background starting  node.ini wc=" >> $RUNBPQLOG
    wc $NODE_INIT >> $RUNBPQLOG
fi






################# LOOP HERE FOREVER
#### Top of loop -- check if we should be calling linbpq or just waiting for a while.
while [ 1 ];
do
   if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      echo -ne $(date) " " >> $TARPN_SERVICE_LOG
      echo "BPQ node is enabled to be run as a service" >> $TARPN_SERVICE_LOG
      check_process "linbpq"
      if [ $? -ge 1 ]; then
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "ERROR2: BPQ node is already running.  " >> $TARPN_SERVICE_LOG
         sleep 100
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
	 echo "ERROR2: EXIT" >> $TARPN_SERVICE_LOG
         exit 0;
      else
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "BPQ node is not already running-- we will runbpq" >> $TARPN_SERVICE_LOG

         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "Truncate logfiles.  SDCARD space before truncate:" >> $TARPN_SERVICE_LOG
         df -h / >> $TARPN_SERVICE_LOG

         ### TRUNCATE LOG FILES
         sudo chmod 666 /var/log/tarpn*.*
         truncate_log_file $GETALL_LOG                            #tarpn_ninotnc_getall.log   written to by rx_tarpnstat.c
         truncate_log_file $NPA_LOGFILE                           #tarpn_neighbor_port_association.log
         truncate_log_file $TARPN_SERVICE_LOG                        #tarpn_service.log
         truncate_log_file $HOME_LOGFILE                          #tarpn_home.log
         truncate_log_file $START_STOP_LOGFILE                    #tarpn_startstop.log
         truncate_log_file $RUNBPQLOG                             #tarpn_runbpq.log
         truncate_log_file $TARPNCOMMANDLOGFILE                   #tarpn_command.log
         truncate_log_file $STATUSMONITOR_LOGFILE                 #tarpn_statusmonitor.log
         truncate_log_file $TARPNMON_RUNNER_LOG                   #tarpn_mon.log
         truncate_log_file $RX_TARPNSTAT_LOGFILE                  #tarpn_rxtarpnstat_service.log
         truncate_log_file $TARPN_CONTROL_PANEL_LOGFILE           #tarpn_control_panel.log
         truncate_log_file /var/log/tarpn_linkstatus.log          # written to by send_routes_via_cq.c
         truncate_log_file /var/log/tarpn_tarpnstat.log           # written to by rx_tarpnstat.c
         truncate_log_file /var/log/tarpn_home_runtime.log        # written to by TARPN-HOME
         truncate_log_file /var/log/tarpn_home_webapp_copylog.log # written to by TARPN-HOME

         if [ -f $TARPN_HOME_COPYLOG ];
         then
             truncate_log_file $TARPN_HOME_COPYLOG
         else
             echo -ne $(date) "" >> $TARPN_SERVICE_LOG
             echo -n $TARPN_HOME_COPYLOG "does not exist yet - cannot truncate" >> $TARPN_SERVICE_LOG
         fi


         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "SDCARD space after truncate:" >> $TARPN_SERVICE_LOG
         df -h / >> $TARPN_SERVICE_LOG

         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "List of tty ports likely to be NinoTNC" >> $TARPN_SERVICE_LOG
         ls -l  /dev | grep -e ttyACM -e ttyUSB --color=never  >> $TARPN_SERVICE_LOG
         echo   >> $TARPN_SERVICE_LOG
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "List of neighbors and ports called out in node.ini"    >> $TARPN_SERVICE_LOG
         echo "tarpn_background.sh: #####"     >> $TARPN_SERVICE_LOG
         grep -e neighborA -e neighborB -e neighborC -e neighborD -e neighborE -e neighborF -e neighborG -e neighborH -e neighborI -e neighborJ -e usb-port /home/pi/node.ini   >> $TARPN_SERVICE_LOG
         grep portdev /home/pi/node.ini | grep "tty" | grep -v "ttyXXXX"     >> $TARPN_SERVICE_LOG

         ### remove the saved nodes file because the ports may be in a different order when we start up.
         sudo rm -rf /home/pi/bpq/BPQNODES.dat

         ### Call RUNBPQ ############################################################################################################################################################################################
         ### Call RUNBPQ ############################################################################################################################################################################################
         ### Call RUNBPQ ############################################################################################################################################################################################

         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "Calling RUNBPQ.SH   See /var/log/tarpn_runbpq.log"    >> $TARPN_SERVICE_LOG
         /usr/tarpn/sbin/runbpq.sh




         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "back from runbpq" >> $TARPN_SERVICE_LOG

         echo -ne $(date) "" >> $NPA_LOGFILE
         echo "TARPN-Background: LINBPQ ended. Delete the TNPA directory" >> $NPA_LOGFILE
         sudo rm -rf /tmp/tarpn/tnpa

         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "stop the TARPN-HOME web app" >> $TARPN_SERVICE_LOG
         check_process "tarpn_home.pyc"
         if [ $? -ge 1 ]; then
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
             echo "TARPN-HOME seems to still be running.  Remove the go file" >> $TARPN_SERVICE_LOG
             if [ -d /tmp/tarpn ]; then
                if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
                  echo -ne $(date) "" >> $HOME_LOGFILE
                  echo "tarpn background: back from runbpq Delete the taprn-home-go.flag" >> $HOME_LOGFILE
                  sudo rm -rf /tmp/tarpn/tarpn_home_go.flag     ## added log write
                fi
             fi
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
	     echo "Deleted TARPN HOME go Flag -- sleep for 15" >> $TARPN_SERVICE_LOG
             sleep 15
         fi
         echo "TARPN-Background: Sleep for 30 seconds before restarting LINBPQ"
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "Sleep for 30 seconds before restarting LINBPQ" >> $TARPN_SERVICE_LOG
         echo -ne $(date) "" >> $NPA_LOGFILE
         echo "TARPN-Background: sleep for 30 secondes before restarting LINBPQ" >> $NPA_LOGFILE
         sleep 30    ## give neighbor port association some time to quit.
      fi
   else
      echo -ne $(date) " " >> $TARPN_SERVICE_LOG
      echo "BPQ node is NOT enabled to be run as a service" >> $TARPN_SERVICE_LOG
      check_process "linbpq"
      if [ $? -ge 1 ]; then
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "Not enabled as a service, but is running" >> $TARPN_SERVICE_LOG
      else
         check_process "tarpn_home.pyc"
         if [ $? -ge 1 ]; then
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
             echo "Not enabled and not running. TARPN-HOME.PYC seems to be running.  oops" >> $TARPN_SERVICE_LOG
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
             echo "tarpn_home.pyc seems to still be running.  Remove the GO file" >> $TARPN_SERVICE_LOG
             if [ -d /tmp/tarpn ]; then
                if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
                  echo -ne $(date) "" >> $HOME_LOGFILE
                  echo "tarpn background: tarpn service stopped - Delete the taprn-home-go.flag" >> $HOME_LOGFILE
                  sudo rm -rf /tmp/tarpn/tarpn_home_go.flag        ### added log write
                fi
             fi
             date >> $TARPN_SERVICE_LOG
             sleep 5
         fi
         check_process "tarpn_home.pyc"
         if [ $? -ge 1 ]; then
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
             echo "BPQ is not enabled and not running." >> $TARPN_SERVICE_LOG
             echo -ne $(date) " " >> $TARPN_SERVICE_LOG
             echo "tarpn_home.pyc is yet again still running.  killall python" >> $TARPN_SERVICE_LOG
             echo "TARPN-BACKGROUND:2: calling for killall python"
             sudo killall python
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
      if grep -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini;
      then
         echo -ne $(date) " " >> $TARPN_SERVICE_LOG
         echo "TARPN Service is now enabled." >> $TARPN_SERVICE_LOG
      fi
   fi
done


