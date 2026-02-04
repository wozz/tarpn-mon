#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC


startget() {
if [ -f $1 ];
then
   echo $1 "already exists -- deleting it"
   rm $1
fi

wget -o /dev/null $_source_url/$1
if [ -f $1 ];
then
   echo $1 "ok"
else
   wget -o /dev/null $_source_url/$1
   if [ -f $1 ];
   then
      echo $1 "downlaoded on 2nd try by startget"
   else
      wget -o /dev/null $_source_url/$1
      if [ -f $1 ];
      then
         echo $1 "downlaoded on 3rd try by startget"
      else
         echo "startget    Failed to download" $1
         echo "startget    Abort script"
         exit 1
      fi
   fi
fi
}



check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}


resume_services() {
#### Restore all of our background services.

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
    echo "#### start TARPN service"
    echo -ne $(date) " " >> $TARPN_SERVICE_LOG
    echo "TARPN UPDATE -- is resuming tarpn.service" >> $TARPN_SERVICE_LOG
    sudo systemctl start tarpn.service

    echo "#### start neighbor_port_association service"
    echo -ne $(date) " " >> $NPA_LOGFILE
    echo "TARPN UPDATE -- is resuming pi-shutdown-service" >> $NPA_LOGFILE
    sudo systemctl start neighbor_port_association.service

    echo "#### start rx_tarpnstat service"
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "TARPN UPDATE -- is resuming rx-tarpnstat-service" >> $RX_TARPNSTAT_LOGFILE
    sudo systemctl start rx_tarpnstat.service

    echo "#### start home service"
    echo -ne $(date) " " >> $HOME_LOGFILE
    echo "TARPN UPDATE -- is resuming home.service" >> $HOME_LOGFILE
    sudo systemctl start home.service

    echo "#### start statusmonitor service"
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "TARPN UPDATE -- is resuming statusmonitor-service" >> $STATUSMONITOR_LOGFILE
    sudo systemctl start statusmonitor.service

    echo "#### start pi_shutdown service"
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "TARPN UPDATE -- is resuming pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
    sudo systemctl start pi_shutdown.service

    echo "start tarpn-mon service"
    echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
    echo "TARPN UPDATE -- is resuming tarpn-mon-service" >> $TARPNMON_RUNNER_LOG
    sudo systemctl start $TARPN_MON_SERVICE_FILE
fi
}

STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"
DOWNLOAD_SCRIPT_PERMISSION="/usr/local/etc/download-script-permission.txt"


HOME_LOGFILE="/var/log/tarpn_home.log"
TARPN_SERVICE_LOG="/var/log/tarpn_service.log"
START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"
TARPNMON_RUNNER_LOG="/var/log/tarpn_mon.log";
NPA_LOGFILE="/var/log/tarpn_neighbor_port_association.log"
RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rx_tarpnstat_service.log"
STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log";

TARPN_MON_SERVICE_FILE="tarpn_mon.service";

############ 10-15-2015  vJ002   -- stop trying to download host.sh.  It is gone.
############ 10-17-2015  vJ003   -- shutdown service before downloading new service file, then start it again
############  2-14-2016  vJ004   -- add pi-shutdown-background
############  3-04-2016  vJ005   -- if user didn't already have the pi-shutdown-background,   install it now.
############  6-15-2016  vJ006   -- replace tarpn.service  when update is done.
############  6-25-2016  vJ007   -- write a log comment to tarpn-pwrman.log when we shut it down
############  2-11-2017  vJ008   -- add update and install of HOME service file and home_background.sh
############  2-12-2017  vJ009   -- fix bug where leftover code printed wrong message in HOME update
############  2-12-2017  vJ010   -- delete the delete-me files to stop HOME service when replacing the service and the background script.
############  2-12-2017  vJ011   -- fix bug where home_background.sh was moved to the wrong file!
############  2-12-2017  vJ012   -- delete straggler temporary files in the /home/pi folder
############  2-12-2017  vJ013   -- shutdown all services early in the update process
############  2-12-2017  vJ014   -- put start text to differentiate from tarpn updateapps
############  7-29-2017  vJ015   -- refuse to run if python-configparser  is not present.
############  8-05-2017  vJ016   -- delete the tarpn run cookie
############  8-18-2017  vS001   -- disable the Console GETTY service
############  8-19-2017  vS-002  -- add start and end dates.
############  8-20-2017  vs-003  -- Turn on uart in /boot/config.txt
############  10-2-2017  vs-004  -- Add more prints in the slower parts
############  10-2-2017  vs-005  -- fix typo -- add some more prints
############  10-4-2017  vs-006  -- attempt to make start date/time reliable.  I saw it not work once.
############                        Remove redundant service shutdowns.  Make the error messages more consistant.  Get rid of new-install code for some features that are already installed.
############  10-4-2017  vs-007  -- Don't install home if it isn't there already.  Don't quit home twice.  We quit it earlier in the update.
############  10-4-2017  vs-008  -- don't kick bpq if bpq is not running.  Do 20 second delay if BPQ was running, 5 otherwise
############  05-05-2018 vs-009  -- get Unix Epoch Time and write it to the card if it wasn't already there.
############  05-12-2018 vs-010  -- set a default crowdcall in node.ini.
############  05-13-2018 vs-011  -- if chatconfig.cfg is missing or has bad app #, get new copy
############  05-26-2018 vs-012  -- get rid of checking for crowd config in node.ini
############  11-22-2018 vs-013  -- Add the BBS checker background service, script, and app.
############  11-22-2018 vs-014  -- bug fixing BBSCHECKER/STATUSMONITOR
############  11-23-2018 vs-015  -- add ring.wav for updated bbs_checker
############  12-14-2018 vs-016  -- add SENDROUTETOCQ application
############  12-15-2018 vs-017  -- add receive and transmit apps
############   1-14-2019 vs-018  -- delete the TARPN-HOME remove-me file and killall python before doing update.
############   2-17-2019 vs-019  -- improve the TARPN-HOME stop process -- rearrange the order for stopping things
############   2-26-2019 vs-020  -- service files are naw named item-service.txt on the website.   Rename then during download and install  add rx_tarpnstatus files
############   2-26-2019 vs-021  -- rename rx-tarpnstat to rx-tarpnstapapp.  do killall before replacing the applications
############   2-28-2019 vs-022  -- show version of  rx-tarpnstapapp
############   4-19-2019 vs-023  -- write to tarpn-command.log when completed
############   5-24-2020 vb-001  -- CHeck to see if VNC custom.common exists.  if not, create it.
############   8-16-2020 vb-002 --- working on BPQ command extensions.
############   8-17-2020 vb-003 --- finishing BPQ command extensions.
############   8-17-2020 vb-004 --- Change the name of the trr target to trr.sh which will then call trr.  Download trr.sh
############   8-17-2020 vb-005 --- New version of linux.sh   create bpq-extensions folder
############   8-17-2020 vb-006 --- New version of linux.sh (003)  fix create bpq-extensions folder
############   8-23-2020 vb-007 --- Get w4eip_link_quality.txt as trr in sbin
############   8-23-2020 vb-008 --- fix bug in updating linux script
############   8-23-2020 vb-009 --- fix bug in updating linux script
############   8-23-2020 vb-010 --- Stop demanding that the PI SHUTDOWN SERVICe was already installed
############   8-23-2020 vb-011 --- Don't allow update to run as anybody but PI
############   8-24-2020 vb-012 --- fix bad path for trr.sh
############   9-01-2020 vb-013 --- Add flashtnc.py and get_tnc_version.py
############   9-02-2020 vb-014 --- Add latest_ninotnc.zip and create ninotnc versions folder
############  10-04-2020 vb-015 --  remove stray * character on line 384.
############  10-04-2020 vb-016 --  fix some bugs in latest-ninotnc file movement
############  10-29-2020 vb-017 --  add KA UP8R things
############  10-31-2020 vb-018 --  add KA UP8R things
############  10-31-2020 vb-019 --  stop and complain if latest_ninotnc.zip or flashtnc.py or get_tnc_version.py are unable to be downloaded
############  11-30-2020 vb-020 --  Set get-or-set-kaup8r script to be executable
############  03-09-2021 vb-021 --  Replace the initd and services file data with .002 and .003 versions
############  05-19-2021 vb-022 --  new TAPRN HOME run/don't run semaphore
############  05-23-2021 vb-023 --  fix check_process()   use tarpn_home.pyc instead of python to detect of tarpn-home is still running.
############  05-24-2021 vb-024 --  create /tmp/tarpn/temp if it doesn't already exist.
############  05-30-2021 vb-030 --  update/install neighbor-port-association.
############  06-03-2021 vb-031 --  update/install neighbor-port-association.
############  06-06-2021 vb-032 --  stop installing KA UP8R files -- add write to TAROP start/stop log
############  06-07-2021 vb-033 --  put a message in the tarpn-home log when deleting the 'go' flag
############  06-08-2021 vb-034 --  Improve management of stopping tarpn-home and get tarpn-home-update.sh script
############  06-11-2021 vb-035 --  neighbor port association service update to 002.  changed name of neighbor_port_association.sh to npa.sh
############  06-13-2021 vb-036 --  Write to the tarpn_service log file when we stop and start the tarpn service
############  06-30-2021 vb-037 --  Use test_internet.sh to verify Internet access instead of doing it locally
############  10-22-2021 vb-038 --  Follow-through for the migrate function -- delete migrate.sh at the end of update.
############  11-13-2021 vBullseye001 -- fix tailing null in source-url
############  11-30-2021 vBullseye002 -- use zip files for neighbor-port-association app and for rx_tarpnstatapp
############  11-30-2021 vBullseye003 -- turn services back on before exit, even if an error occurs
############  11-30-2021 vBullseye004 -- turn on tarpn service before exit.  Forgot that one
############  11-30-2021 vBullseye005 -- rx_tarpnstat050app
############  11-30-2021 vBullseye006 -- install ZIP
############  11-30-2021 vBullseye007 -- remove zip-temp at the end of update
############  12-02-2021 vBullseye008 -- use zip to transfer the new versions of bbs-checker and sendroutestocq.
############  12-03-2021 vBullseye009 -- rx_tarpnstatapp050 becomes rx_tarpnstatapp.
############  12-03-2021 vBullseye010 -- add logfiletruncate.sh.
############  12-04-2021 vBullseye011 -- add linktest from zip and listen from zip
############   9-19-2021 vBullseye012 -- write to the pwrman log to announce when we are starting or stopping the pwrman service
############   9-28-2022 vBullseye013 -- update installation of Dave's TRR program
###########    3-19-2023 vBullseye014 -- fix TRR installer to delete the old stuff BEFORE installing the new stuff.
###########    3-22-2023 vBullseye015 -- add a g8bpq loopback file that is always 10,000 bytes long
###########    5-06-2023 vBullseye016 -- replace wget calls with tarpnget
###########    5-06-2023 vBullseye017 -- we do not need trr.txt
###########    5-06-2023 vBullseye018 -- get tarpnget and sleep_with_count()
###########    6-04-2023 vBullseye019 -- get g8bpq-stress test program
###########    6-04-2023 vBullseye020 -- replace the g8bpqloop.txt file
###########    6-04-2023 vBullseye021 -- move stress test program to /usr/local/sbin now that tarpn command knows about it.
###########    7-18-2023 vBullseye022 -- get ncpacket wallpaper
###########   10-24-2023 vBullseye023 -- Add a completion date file so tinfo can read it out.
###########   10-25-2023 vBullseye024 -- fix bug in completion date file.
###########   11-26-2023 vBullseye025 -- add L4LISTEN.
###########    1-01-2024 vBullseye026 -- Use new CONTROL_PANEL_LOG file
###########    1-01-2024 vBullseye027 -- Set the rights for the log files, in case they weren't set before.
###########    1-24-2025 vBullseye028 -- Add updating of WA2M tarpn-mon web-page monitor application.
###########    1-25-2025 vBullseye029 -- Add tarpnmon-runner.sh
###########    5-05-2025 vBullseye030 -- Add add tarpn-mon-service
###########    5-07-2025 vBullseye031 -- Fix install of tarpn-mon-service
###########    5-07-2025 vBullseye032 -- Fix install of tarpn-mon-service
###########    5-07-2025 vBullseye033 -- Fix install of tarpn-mon-service
###########    5-07-2025 vBullseye034 -- use -version to get the version # of tarpn-mon
###########    5-09-2025 vBullseye035 -- clean up log messages and add a few for start/stop of tarpn update
###########    6-06-2025 vBullseye036 -- Use the same define for TARPNCOMMANDLOG in every script file that refers to that log file.
###########    6-07-2025 vBullseye037 -- Add install of the Fix-Vnc-Headless.sh script file
###########   10-18-2025 vBullseye038 -- Add install of gpio_for_controlpanel.sh
###########   10-24-2025 vBullseye039 -- get rid of Stopping ttyAMA0 service
###########   10-24-2025 vBullseye040 -- Fix bug where gpio_for_controlpanel.sh was not properly installed
###########   11-22-2025 vBullseye041 -- Add some trapping for services not running
###########   11-22-2025 vBullseye042 -- Add some more trapping for services not running
###########   11-22-2025 vBullseye043 -- focus on the re-enable of tarpn.service.
###########   11-22-2025 vBullseye044 -- add [ -f $DOWNLOAD_SCRIPT_PERMISSION ] blocking the code fragments that update the services.  Stop turning off services.
###########   11-23-2025 vBullseye045 -- create a file in /tmp to stop the service-called-scripts.  STOP_SERVICE_SCRIPT_EXECUTION_SEMIFORE="/tmp/stop_service_scripts.txt"
###########   11-23-2025 vBullseye046 -- move the semiphore to /tmp instead of /tmp/tarpn.   Add KILLALL calls for the background scripts
###########   11-23-2025 vBullseye047 -- Fix bug where tarpn_background.sh was not being updated
###########   11-23-2025  Bullseye048 -- Debugging new tarpnget()
###########   11-23-2025  Bullseye049 -- Set the version # to standard so SYSINFO and UPDATE can read it.
###########   11-24-2025  Bullseye050 -- Don't test or update XINETD.  It is installed in tarpn_start1dl

echo "#####"
echo "#####"
echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo -ne $(date) "" >> $TARPN_SERVICE_LOG
echo        "UPDATE.SH start  update.sh version: Bullseye050-  START" >> $TARPNCOMMANDLOGFILE
echo        "UPDATE.SH start  update.sh version: Bullseye050-  START" >> $TARPN_SERVICE_LOG
echo "##### --VERSION--update                    Bullseye050-  START"


echo "Hello user " $(whoami);

if [ $(whoami) != "pi" ]; then
    echo "TARPN UPDATE should only be run by user pi"
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  FAIL: User is $(whoami) -- must be pi" >> $TARPNCOMMANDLOGFILE
    exit 1               #wrong user
fi


sudo echo date >> $TARPNCOMMANDLOGFILE
sudo chmod 666 $TARPNCOMMANDLOGFILE

rm -rf ~/update_start_date.txt
uptime
date > ~/update_start_date.txt
cat ~/update_start_date.txt




echo
echo " "
echo " #######     #     ######   ######   #     #"
echo "    #       # #    #     #  #     #  ##    #"
echo "    #      #   #   #     #  #     #  # #   #"
echo "    #     #     #  ######   ######   #  #  #"
echo "    #     #######  #   #    #        #   # #"
echo "    #     #     #  #    #   #        #    ##"
echo "    #     #     #  #     #  #        #     #"
echo " "
sleep 0.2
echo " #     #  ######   ######      #     #######  ####### "
echo " #     #  #     #  #     #    # #       #     #       "
echo " #     #  #     #  #     #   #   #      #     #       "
echo " #     #  ######   #     #  #     #     #     #####   "
echo " #     #  #        #     #  #######     #     #       "
echo " #     #  #        #     #  #     #     #     #       "
echo "  #####   #        ######   #     #     #     ####### "
echo " "
sleep 0.2
echo
uptime

sudo rm /usr/local/etc/ag.dat

### Establish a source URL for acquiring updated materials
cd /home/pi
if [ -f /usr/local/sbin/source_url.txt ];
then
    echo -n;
else
   echo "##### ERROR706.043: source URL file not found."
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo " update.sh ERROR706.043 trying to get Source URL - QUIT" >> $TARPNCOMMANDLOGFILE
   echo
   echo "##### Aborting"
   exit 1
fi
_source_url=$(tr -d '\0' </usr/local/sbin/source_url.txt);

if [ -f /usr/local/sbin/test_internet.sh ];
then
    echo "Internet test code is loaded"
else
    sudo rm -f test_internet.sh
    startget test_internet.sh
    if [ -f test_internet.sh ];
    then
        if grep -q "copyright Tadd Torborg KA2DEW" test_internet.sh; then
           chmod +x test_internet.sh
           sudo cp test_internet.sh /usr/local/sbin
        else
           echo "FAIL1 getting access to Internet for update"
           echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
           echo " update.sh FAIL1 trying to read files from Internet - QUIT" >> $TARPNCOMMANDLOGFILE
           exit 1
        fi
    else
        echo "ERROR706.042:  FAIL2 getting access to Internet for update"
        echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
        echo "ERROR706.042:   update.sh FAIL2 trying to read files from Internet - QUIT" >> $TARPNCOMMANDLOGFILE
        exit 1
    fi
fi

uptime





echo "##### Verify script WRITE access to the /home/pi user directory"
cd /home/pi
source test_internet.sh
getTestFile
if [ $? -lt 1 ];       ## if no errors, move on
then
   echo "We have access to the TARPN repository"
else
    echo "ERROR706.041  FAIL getting access to Internet for update"
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "ERROR706.041  update.sh failed to read files from Internet - QUIT" >> $TARPNCOMMANDLOGFILE
    exit 1;
fi




###########  Get UNIX EPOCH TIME and write it to the card.
if [ -f /usr/local/sbin/tarpn_start1dl_starttime.txt ];
then
   echo -n "This SD card had the datecode of "
   cat /usr/local/sbin/tarpn_start1dl_starttime.txt
else
   date +%s > /home/pi/datetemp.txt
   sudo mv /home/pi/datetemp.txt /usr/local/sbin/tarpn_start1dl_starttime.txt
   echo -n "This SD card is "
   cat /usr/local/sbin/tarpn_start1dl_starttime.txt
fi


uptime


rm -f tarpn
rm -f runbpq.sh


sudo chmod 666 $START_STOP_LOGFILE
echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### TARPN UPDATE starting"  >> $START_STOP_LOGFILE

echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo "### TARPN UPDATE starting"  >> $TARPNCOMMANDLOGFILE


echo

##################################################################################################
echo "###### Download TARPNGET"
startget tarpnget.sh
if [ -f tarpnget.sh ];
then
   echo "##### tarpnget downloaded successfully"
   chmod +x tarpnget.sh;
   sudo mv tarpnget.sh /usr/local/sbin/tarpnget.sh
else
   echo -e "\n\n\n\n\nERROR: UPDATE Failed retrieving tarpnget.  Something is wrong"
   echo -e "ERROR: UPDATE Aborting\n\n\n\n\n"
   exit 1;
fi

source /usr/local/sbin/tarpnget.sh
echo
echo "###### Download SLEEP-WITH-COUNT"
tarpnget sleep_with_count.sh
if [ -f sleep_with_count.sh ];
then
   echo "##### sleep_with_count downloaded successfully"
   chmod +x sleep_with_count.sh;
   sudo mv sleep_with_count.sh /usr/local/sbin/sleep_with_count.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving sleep_with_count.  Something is wrong"
   echo -e "ERROR: UPDATE Aborting\n\n\n\n\n"
   exit 1;
fi


source /usr/local/sbin/sleep_with_count.sh
##################################################################################################
echo

uptime















###################################################################################################
###################################################################################################
######    ____    _                    _       _   _   ____    ____      _    _____   _____   #####
######   / ___|  | |_    __ _   _ __  | |_    | | | | |  _ \  |  _ \    / \  |_   _| | ____|  #####
######   \___ \  | __|  / _` | | '__| | __|   | | | | | |_) | | | | |  / _ \   | |   |  _|    #####
######    ___) | | |_  | (_| | | |    | |_    | |_| | |  __/  | |_| | / ___ \  | |   | |___   #####
######   |____/   \__|  \__,_| |_|     \__|    \___/  |_|     |____/ /_/   \_\ |_|   |_____|  #####
######                                                                                        #####
###################################################################################################
###################################################################################################
###################################################################################################
echo
echo "##### Set semaphore to stop background scripts"
sudo touch $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE
sleep 1

echo -ne $(date) "" >> $HOME_LOGFILE
echo "### TARPN UPDATE starting"  >> $HOME_LOGFILE

echo -ne $(date) "" >> $TARPN_SERVICE_LOG
echo "### TARPN UPDATE starting"  >> $TARPN_SERVICE_LOG

echo -ne $(date) "" >> $TARPN_CONTROL_PANEL_LOGFILE
echo "### TARPN UPDATE starting"  >> $TARPN_CONTROL_PANEL_LOGFILE

echo -ne $(date) "" >> $START_STOP_LOGFILE
echo "### TARPN UPDATE starting"  >> $START_STOP_LOGFILE

echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo "### TARPN UPDATE starting"  >> $TARPNCOMMANDLOGFILE

echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
echo "### TARPN UPDATE starting"  >> $TARPNMON_RUNNER_LOG

echo -ne $(date) "" >> $NPA_LOGFILE
echo "### TARPN UPDATE starting"  >> $NPA_LOGFILE

echo -ne $(date) "" >> $RX_TARPNSTAT_LOGFILE
echo "### TARPN UPDATE starting"  >> $RX_TARPNSTAT_LOGFILE

echo -ne $(date) "" >> $STATUSMONITOR_LOGFILE
echo "### TARPN UPDATE starting"  >> $STATUSMONITOR_LOGFILE


sudo killall tarpn_background.sh
sudo killall npa.sh
sudo killall home_background.sh
sudo killall runbpq.sh
sudo killall pi_shutdown_background.sh
sudo killall rx_tarpnstat.sh
sudo killall statusmonitor.sh





###################################################################################################
if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
    echo "#### shutting down tarpn service"
    sudo systemctl stop tarpn.service
    echo "#### systemctl STOP sent to tarpn service"

    sudo chmod 666 $TARPN_SERVICE_LOG

    echo -ne $(date) "" >> $TARPN_SERVICE_LOG
    echo "### UPDATE: Stopped tarpn service"  >> $TARPN_SERVICE_LOG
fi



uptime

echo "#### Check if LINBPQ (the node) is running"

######## kill (to cause to restart) the BPQ node
cd /home/pi
check_process "linbpq"
if [ $? -ge 1 ]; then
    echo "#### issuing a kill to linbpq node application"
    sudo killall linbpq;
    echo
    echo "##### BPQ node has been killed ."
    echo
else
    echo "##### BPQ not running. "
fi
    echo

if [ -d /tmp/tarpn ]; then
   echo "#### See if TARPN HOME needs stopping"
   if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
     echo "#### tell TARPN HOME to stop"
     echo -ne $(date) "" >> $HOME_LOGFILE
     echo "tarpn-update: Delete the tarpn-home-go.flag" >> $HOME_LOGFILE
     sudo rm -rf /tmp/tarpn/tarpn_home_go.flag         ### added log entry
     sleep 2
   else
     echo "#### TARPN home didn't need telling"
   fi
fi
    echo

echo "##### Install ZIP command"
sudo apt install zip
uptime


echo "##### Removing old zip-temp directory (if it exists)"
sudo rm -rf /home/pi/zip-temp

sudo chmod 666 $HOME_LOGFILE
echo -e "\n\n" >> $HOME_LOGFILE
echo -ne $(date) "" >> $HOME_LOGFILE
echo "Starting TARPN-UPDATE  -- this will kill off the home service" >> $HOME_LOGFILE
uptime

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
    #### Shutdown all of our background services.
    echo "#### shutting down neighbor_port_association service"
    echo -e "\n\n" >> $NPA_LOGFILE
    echo -ne $(date) "" >> $NPA_LOGFILE
    echo "TARPN UDPATE starting -- suspending NPA service" >> $NPA_LOGFILE
    sudo systemctl stop neighbor_port_association.service
    uptime


    echo "#### shutting down rx_tarpnstat service"
    echo -e "\n\n" >> $RX_TARPNSTAT_LOGFILE
    echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
    echo "TARPN UDPATE starting -- suspending rx-tarpnstat-service" >> $RX_TARPNSTAT_LOGFILE
    sudo systemctl stop rx_tarpnstat.service
    uptime


    echo "#### shutting down home service"
    echo -e "\n\n" >> $HOME_LOGFILE
    echo -ne $(date) " " >> $HOME_LOGFILE
    echo "TARPN UDPATE starting -- suspending home.service" >> $HOME_LOGFILE
    sudo systemctl stop home.service
    uptime


    echo "#### shutting down statusmonitor service"
    echo -e "\n\n" >> $STATUSMONITOR_LOGFILE
    echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
    echo "TARPN UDPATE starting -- suspending statusmonitor-service" >> $STATUSMONITOR_LOGFILE
    sudo systemctl stop statusmonitor.service
    uptime

    echo "#### shutting down pi_shutdown service"
    sudo chmod 666 $TARPN_CONTROL_PANEL_LOGFILE
    echo -e "\n\n" >> $TARPN_CONTROL_PANEL_LOGFILE
    sudo echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    sudo echo "TARPN UDPATE starting -- suspending pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
    sudo systemctl stop pi_shutdown.service
    uptime

    echo "#### shutting down tarpn-mon service"
    sudo systemctl stop $TARPN_MON_SERVICE_FILE
    echo -e "\n\n" >> $TARPNMON_RUNNER_LOG
    echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
    echo "TARPN UDPATE starting -- suspending tarpn-mon service" >> $TARPNMON_RUNNER_LOG

    uptime
fi

echo " "
echo " "
echo " "
echo " "




#### to install the custom bpq commands we need to do this
### install xinetd
### once-installed, create a file called /usr/local/etc/xinitd.001

### download the custom-bpq-commands-services.001 file
### copy custom-bpq-commands-services.001 to /etc/services
### once copied/installed, create /usr/local/etc/custom-bpq-commands-services.001

### download the custom-bpq-commands-inetd.001 file
### copy contents of custom-bpq-commands-inetd.001 to /etc/inetd.conf
### once copied/installed, create /usr/local/etc/custom-bpq-commands-inetd.001


##### get rid of any temporary files leftover from a previous run of update
rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*
rm -f ~/neighbor_port_association*
### this is done during tarpn-start1dl   ############ Update inet.d configuration
### this is done during tarpn-start1dl
### this is done during tarpn-start1dl   if [ -f /usr/local/etc/xinetd.001 ];
### this is done during tarpn-start1dl   then
### this is done during tarpn-start1dl      echo "### xinetd already installed"
### this is done during tarpn-start1dl   else
### this is done during tarpn-start1dl      echo "### XINETD not installed.  Will do so now."
### this is done during tarpn-start1dl      sudo apt-get -y install xinetd
### this is done during tarpn-start1dl      sudo touch /usr/local/etc/xinetd.001
### this is done during tarpn-start1dl   fi
### this is done during tarpn-start1dl   echo " "
### this is done during tarpn-start1dl   echo " "


######### Get a 10K test file and put it in the Files folder
if [ -d /home/pi/bpq/Files ]; then
   echo "  Files folder already exists"
else
   cd /home/pi/bpq
   mkdir Files
   echo "  Files folder was missing.  Create it"
fi


echo "#### get g8bpqloop.txt"
cd ~
sudo rm -f g8bpqloop.txt
uptime
tarpnget g8bpqloop.txt
if [ -f /home/pi/bpq/Files/g8bpqloop.txt ]; then
   sudo mv g8bpqloop.txt /home/pi/bpq/Files
else
   echo "ERROR706.055: Failed to get g8bpqloop.txt file"
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.055.  Failed to get g8bpqloop.txt file from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.055!  Failed to get g8bpqloop.txt file from web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR706.055: Aborting"
fi

uptime

######### INSTALL WALLPAPER ###################################################################
echo "#### install wallpaper if needed"
cd ~
if [ -f /usr/share/rpd-wallpaper/ncpacket-wallpaper.gif ];
then
   echo "NCPACKET wallpaper is already installed"
else
   echo "get NCPACKET wallpaper"
   sudo rm -f ncpacket-w*
   tarpnget ncpacket-wallpaper.gif
   if [ -f ncpacket-wallpaper.gif ];
   then
       sudo mv ncpacket-wallpaper.gif /usr/share/rpd-wallpaper
   fi
fi

uptime

######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
cd ~
mkdir zip-temp
cd zip-temp


echo "#### Download neighbor port association APP regardless of whether we need the update"
tarpnget npa.zip
##### now neighbor_port_association-service.app should exist in the home directory
if [ -f /home/pi/zip-temp/npa.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.030.  Failed to obtain npa.zip from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.030!  Failed to obtain npa.zip from the web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR706.030: Aborting"
   exit 1
fi
uptime

echo "#### Install the NPA APP that we just downloaded"
unzip npa.zip

if [ -f /home/pi/zip-temp/neighbor_port_association.app ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.029.  Error in unzipping npa.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.029! Error in unzipping npa.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.029: Aborting"
   exit 1
fi
uptime

echo "#### Get the NPA control script"
cd /home/pi
tarpnget npa.sh
##### now npa.sh should exist in the home directory
if [ -f ~/npa.sh ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.028.  Failed to obtain npa.sh from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.028! Failed to obtain npa.sh from the web server."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.028: Aborting"
   exit 1
fi
uptime

echo "#### Install the NPA app and control script"
chmod +x npa.sh
sudo killall npa.sh
sudo mv npa.sh /usr/local/sbin
chmod +x zip-temp/neighbor_port_association.app
sudo mv zip-temp/neighbor_port_association.app /usr/local/sbin
if [ -x /usr/local/sbin/npa.sh ];
then
   echo "##### Neighbor-Port-Association script updated"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.027.  Neighbor-port-association script file failed to install."  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "ERROR706.027! Neighbor-Port-Association script file failed to install."
   echo "              Please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.027: Aborting"
   exit 1;
fi

if [ -x /usr/local/sbin/neighbor_port_association.app ];
then
   echo "##### Neighbor-Port-Assocation APP updated"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.026.  Neighbor-port-association app file failed to install."  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "ERROR706.026! Neighbor-Port-Assocation APP file failed to install."
   echo "              Please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.026: Aborting"
   exit 1;
fi

######### NEIGHBOR-PORT-ASSOCIATION service
######### NEIGHBOR-PORT-ASSOCIATION service
######### NEIGHBOR-PORT-ASSOCIATION service
echo
echo "##### See if we need to install the Neighbor Port Association SERVICE"
if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then

    if [ -e /usr/local/etc/npa_installed.002 ];
    then
        echo "##### neighbor-port-association 002 is already installed"
    else
        echo "##### installing neighbor-port-association 002"
        tarpnget neighbor_port_association-service.txt

        ##### now neighbor_port_association-service.txt should exist in the home directory
        if [ -f ~/neighbor_port_association-service.txt ];
        then
            echo " "
        else
            echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
            echo "update.sh  ERROR706.025.  Neighbor-port-association service failed to download."  >> $TARPNCOMMANDLOGFILE
            resume_services
            echo "ERROR706.025!  Outputting debug information to be relayed to he who debugs."
            ls -lrat
            pwd
            echo "url"
            echo $_source_url
            echo "ERROR706.025!  Failed to obtain neighbor_port_association-service.txt from the web server."
            echo "        please send a missive about this to tarpn@groups.io"
            echo "        Include the terminal output from this update."
            echo "ERROR706.025: Aborting"
            exit 1
         fi

        mv neighbor_port_association-service.txt neighbor_port_association.service

        if [ -f /etc/systemd/system/neighbor_port_association.service ];
        then
            sudo rm /etc/systemd/system/neighbor_port_association.service
        fi

        if [ -f /etc/systemd/system/neighbor_port_association.service ];
        then
            echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
            echo "update.sh ERROR706.024.  unable to remove prior neighbor port association service."  >> $TARPNCOMMANDLOGFILE
            resume_services
            echo "ERROR706.024: Unable to remove prior neighbor-port-association.service"
            echo "              please send a missive about this to tarpn@groups.io"
            echo "              Include the terminal output from this update."
            echo "ERROR706.024: Aborting"
            exit 1
       fi
       sudo mv ~/neighbor_port_association.service /etc/systemd/system/neighbor_port_association.service

       if [ -f /etc/systemd/system/neighbor_port_association.service ];
       then
       ### Download files related to automatic operation

       ### Start NPA service from the OS
          echo "##### Neighbor-Port-Assocation SERVICE file installed"
          sudo systemctl daemon-reload
          sudo systemctl enable neighbor_port_association.service
          ##sudo systemctl status home.service
          echo "###########################################################"
          sleep 1
       else
          echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
          echo "update.sh  ERROR706.023.  Neighbor-port-association SERVICE failed to copy to system.d"  >> $TARPNCOMMANDLOGFILE
          resume_services
          echo "ERROR706.023! Neighbor-Port-Assocation SERVICE file failed"
          echo "              to copy to /etc/system.d/system."
          echo "              Please send a missive about this to tarpn@groups.io"
          echo "              Include the terminal output from this update."
          echo "ERROR706.023: Aborting"
          exit 1;
       fi

       ### put a token in the etc directory indicating that this version of npa was installed.
       echo $(date) "" > npa_installed.002
       sudo mv npa_installed.002 /usr/local/etc
    fi
fi
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################

uptime


########################### TARPN-MON executable ###########################################################################################################
########################### TARPN-MON executable ###########################################################################################################
########################### TARPN-MON executable ###########################################################################################################


TARPN_MON_SERVICE_PATH_AND_FILE="/etc/systemd/system/tarpn_mon.service";
### defined at top ### TARPN_MON_SERVICE_FILE="tarpn_mon.service";
TARPN_MON_SERVICE_DOWNLOAD_NAME="tarpn-mon-service.txt";
TARPN_MON_SCRIPT_NAME="tarpnmon-runner.sh"
TARPN_MON_SCRIPT_PATH_AND_NAME="/usr/local/sbin/tarpnmon-runner.sh"


echo " "
echo " "
echo " "
echo "###### Updating WA2M TARPN-MON web app."
echo " "

##### Create TARPN MON Log
echo "Create the tarpn-mon log file if it doesn't already exist"

if [ -e $TARPNMON_RUNNER_LOG ];
then
    echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
    echo "TARPN UPDATE -- tarpn_mon.log file already exists"  >> $TARPNMON_RUNNER_LOG
    echo "tarpn_mon.log file already exists."
else
    echo "TARPN UPDATE -- creating tarpn_mon.log file"
    echo "TARPN UPDATE -- creating tarpn_mon.log file" > tarpnmon-runner-temp.log
    sudo mv tarpnmon-runner-temp.log $TARPNMON_RUNNER_LOG
    sudo chmod 666 $TARPNMON_RUNNER_LOG
    sudo chown root $TARPNMON_RUNNER_LOG
    echo -ne $(date) "" > $TARPNMON_RUNNER_LOG
    echo "Created" $TARPNMON_RUNNER_LOG >> $TARPNMON_RUNNER_LOG
    echo "Created" $TARPNMON_RUNNER_LOG
fi



#### download a current copy of the tarpnmon-runner script
echo "Get the latest runner script for tarpn-mon first and install it."

cd /home/pi
sudo rm -rf tarpn-mon-install-temp-directory
mkdir tarpn-mon-install-temp-directory
cd tarpn-mon-install-temp-directory

tarpnget tarpnmon-runner.sh
if [ -f tarpnmon-runner.sh ];
then
    chmod +x tarpnmon-runner.sh
    sudo mv tarpnmon-runner.sh /usr/local/sbin/tarpnmon-runner.sh
    echo "The current runner script from the repository has been installed."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.044. Cound not acquire tarpnmon-runner script from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "#### ERROR706.044"
    echo "#### Something is wrong.  I had access to TARPN server but could"
    echo "#### not acquire the tarpnmon-runner script from TARPN server.  "
    echo "#### Abort"
    exit 1;
fi



### see if we have a version of tarpn-mon installed already.
### if so, read it's version string and save it.
### If not, make a fake [old] version string.

echo "Now check the status of our installed tarpn-mon webapp."

if [ -f /usr/local/sbin/tarpn-mon ];
then
    tarpn-mon -version > tarpn-mon-existing-version.txt
    echo "installed already, we have version " $(cat tarpn-mon-existing-version.txt)
else
    echo "no tarpn-mon installed.  This will be a new install, then."
    echo "Non existant pre-installed version will be called 0.00.0"
    echo "0.00.0" > tarpn-mon-existing-version.txt
fi
echo " "

#### download the version string for the (potentially) new version of tarpn-mon
tarpnget tarpn-mon-version.txt                                                          ############### GET TARPN-MON-VERSION.TXT
if [ -f tarpn-mon-version.txt ];
then
    cp tarpn-mon-version.txt tarpn-mon-new-version.txt
    cp tarpn-mon-version.txt tarpn-mon-new-test-version.txt
    echo " " >> tarpn-mon-new-test-version.txt
    echo " " >> tarpn-mon-new-test-version.txt
    cp tarpn-mon-existing-version.txt tarpn-mon-existing-test-version.txt
    echo " " >> tarpn-mon-existing-test-version.txt
    echo " " >> tarpn-mon-existing-test-version.txt
    DIFF=$(diff -qbZB tarpn-mon-existing-test-version.txt tarpn-mon-new-test-version.txt | wc -c)
    if [ $DIFF -ne 0 ];
    then
        echo "The web-site has a new version of WA2M tarpn-mon which is version  " $(cat tarpn-mon-new-version.txt)
        echo "The version of WA2M tarpn-mon we have installed already is version " $(cat tarpn-mon-existing-version.txt)
        sudo rm -rf __MACOSX
        tarpnget tarpn-mon.linux-arm32.zip                                            ############### GET TARPN-MON.LINUX-ARM32.ZIP

        if [ -f tarpn-mon.linux-arm32.zip ];
        then
            unzip tarpn-mon.linux-arm32.zip
            sudo rm -rf __MACOSX
            rm -rf tarpn-mon-linux-arm32.zip
            mv tarpn-mon.linux-arm32 tarpn-mon
            chmod +x tarpn-mon
            sudo rm -f /usr/local/sbin/tarpn-mon
            sudo mv tarpn-mon /usr/local/sbin/tarpn-mon
        else
            echo "We are unable to download new version of WA2M tarpn-mon from the website."
            echo "We'll be sticking with the old version for now."
        fi
    else
        echo "The web-site has a version of WA2M tarpn-mon which is version  " $(cat tarpn-mon-new-version.txt)
        echo "This is the current version.  We're leaving the install of tarpn-mon alone."
    fi
    cd /home/pi
else
    echo "I was unable to download the WA2M tarpn-mon version statement file."
    echo "We'll be leaving tarpn-mon alone for the moment. "
fi
sudo rm -rf /home/pi/tarpn-mon-install-temp-directory


uptime


############### TARPN-MON service
############### TARPN-MON service
############### TARPN-MON service


echo
echo "See if we need to install the systemd SERVICE for TARPN-MON."

cd ~
sudo rm -rf download_temp_folder
mkdir download_temp_folder
cd download_temp_folder

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then

    if [ -e $TARPN_MON_SERVICE_PATH_AND_FILE ];
    then
        echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
        echo "TARPN UPDATE: tarpn-mon service is already installed" >> $TARPNMON_RUNNER_LOG
        echo "tarpn-mon service is already installed"
        echo "There is only one version (so far) of the service, so leave it alone."
    else
        echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
        echo "TARPN UPDATE is installing tarpn-mon service" >> $TARPNMON_RUNNER_LOG
        echo "##### installing tarpn-mon service"

       cd ~/download_temp_folder
       tarpnget $TARPN_MON_SERVICE_DOWNLOAD_NAME

       ##### now tarpn-mon-service.txt should exist in the home directory
        if [ -f $TARPN_MON_SERVICE_DOWNLOAD_NAME ];
        then
            mv $TARPN_MON_SERVICE_DOWNLOAD_NAME $TARPN_MON_SERVICE_FILE
            sudo mv $TARPN_MON_SERVICE_FILE $TARPN_MON_SERVICE_PATH_AND_FILE
            ### Start TARPN-MON service from the OS
            sudo systemctl daemon-reload
            sudo systemctl enable $TARPN_MON_SERVICE_FILE

            echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
            echo "TARPN UPDATE: tarpn-mon-service is enabled - waiting for start."  >> $TARPNMON_RUNNER_LOG
            echo "tarpn-mon-service is enabled - waiting for start."
        else
            echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
            echo "TARPN UPDATE: ERROR706.098.  tarpn-mon-service.txt failed to download."  >> $TARPNMON_RUNNER_LOG
            echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
            echo "TARPN UPDATE: ERROR706.098.  tarpn-mon-service.txt failed to download."  >> $TARPNCOMMANDLOGFILE
            echo "calling resume services and then exit the update command."

            resume_services
            echo "ERROR706.098!  Outputting debug information to be relayed to he who debugs."
            ls -lrat
            pwd
            echo "url"
            echo $_source_url
            echo "ERROR706.098!  Failed to obtain tarpn-mon-service.txt from the web server."
            echo "        please send a missive about this to tarpn@groups.io"
            echo "        Include the terminal output from this update."
            echo "ERROR706.098: Aborting"
            exit 1
        fi

    fi
fi

#### If tarpn-mon service is installed, update the tarpn mon runner script, regardless of whether we already have a tarpn mon runner script
if [ -f $TARPN_MON_SERVICE_PATH_AND_FILE ];
then
    ### Download files related to automatic operation
    tarpnget $TARPN_MON_SCRIPT_NAME
    if [ -f $TARPN_MON_SCRIPT_NAME ];
    then
        sudo chmod +x $TARPN_MON_SCRIPT_NAME
        sudo mv $TARPN_MON_SCRIPT_NAME $TARPN_MON_SCRIPT_PATH_AND_NAME
        echo "##### TARPN-MON-RUNNER file installed"

        ##sudo systemctl status home.service
        echo "###########################################################"
        echo
        echo
        echo
        sleep 1
    else
        echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
        echo "update.sh  ERROR706.099.  TARPN-MON SERVICE failed to copy to system.d"  >> $TARPNCOMMANDLOGFILE
        resume_services
        echo "ERROR706.099! TARPN-MON SERVICE file failed"
        echo "              to copy to /etc/system.d/system."
        echo "              Please send a missive about this to tarpn@groups.io"
        echo "              Include the terminal output from this update."
        echo "ERROR706.099: Aborting"
        exit 1;
    fi
fi

cd ~
rm -rf download_temp_folder

######### Done with TARPN-MON service ###################################################################
######### Done with TARPN-MON service ###################################################################
######### Done with TARPN-MON service ###################################################################


uptime



######### Update the Fix-VNC-Headless script
rm -f /home/pi/fix-vnc-headless.sh
tarpnget fix-vnc-headless.sh
if [ -f /home/pi/fix-vnc-headless.sh ];
then
   chmod +x /home/pi/fix-vnc-headless.sh
   sudo chown root /home/pi/fix-vnc-headless.sh
   sudo mv /home/pi/fix-vnc-headless.sh /usr/local/sbin/fix-vnc-headless.sh
   echo "### Updated fix-vnc-headless.sh"
   rm -f /home/pi/fix-vnc-headless.sh
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.032.  failure getting fix-vnc-headless.SH script from TARPN server."  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.032  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the fix-vnc-headless.sh script from TARPN server. "
    echo "              Post to tarpn@groups.io including this error message."
    echo "              Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi

uptime


#### Install BPQ Services, custom scripts and whatnot

if [ -f /usr/local/etc/custom-bpq-commands-services.002 ];
then
   echo "### version 002 BPQ custom commands SERVICES already installed"
else
    echo " "
    echo "CUSTOM-BPQ-COMMANDS.002 not installed. Doing so now."
    ### if there are already changes for .001, blow them away so we can act like we're starting with a fresh system.
    if [ -f /usr/local/etc/custom-bpq-commands-services.001 ];
    then
       echo "### we already had version 001, so turn off all of the 001 features of the services file"
       sudo rm -f /home/pi/services-copy
       cp /etc/services /home/pi/services-copy                                            ## copy the services OS file to our local folder
       sudo sed -i 's/custom-bpq-commands-services-001/cus##tom-b##pq-comm##ands-servi##ces-0##01/g' /home/pi/services-copy
       sudo sed -i 's/trr     63000/###trr     63##000/g' /home/pi/services-copy
       sudo sed -i 's/linux   63001/###linux   630##01/g' /home/pi/services-copy
       sudo sed -i 's/tchat   63002/###tchat   63##002/g' /home/pi/services-copy
       sudo sed -i 's/tinfo   63003/###tinfo   63##003/g' /home/pi/services-copy
       sudo chown root /home/pi/services-copy                                             ## make our copy of services look like the original root ownership
       sudo chgrp root /home/pi/services-copy                                             ## make our copy of services look like the original root group
       sudo mv /home/pi/services-copy /etc/services
    fi
    if grep -q "63000" /etc/services; then
       echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
       echo "update.sh  ERROR706.022.  Port 63000 already present in /etc/services.  FAIL"  >> $TARPNCOMMANDLOGFILE
       echo "### Contact tarpn@groups.io - this is a bug."
       resume_services
       echo "### ERROR706.022  fail in CUSTOM-BPQ-COMMANDS."
       echo "###               Note: port 63000 already present in /etc/services"
       echo "###               Contact tarpn@groups.io  -- this is a bug."
       exit 1;
    fi
    tarpnget custom-bpq-commands-services.002
    if [ -f custom-bpq-commands-services.002 ];
    then
       cp /etc/services /home/pi/services-copy                                            ## copy the services OS file to our local folder
       sudo cat /home/pi/custom-bpq-commands-services.002 >> /home/pi/services-copy       ## add the /etc/services info for BPQ command extension
       sudo chown root /home/pi/services-copy                                             ## make our copy of services look like the original root ownership
       sudo chgrp root /home/pi/services-copy                                             ## make our copy of services look like the original root group
       sudo mv /home/pi/services-copy /etc/services                                       ## put the new version of services back to the /etc directory where it lives
       sudo touch /usr/local/etc/custom-bpq-commands-services.002       ## add the flag-file to tell us not to install this again
       echo "### version 002 BPQ custom commands SERVICES now newly installed"
       echo " "
    else
       echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
       echo "update.sh  ERROR706.021.  Port 63000 already present in /etc/services."  >> $TARPNCOMMANDLOGFILE
       resume_services
       echo "### ERROR706.021: Fail in CUSTOM-BPQ-COMMANDS in retrieving the /etc/services details from tarpn.com"
       echo "###               Contact tarpn@groups.io  -- this is a bug."
       exit 1;
    fi
fi


if [ -f /usr/local/etc/custom-bpq-commands-inetd.004 ];
then
   echo "### version 004 BPQ custom commands INETD already installed"
else
    echo "Version 004 BPQ custom commands INETD not installed. Doing so now."
    tarpnget custom-bpq-commands-inetd.004
    if [ -f custom-bpq-commands-inetd.004 ];
    then
       if [ -f /etc/inetd.conf ];                                                          ## see if there is already an inetd.conf.
       then
           sudo rm -f /etc/inetd.conf                                             ## yes.  blow it away
       fi
       sudo rm -f /home/pi/inetdconf-copy
       sudo mv /home/pi/custom-bpq-commands-inetd.004 /home/pi/inetdconf-copy       ## add the /etc/inetd.conf reconfig info for BPQ command extension
       sudo chown root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root ownership
       sudo chgrp root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root group
       sudo mv /home/pi/inetdconf-copy /etc/inetd.conf                  ## put the new version of inetd.conf back to the /etc directory where it lives
       sudo touch /usr/local/etc/custom-bpq-commands-inetd.004          ## add the flag-file to tell us not to install this again
       sudo /etc/init.d/xinetd restart                                  ## kick the xinetd service so it uses our new stuff
       echo "### version 004 BPQ custom commands INETD now newly installed"
    else
       echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
       echo "update.sh ERROR706.020.  Fail in version 004 BPQ custom commands INETD."  >> $TARPNCOMMANDLOGFILE
       resume_services
       echo "ERROR706.020: Fail in version 004 BPQ custom commands INETD in retrieving"
       echo "              the /etc/inetd details from tarpn.com"
       echo "              Contact tarpn@groups.io  -- this is a bug."
       exit 1;
    fi
fi


rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*

echo " "
echo " "
echo " "

uptime


######### Update the Linux script
rm -f /home/pi/linux.sh
tarpnget linux.sh
if [ -f /home/pi/linux.sh ];
then
   chmod +x linux.sh
   sudo chown root linux.sh
   sudo mv /home/pi/linux.sh /usr/local/sbin/linux.sh
   if [ -d /home/pi/bpq-extensions ];
   then
        echo "bpq-extensions folder is present"
   else
        echo "### Created bpq-extensions folder"
        mkdir /home/pi/bpq-extensions
        sudo chown pi /home/pi/bpq-extensions
   fi
   echo "### Updated linux.sh"
   rm -f /home/pi/linux.sh
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.019.  failure getting Linux.SH script from TARPN server."  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.019  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the linux.sh script from TARPN server. "
    echo "              Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi

uptime

######### Update the TRR script
sudo rm -f /usr/local/sbin/w4eip_link_quality*
sudo rm -f /usr/local/sbin/tr
sudo rm -f /usr/local/sbin/trr
rm -f trr.sh*
tarpnget trr.sh
if [ -f trr.sh ];
then
   chmod +x trr.sh
   sudo chown root trr.sh
   sudo mv trr.sh /usr/local/sbin/trr.sh
   echo "### Updated trr.sh"
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.018.  Failure getting trr.sh script from TARPN server."  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.018  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the trr.sh script from TARPN server. "
    echo "              Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi
rm -f trr.sh

######### Update the TRR application
sudo rm -f get_tr.sh
sudo rm -f w4eip_link_quality*
sudo rm -f trr*

tarpnget w4eip_link_quality.txt

if [ -f w4eip_link_quality.txt ];
then
    chmod +x w4eip_link_quality.txt
    sudo mv w4eip_link_quality.txt /usr/local/sbin/trr
    echo "##### w4eip_link_quality.txt command has been updated."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.017. Cound not acquire the w4eip_link_quality.txt script from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.017 Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the w4eip_link_quality.txt script from TARPN server.  "
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi
uptime

######### Update the TINFO application
sudo rm -f tinfo.sh*

tarpnget tinfo.sh

if [ -f tinfo.sh ];
then
    chmod +x tinfo.sh
    sudo rm -f /usr/local/sbin/tinfo.sh
    sudo mv tinfo.sh /usr/local/sbin/tinfo.sh
    echo "##### TINFO script has been updated."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.016. Cound not acquire TINFO.SH from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.016 Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the TINFO.SH script from TARPN server.  "
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi

uptime


######### Update logfiletruncate.sh
sudo rm -f logfiletruncate.sh*

tarpnget logfiletruncate.sh

if [ -f logfiletruncate.sh ];
then
    chmod +x logfiletruncate.sh
    sudo rm -f /usr/local/sbin/logfiletruncate.sh
    sudo mv logfiletruncate.sh /usr/local/sbin/logfiletruncate.sh
    echo "##### logfiletruncate.sh script has been updated."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.101. Cound not acquire logfiletruncate.sh script from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "#### ERROR706.101"
    echo "#### Something is wrong.  I had access to TARPN server but could"
    echo "#### not acquire the logfiletruncate.sh script from TARPN server.  "
    echo "#### Abort"
    exit 1;
fi

uptime






######### Update the NODE-CALLS-LINKTEST script
echo " "
echo " "
echo " "
echo "###### Updating the utility used by the node to call LINKTEST."
echo " "

sudo rm -f node_calls_linktest.sh*

tarpnget node_calls_linktest.sh

if [ -f node_calls_linktest.sh ];
then
    chmod +x node_calls_linktest.sh
    sudo rm -f /usr/local/sbin/node_calls_linktest.sh
    sudo mv node_calls_linktest.sh /usr/local/sbin/node_calls_linktest.sh
    echo "##### NODE_CALLS_LINKTEST script has been updated."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.015. Cound not acquire NODE_CALLS_LINKTEST script from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "#### ERROR706.015"
    echo "#### Something is wrong.  I had access to TARPN server but could"
    echo "#### not acquire the NODE_CALLS_LINKTEST script from TARPN server.  "
    echo "#### Abort"
    exit 1;
fi
uptime

echo " "
echo " "
echo "Update the l4listen utility"
echo " "



######### Update the l4listen program
rm -f l4listen*
tarpnget l4listen.zip
if [ -f l4listen.zip ];
then
   unzip l4listen.zip
   sudo mv l4listen /usr/local/sbin/l4listen
   echo "### Updated l4listen"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.031. Cound not acquire l4listen.zip from TARPN server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "#### ERROR706.031"
   echo "### l4listen.zip failed to download.  This is a bug."
   echo "### complain to tarpn@groups.io"
   echo " "
   exit 1
fi
rm -f l4listen.zip

echo " "
uptime
echo " "
echo "Update the flashTNC Python script"
echo " "
######### Update the flashtnc.py program
rm -f flashtnc.py*
tarpnget flashtnc.py
if [ -f flashtnc.py ];
then
   chmod +x flashtnc.py
   sudo chown root flashtnc.py
   sudo mv flashtnc.py /usr/local/sbin/flashtnc.py
   echo "### Updated flashtnc.py"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.015. Cound not acquire flashtnc.py from TARPN server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "#### ERROR706.015"
   echo "### flashtnc.py failed to download.  This is a bug."
   echo "### complain to tarpn@groups.io"
   echo " "
   exit 1
fi
rm -f flashtnc.py
uptime


######### Update the get_tnc_version.py program
rm -f get_tnc_version.py*
tarpnget get_tnc_version.py
if [ -f get_tnc_version.py ];
then
   chmod +x get_tnc_version.py
   sudo chown root get_tnc_version.py
   sudo mv get_tnc_version.py /usr/local/sbin/get_tnc_version.py
   echo "### Updated get_tnc_version.py"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.014. Cound not acquire get_tnc_version.py from TARPN server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "#### ERROR706.014"
   echo "#### get_tnc_version.py failed to download.  This is a bug."
   echo "#### complain to tarpn@groups.io"
   echo " "
   exit 1
fi
rm -f get_tnc_version.py


uptime


############## Create the ninotnc versions directory
if [ -d /usr/local/etc/ninotnc ];
then
     echo "### NinoTNC directory is present"
else
     sudo mkdir /usr/local/etc/ninotnc
     if [ -d /usr/local/etc/ninotnc ];
     then
          echo "### created ninotnc directory"
     else
          echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
          echo "update.sh  ERROR706.012  Cound not create NinoTNC directory"  >> $TARPNCOMMANDLOGFILE
          resume_services
          echo "#### ERROR706.012"
          echo "#### FAILURE creating NinoTNC directory"
          echo "#### Please complain to tarpn@groups.io"
          exit 1
     fi
fi

if [ -d /usr/local/etc/ninotnc/versions ];
then
     echo "### NinoTNC Versions directory is present"
else
     sudo mkdir /usr/local/etc/ninotnc/versions
     if [ -d /usr/local/etc/ninotnc/versions ];
     then
          echo "### created Ninotnc Versions directory"
     else
          echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
          echo "update.sh   ERROR706.011   Cound not create NinoTNC Versions directory"  >> $TARPNCOMMANDLOGFILE
          resume_services
          echo "#### ERROR706.011"
          echo "FAILURE creating Ninotnc Versions directory"
          echo "Please complain to tarpn@groups.io"
          exit 1
     fi
fi


############## Get the latest NinoTNC firmware
cd ~
rm -f latest_ninotnc.*
rm -rf temp_latest_ninotnc
sudo rm -rf /usr/local/etc/ninotnc/versions/latest_ninotnc
tarpnget latest_ninotnc.zip
if [ -f latest_ninotnc.zip ];
then
    mkdir temp_latest_ninotnc
    cd temp_latest_ninotnc
    unzip -q /home/pi/latest_ninotnc.zip
    rm -rf *MACOSX
    echo "downloaded NinoTNC program file(s): "
    ls -1
    sudo mv * /usr/local/etc/ninotnc/versions
    cd ..
    rm -rf latest_ninotnc
    cd ..
    rm -f latest_ninotnc.zip
    rm -rf temp_latest_ninotnc
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.010 No NinoTNC code versions available"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "#### ERROR706.010"
    echo "No NinoTNC code versions available."
    echo "### This is a bug."
    echo "### Complain to tarpn@groups.io"
    echo " "
    exit 1
fi
cd ~
rm -f latest_ninotnc.*

echo " "
echo " "
echo " "


uptime





############# Fix timeout on VNC to a large number
if [ -f /etc/vnc/config.d/common ];
then
   ####### VNC configuration exists.   See if the custom one already exists.
   if [ -f /etc/vnc/config.d/common.custom ];
   then
      echo "# VNC custom config already exists.  leaving it alone."
      echo
      echo
   else
      rm -f common.custom
      echo "#### VNC custom config does not exist.  We'll create one with a really long timeout."
      echo "IdleTimeout=86400000" > common.custom
      echo "" >> common.custom
      sudo mv common.custom /etc/vnc/config.d/common.custom
      sudo chown root /etc/vnc/config.d/common.custom
      sudo chgrp root /etc/vnc/config.d/common.custom
      sudo chmod 644 /etc/vnc/config.d/common.custom
      echo
      echo
   fi
fi





############ UPDATE tarpn
cd /home/pi
tarpnget tarpn
if [ -f tarpn ];
then
    chmod +x tarpn
    sudo mv tarpn /usr/local/sbin/tarpn
    echo "##### TARPN command has been updated."
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.009. could not get new tarpn script - Aborting"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "ERROR706.009  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the tarpn script from the TARPN server.  "
    echo "              Abort, old TARPN script is intact."
    echo
    echo "##### Aborting"
    exit 1;
fi


uptime


#### Disable the console GETTY service
## echo "##### Stop console GETTY in config.txt"
## sudo systemctl stop serial-getty@ttyAMA0.service
## sudo systemctl disable serial-getty@ttyAMA0.service

echo "##### Disable console GETTY in config.txt"
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt



########## Test to see if python configparser is present.
#### If not, just exit.  We need configparser for tarpn home and that must be added by tarpn updateapps.
echo "##### checking for python-configparser"

sudo rm -f /home/pi/home_test_file.txt
dpkg-query -W -f='${binary:Package} ${Version}\t${Maintainer}\n' python-configparser | wc -l  > /home/pi/home_test_file.txt;
_count=$( cat /home/pi/home_test_file.txt );
sudo rm -f /home/pi/home_test_file.txt
_value=1
if [ $_value -ne $_count ]; then
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "ERROR. Python ConfigParser not present"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "###### ERROR706.008: python configparser not present.  "
    echo "######               Please fix by running   tarpn updateapps. "
    echo
    echo "##### Aborting"
    exit 1;
else
    echo "##### python-configparser is present.  Moving on."
fi

uptime



############ UPDATE runbpq.sh
cd /home/pi
tarpnget runbpq.sh
if [ -f runbpq.sh ];
then
    echo "##### received RUNBPQ - BPQ node execution script"
    chmod +x runbpq.sh
    sudo killall runbpq.sh
    sudo mv runbpq.sh /usr/local/sbin/runbpq.sh
    echo "##### BPQ node execution script has been updated."
else
     echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
     echo "update.sh  ERROR706.007. Did not receive RUNBPQ from TARPN server"  >> $TARPNCOMMANDLOGFILE
     resume_services
     echo "##### ERROR706.007    Did not receive RUNBPQ."
     echo
     echo "##### Abort -- complain to tarpn@groups.io."
     exit 1
fi

echo " "
echo " "
uptime
echo " "
echo " "
########### UPDATE rx_tarpnstatapp application
cd /home/pi
echo "ignore the no-process-found missive if printed here:"
sudo killall rx_tarpnstatapp
rm -f rx_tarpnstatapp*

cd zip-temp
tarpnget rx_tarpnstatapp.zip
if [ -f rx_tarpnstatapp.zip ];
then
    echo "##### received rx_tarpnstatapp  zip file"
    unzip rx_tarpnstatapp.zip
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.006. rx_tarpnstatapp.zip not available from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    pwd
    ls -lrats
    echo "##### ERROR706.006   Did not receive rx_tarpnstatapp.zip file.  FAIL FAIL FAIL"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi

if [ -f rx_tarpnstatapp ];
then
    echo "##### received and unzipped rx_tarpnstatapp Application"
    chmod +x rx_tarpnstatapp
    ./rx_tarpnstatapp version
    sudo mv rx_tarpnstatapp /usr/local/sbin/rx_tarpnstatapp
    echo -e "##### rx_tarpnstatapp application has been updated.\n"
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.005. rx_tarpnstatapp not available from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    pwd
    ls -lrats
    echo "##### ERROR706.005   Unable to unzip rx_tarpnstatapp!  FAIL FAIL FAIL"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi

echo " "
echo " "
uptime
echo " "
echo " "


############################# UPDATE BBS-CHECKER APPLICATION FROM ZIP FILE

sudo killall bbs_checker

cd /home/pi/zip-temp

tarpnget bbs_checker.zip
##### now bbs_checker.zip should exist in the zip-temp directory
if [ -f /home/pi/zip-temp/bbs_checker.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.004.  Failed to obtain bbs_checker.zip from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.004! Failed to obtain bbs_checker.zip from the web server."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.004: Aborting"
   exit 1
fi

unzip bbs_checker.zip

if [ -f /home/pi/zip-temp/bbs_checker ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.003.  Error in unzipping bbs_checker.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.003! Error in unzipping bbs_checker.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.003: Aborting"
   exit 1
fi

echo "##### received bbs_checker  application"
chmod +x bbs_checker
sudo mv bbs_checker /usr/local/sbin/bbs_checker
echo "##### bbs_checker application has been updated."

### old ### ########### UPDATE bbs_checker application
### old ### cd /home/pi/zip
### old ### rm -f bbs_checker*
### old ### sudo killall bbs_checker
### old ###
### old ### wget -o /dev/null $_source_url/bbs_checker
### old ### if [ -f bbs_checker ];
### old ### then
### old ###     echo "##### received bbs_checker  application"
### old ###     chmod +x bbs_checker
### old ###     sudo mv bbs_checker /usr/local/sbin/bbs_checker
### old ###     echo -e "##### bbs_checker application has been updated.\n"
### old ### else
### old ###     echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
### old ###     echo "ERROR3b. Did not receive bbs_checker from TARPN server"  >> $TARPNCOMMANDLOGFILE
### old ###     resume_services
### old ###     echo "##### ERROR3b   Did not receive bbs_checker.  Leaving current copy alone"
### old ###     echo
### old ###     echo "##### Abort -- complain to tarpn@groups.io."
### old ###     exit 1
### old ### fi


###################### DONE WITH BBS-CHECKER APPLICATION from ZIP FILE
uptime

############################# UPDATE SENDROUTESTOCQ APPLICATION FROM ZIP FILE

sudo killall sendroutestocq

cd /home/pi/zip-temp

tarpnget sendroutestocq.zip
##### now sendroutestocq.zip should exist in the zip-temp directory
if [ -f /home/pi/zip-temp/sendroutestocq.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.002.  Failed to obtain SENDROUTESTOCQ.zip from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.002! Failed to obtain SENDROUTESTOCQ.zip from the web server."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.002: Aborting"
   exit 1
fi

unzip sendroutestocq.zip

if [ -f /home/pi/zip-temp/sendroutestocq ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.001.  Error in unzipping SENDROUTESTOCQ.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.001! Error in unzipping SENDROUTESTOCQ.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.001: Aborting"
   exit 1
fi

echo "##### received SENDROUTESTOCQ  application"
chmod +x sendroutestocq
sudo mv sendroutestocq /usr/local/sbin/sendroutestocq
echo "##### SENDROUTESTOCQ application has been updated."


### old ### ########### UPDATE sendroutestocq application
### old ### rm -f sendroutestocq
### old ### sudo killall sendroutestocq
### old ### wget -o /dev/null $_source_url/sendroutestocq
### old ### if [ -f sendroutestocq ];
### old ### then
### old ###     echo "##### received SENDROUTESTOCQ  application"
### old ###     chmod +x sendroutestocq
### old ###     sudo mv sendroutestocq /usr/local/sbin/sendroutestocq
### old ###     echo -e "##### SENDROUTESTOCQ application has been updated.\n"
### old ### else
### old ###     echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
### old ###     echo "ERROR4a. SENDROUTESTOCQ not available from TARPN server"  >> $TARPNCOMMANDLOGFILE
### old ###     resume_services
### old ###     echo "##### ERROR4a   Did not receive sendroutestocq.  Leaving current copy alone"
### old ###     echo
### old ###     echo "##### Abort -- complain to tarpn@groups.io."
### old ###     exit 1
### old ### fi

###################### DONE WITH SENDROUTESTOCQ APPLICATION from ZIP FILE


uptime



########### UPDATE configure_node_ini.sh
cd /home/pi
rm -f configure_node_ini.sh*
tarpnget configure_node_ini.sh
if [ -f configure_node_ini.sh ];
then
    echo "##### received CONFIGURE-NODE  command script"
    chmod +x configure_node_ini.sh
    sudo mv configure_node_ini.sh /home/pi/bpq/configure_node_ini.sh
    echo -e "##### CONFIGURE-NODE script has been updated.\n"
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR705.001. CONFIGURE-NODE not available from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "##### ERROR705.001   Did not receive CONFIGURE-NODE.  Leaving current copy alone"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi


echo " "
uptime
echo " "
echo "Download the latest version of the NC4FG TARPN-HOME updater script."
echo " "



####### UPDATE the NC4FG TARPN-HOME UPDATER script
sudo rm -rf tarpn-home-update.*
tarpnget tarpn-home-update.sh
if [ -f tarpn-home-update.sh ];
then
    echo "##### received NC4FG TARPN-HOME UPDATER script"
    chmod +x tarpn-home-update.sh
    sudo mv tarpn-home-update.sh /usr/local/sbin
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "tarpn-update: Updated the tarpn-home-update script" >> $HOME_LOGFILE
    echo "Use the command     tarpn home update    to get the latest version"
    echo "of NC4FG TARPN-HOME. "
    echo " "
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR705.002. TARPN-HOME UPDATER not available from TARPN server"  >> $TARPNCOMMANDLOGFILE
    resume_services
    ls -lrats
    echo "##### ERROR705.002   Did not receive TARPN-HOME UPDATER script. "
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1;
fi



######## Stop the TARPN-HOME application

################ NC4FG -- HOME
echo "##### Stopping NC4FG TARPN-HOME in preparation"
echo "##### for updating tarpn scripting and utilities."
if [ -d /tmp/tarpn ]; then
   if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
     echo -ne $(date) "" >> $HOME_LOGFILE
     echo "tarpn-update: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
     sudo rm -rf /tmp/tarpn/tarpn_home_go.flag          ## added log entry
     sleep 2
   fi
fi
uptime

check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "##### 5 seconds after deleting the tarpn_home_go file, tarpn-home is still running"
    sleep 15
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "##### 20 seconds after deleting the tarpn_home_go file, tarpn-home is still running"
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "##### 40 seconds after deleting the tarpn_home_go file, tarpn-home is still running"
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "##### 60 seconds after deleting the tarpn_home_go file, tarpn-home is still running"
    sleep 20
fi

check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "##### 80 seconds after deleting the tarpn_home_go file, tarpn-home is still running"
    echo "##### doing a killall python"
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "tarpn-update: TARPN HOME didn't quit nicely.  Doing KILLALL PYTHON" >> $HOME_LOGFILE
    sudo killall python
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "tarpn-update: FAIL trying to get TARPN-HOME to quit.  Complain to tarpn@groups.io" >> $HOME_LOGFILE
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "tarpn-update: ERROR705.003 trying to get TARPN-HOME to quit"  >> $TARPNCOMMANDLOGFILE
    resume_services
    echo "#### ERROR705.003  FAIL FAIL in the process of stopping TARPN HOME"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi
echo "##### NC4FG TARPN-HOME is stopped"
echo -ne $(date) "" >> $HOME_LOGFILE
echo "tarpn-update: TARPN-HOME is stopped" >> $HOME_LOGFILE

uptime









########## Get chatconfig.cfg if it doesn't exist
cd /home/pi/bpq
echo "#### Check chatconfig.cfg"
if [ -f chatconfig.cfg ];
then
    echo "#### chatconfig.cfg already exists.  Check for app#"
    if grep -q "ApplNum = 0" chatconfig.cfg;
    then
       echo "#### bad app# in chatconfig.  Delete it."
       sudo rm -r chatconfig.cfg
    fi
fi


if [ -f chatconfig.cfg ];
then
    echo "#### chatconfig.cfg already exists.  Leave it alone"
else
    echo "##### chatconfig.cfg is missing.  Getting it now."

    tarpnget chatconfig.cfg
    if [ -f chatconfig.cfg ];
    then
       echo "##### chatconfig.cfg is now installed."
    else
       echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
       echo "tarpn-update: ERROR705.004 trying to download chatconfig.cfg"  >> $TARPNCOMMANDLOGFILE
       resume_services
       pwd
       ls -lrats
       echo "##### ERROR705.004 chatconfig.cfg failed to download.  ABORT! "
       echo "##### Abort -- complain to tarpn@groups.io."
       exit 1
    fi
fi
cd /home/pi


uptime


################# get RING.WAV file

cd /home/pi
tarpnget ring.wav
sudo mv ring.wav /usr/local/sbin/ring.wav


######## UPDATE tarpn_background.sh
cd /home/pi
rm -f tarpn_background.sh*
rm -f tarpn-service.txt
rm -f tarpn.service*
echo "#### GETting tarpn background"
tarpnget tarpn_background.sh
echo "#### GETting tarpn.service"
##### WAS #### wget -o /dev/null $_source_url/tarpn.service
if [ -f tarpn_background.sh ];
then
    echo "##### received TARPN_BACKGROUND script"
    chmod +x tarpn_background.sh
    sudo killall tarpn_background.sh
    sudo mv tarpn_background.sh /usr/local/sbin/tarpn_background.sh
    echo "##### TARPN_BACKGROUND script has been updated."
    sleep 1
else
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo "update.sh  ERROR706.047 trying to download TARPN_BACKGROUND"  >> $TARPNCOMMANDLOGFILE
    resume_services
    pwd
    ls -lrats
    echo "##### ERROR706.047   Did not receive TARPN_BACKGROUND. "
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1;
fi


if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
    tarpnget tarpn-service.txt
    if [ -f tarpn-service.txt ];
    then
        echo "##### received TARPN.SERVICE configuration file"
        #### rename the service file from what the developer needs to what the Raspberry PI needs
        mv tarpn-service.txt tarpn.service
        echo "##### moving new background shell script file into place"
        echo "##### systemctl daemon-reload"
        sleep 1
        uptime
        sudo systemctl daemon-reload
        sleep 1
        echo "##### systemctl enable tarpn.service"
        sleep 1
        uptime
        sudo systemctl enable tarpn.service
        sleep 1
        echo "##### systemctl start tarpn.service."
        sleep 1
        uptime
        sudo systemctl start tarpn.service
        sleep 1
        echo "##### TARPN_BACKGROUND service has been reloaded and the"
        echo "##### OS has been told to resume calling it -- wait up to 16 seconds to verify."
        echo -e "\n\n\n\n"
        echo -ne $(date) "" >> $TARPN_SERVICE_LOG
        echo "### tarpn update.sh: started tarpn service"  >> $TARPN_SERVICE_LOG
        uptime
        sleep 1
        sudo rm -f /home/pi/tempparsingfile1.txt
        sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
        if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
        then
           echo "### TARPN Service has resumed after 1 second."
           uptime
        else
           sleep 2
           uptime
           sudo rm -f /home/pi/tempparsingfile1.txt
           sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
           if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
           then
              echo "### TARPN Service has resumed after 3 seconds."
              uptime
           else
              sleep 2
              uptime
              sudo rm -f /home/pi/tempparsingfile1.txt
              sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
              if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
              then
                 echo "### TARPN Service has resumed after 5 seconds."
                 uptime
              else
                 sleep 2
                 uptime
                 sudo rm -f /home/pi/tempparsingfile1.txt
                 sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
                 if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
                 then
                    echo "### TARPN Service has resumed after 7 seconds."
                    uptime
                 else
                    sleep 2
                    uptime
                    sudo rm -f /home/pi/tempparsingfile1.txt
                    sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
                    if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
                    then
                       echo "### TARPN Service has resumed after 9 seconds."
                       uptime
                    else
                       sleep 2
                       uptime
                       sudo rm -f /home/pi/tempparsingfile1.txt
                       sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
                       if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
                       then
                          echo "### TARPN Service has resumed after 11 seconds."
                          uptime
                       else
                          sleep 3
                          uptime
                          sudo rm -f /home/pi/tempparsingfile1.txt
                          sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
                          if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
                          then
                             echo "### TARPN Service has resumed after 14 seconds."
                             uptime
                          else
                             sleep 2
                             uptime
                             sudo rm -f /home/pi/tempparsingfile1.txt
                             sudo systemctl status tarpn.service | grep --text "Active:" > /home/pi/tempparsingfile1.txt
                             if grep --text -q "active (running) since" /home/pi/tempparsingfile1.txt
                             then
                                echo "### TARPN Service has resumed after 16 seconds."
                             else
                                echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
                                echo "update.sh: ERROR706.045!  tarpn.service is not running 16 seconds after start!"   >> $TARPNCOMMANDLOGFILE
                                cat $TEMP_PARSE_FILE2 >> $TARPNCOMMANDLOGFILE
                                echo "update.sh:  end supplimental info" >> $TARPNCOMMANDLOGFILE

                                echo "##### ERROR!"
                                echo "##### update.sh: ERROR706.045!  tarpn.service is not running 16 seconds after start!"
                                cat $TEMP_PARSE_FILE2;
                                echo
                                echo "##### Do tarpn update again"
                                echo "##### If the problem persists, send a missive to tarpn@groups.io, "
                                echo "#####     or join the conversation on TARPN Discord."
                                echo "##### I'm sorry for the inconvenience!"
                                echo
                                echo "##### Additional commands of interest are:"
                                echo "##### tarpn kill          -- restarts the tarpn service background"
                                echo
                                echo "##### tarpn reboot        -- does a nice reboot of Linux"
                                echo
                                echo "##### tarpn forceshutdown -- forces a shutdown of Linux."
                                echo "#####                        Use if the Linux daemon processor is broken"
                                echo "#####                        and you are getting HALT or ABORT messages"
                                echo "##### -- ka2dew"
                                echo
                                sudo rm -f $TEMP_PARSE_FILE2
                                exit 1
                             fi
                          fi
                       fi
                    fi
                 fi
              fi
           fi
        fi

    else
        echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
        echo "update.sh  ERROR706.046 trying to download tarpn.service"  >> $TARPNCOMMANDLOGFILE
        echo "##### ERROR706.046   Did not receive TARPN.SERVICE."
        echo
        echo "##### Abort -- complain to tarpn@groups.io."
        exit 1;
    fi
fi
rm -f tarpn.service*
rm -f tarpn_background.sh*
rm -f /home/pi/tempparsingfile1.txt


uptime




########################################################################################
########################################################################################
######## SHUTDOWN SERVICE and PI_SHUTDOWN_BACKGROUND Shell script
######## Check to see if the user has the shutdown service installed.  If not, panic!
echo "##### Check PI-SHUTDOWN service and pi_shutdown_background.sh"
cd /home/pi
rm -f pi_shutdown-service.txt
rm -f pi_shutdown.service

### don't make this check if [ -f /etc/systemd/system/pi_shutdown.service ];
### don't make this check then
### don't make this check    echo "####### UPDATE  PI_SHUTDOWN.SERVICE is installed.  Check Background"
### don't make this check else
### don't make this check ###### Install shutdown service
### don't make this check    echo "##### ERROR 11a   pi_shutdown.service  was not found."
### don't make this check    echo "#####             This should be an existing service included "
### don't make this check    echo "#####             in the original TARPN install package!!!"
### don't make this check    echo
### don't make this check    echo "ERROR: Aborting"
### don't make this check    exit 1;
### don't make this check fi

######## UPDATE pi_shutdown_background.sh

### Delete a temporary downloaded copy of the script in the home pi directory.  (may be left-over from failed install)
rm -f pi_shutdown_background.sh*
rm -f gpio_for_controlpanel.sh*

### Get new copy of the script
tarpnget pi_shutdown_background.sh
tarpnget gpio_for_controlpanel.sh
tarpnget pi_shutdown-service.txt

### Check if we have the script file now.
if [ -f pi_shutdown_background.sh ];
then
   echo "##### received PI_SHUTDOWN_BACKGROUND script"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.048 trying to download PI_SHUTDOWN_BACKGROUND"  >> $TARPNCOMMANDLOGFILE
   resume_services
   pwd
   ls -lrats
   echo "##### ERROR706.048   Did not receive PI_SHUTDOWN_BACKGROUND."
   echo
   echo "##### Aborting"
   exit 1;
fi

### Check if we have the script file now.
if [ -f gpio_for_controlpanel.sh ];
then
   echo "##### received GPIO_FOR_CONTROLPANEL script"
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.049 trying to download GPIO_FOR_CONTROLPANEL"  >> $TARPNCOMMANDLOGFILE
   resume_services
   pwd
   ls -lrats
   echo "##### ERROR706.049   Did not receive GPIO_FOR_CONTROLPANEL."
   echo
   echo "##### Aborting"
   exit 1;
fi


echo "moving new background shell script file into place"
chmod +x pi_shutdown_background.sh
sudo killall pi_shutdown_background.sh
sudo mv pi_shutdown_background.sh /usr/local/sbin/pi_shutdown_background.sh
chmod +x gpio_for_controlpanel.sh
sudo mv gpio_for_controlpanel.sh /usr/local/sbin/gpio_for_controlpanel.sh
echo "PI_SHUTDOWN_BACKGROUND script has been updated."
echo "gpio_for_controlpanel script has been updated."

if [ -f pi_shutdown-service.txt ];
then
   echo "##### Got PI_SHUTDOWN-SERVICE.TXT file from web server."
else
   ls -lrats
   echo "##### ERROR706.050   Did not receive PI_SHUTDOWN-SERVICE.TXT."
   echo
   echo "##### Aborting"
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh  ERROR706.050 trying to download PI_SHUTDOWN-SERVICE.TXT"  >> $TARPNCOMMANDLOGFILE
   exit 1;
fi

#### rename the service file from what the developer needs to what the Raspberry PI needs
if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
    mv pi_shutdown-service.txt pi_shutdown.service

    sudo rm /etc/systemd/system/pi_shutdown.service
    if [ -f /etc/systemd/system/pi_shutdown.service ];
    then
       echo "#### ERROR8: pi_shutdown service did not delete. "
    else
       sudo mv ~/pi_shutdown.service /etc/systemd/system/pi_shutdown.service
       if [ -f /etc/systemd/system/pi_shutdown.service ];
       then
          echo "pi_shutdown.service has been replaced"
          echo "reload service"
          sudo systemctl daemon-reload
          echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
          echo "TARPN UPDATE: is Enabling pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
          sudo systemctl enable pi_shutdown.service
          echo "PI_SHUTDOWN_BACKGROUND script has been updated and the"
          echo "OS has been told to resume calling it."
          echo -e "\n\n\n\n"
       else
          echo "##### ERROR9: pi_shutdown.service was deleted before update but we were"
          echo "#####        unable to re-install the new copy."
          echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
          echo "update.sh  ERROR9 trying to re-install pi_shutdown.service "  >> $TARPNCOMMANDLOGFILE
          echo "##### Aborting"
          exit 1;
       fi
    fi
fi


rm -f pi_shutdown-service.txt
rm -f pi_shutdown.service*
rm -f pi_shutdown_background.sh*


echo
uptime
echo



####### RX-TARPNSTAT shell, and service file

######## Check to see if the user has the rx_tarpnstat service installed.  If not, install it.  If so, just upgraded it.
echo "##### Check RX-TARPNSTAT service and RX-TARPNSTAT.SH"
cd /home/pi
rm -f rx_tarpnstat-service.txt
rm -f rx_tarpnstat.service

if [ -f /etc/systemd/system/rx_tarpnstat.service ];
then
   ######## UPDATE RX_TARPNSTAT.sh

   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f rx_tarpnstat.sh*

   ### Get new copy of the script
   tarpnget rx_tarpnstat.sh
   tarpnget rx_tarpnstat-service.txt

   ### Check if we have the script file now.
   if [ -f rx_tarpnstat.sh ];
   then
      echo "##### received RX_TARPNSTAT.SH from web server"
      echo "##### moving new background shell script file into place"
      chmod +x rx_tarpnstat.sh
      sudo mv rx_tarpnstat.sh /usr/local/sbin/rx_tarpnstat.sh
      echo "##### RX_TARPNSTAT.SH script has been updated."
   else
      ls -lrats
      echo "##### ERROR34   Did not receive RX_TARPNSTAT.SH."
      echo
      echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
      echo "update.sh  ERROR34 trying to download RX_TARPNSTAT.SH "  >> $TARPNCOMMANDLOGFILE
      echo "##### Aborting"
      exit 1;
   fi



   if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
   then
      if [ -f rx_tarpnstat-service.txt ];
      then
         echo "##### Received RX-TARPNSTAT-SERVICE from web server"
         #### rename the service file from what the developer needs to what the Raspberry PI needs
      else
         ls -lrats
         echo "##### ERROR33   Did not receive RX_TARPNSTAT-SERVICE.TXT."
         echo
         echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
         echo "update.sh  ERROR34 trying to download RX_TARPNSTAT-SERVICE.TXT "  >> $TARPNCOMMANDLOGFILE
         echo "##### Aborting"
         exit 1;
      fi
      mv rx_tarpnstat-service.txt rx_tarpnstat.service

      sudo rm /etc/systemd/system/rx_tarpnstat.service
      if [ -f /etc/systemd/system/rx_tarpnstat.service ];
      then
         echo "#### ERROR31: RX_TARPNSTAT service did not delete. "
      else
         sudo mv ~/rx_tarpnstat.service /etc/systemd/system/rx_tarpnstat.service
         if [ -f /etc/systemd/system/rx_tarpnstat.service ];
         then
            echo "##### RX_TARPNSTAT.service has been replaced"
            echo ##### reload service
            sudo systemctl daemon-reload
            sudo systemctl enable rx_tarpnstat.service
            echo "##### RX_TARPNSTAT.SH script has been updated and the"
            echo "##### OS has been told to resume calling it."
            echo -e "\n\n\n\n"
         else
            echo "##### ERROR32: RX_TARPNSTAT.service was deleted before update but we were"
            echo "#####        unable to re-install the new copy."
            echo
            echo "##### Aborting"
            exit 1;
         fi
      fi
   fi
fi

### else
### ###### Install RX_TARPNSTAT service
###
###    ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
###    rm -f rx_tarpnstat.sh*
###    rm -f rx_tarpnstat.service
###    rm -f rx_tarpnstat-service.txt
###
###    ### Get new copy of the script
###    tarpnget rx_tarpnstat.sh
###    tarpnget rx_tarpnstat-service.txt
###
###    ### Check if we have the script file now.
###    if [ -f rx_tarpnstat.sh ];
###    then
###       echo "##### received RX_TARPNSTAT script"
###    else
###       ls -lrats
###       echo "##### ERROR37   Did not receive STATUSMONITOR_BACKGROUND."
###       echo
###       echo "##### Aborting"
###       exit 1;
###    fi
###
###    ### Check if we have the newly downloaded service file now.
###    if [ -f rx_tarpnstat-service.txt ];
###    then
###       echo "##### received RX_TARPNSTAT-SERVICE.TXT"
###    else
###       ls -lrats
###       echo "##### ERROR36   Did not receive RX_TARPNSTAT-SERVICE.TXT."
###       echo
###       echo "##### Aborting"
###       exit 1;
###    fi
###    #### rename the service file from what the developer needs to what the Raspberry PI needs
###    mv rx_tarpnstat-service.txt rx_tarpnstat.service
###
###    sudo rm /etc/systemd/system/rx_tarpnstat.service
###    if [ -f /etc/systemd/system/rx_tarpnstat.service ];
###    then
###       echo "#### ERROR8f: RX_TARPNSTAT service did not delete. "
###    else
###       sudo mv ~/rx_tarpnstat.service /etc/systemd/system/rx_tarpnstat.service
###       if [ -f /etc/systemd/system/rx_tarpnstat.service ];
###       then
###          echo "##### rx_tarpnstat.service has been replaced"
###          echo "##### moving new background shell script file into place"
###          chmod +x rx_tarpnstat.sh
###          sudo mv rx_tarpnstat.sh /usr/local/sbin/rx_tarpnstat.sh
###          echo "##### rx_tarpnstat script has been updated."
###          echo ##### reload service
###          sudo systemctl daemon-reload
###          sudo systemctl enable rx_tarpnstat.service
###          echo "##### rx_tarpnstat script has been installed and the"
###          echo "##### OS has been told to call it."
###          echo -e "\n\n\n\n"
###       else
###          echo "##### ERROR35: rx_tarpnstat.service was deleted before update but we were"
###          echo "#####        unable to re-install the new copy."
###          echo
###          echo "##### Aborting"
###          exit 1;
###       fi
###    fi
### fi
rm -f rx_tarpnstat-service.txt
rm -f rx_tarpnstat.service*
rm -f rx_tarpnstat.sh*



echo
uptime
echo




########## STATUSMONITOR SERVICE, SHELL SCRIPT and APPLICATIONS
######## Check to see if the user has the statusmonitor service installed.  If not, install it.  If so, just upgraded it.
echo "##### Check statusmonitor service and statusmonitor.sh"
cd /home/pi
######## UPDATE statusmonitor.sh
echo -e "\n\n\n\n"
### Delete a temporary downloaded copy of the script (may be left-over from failed install)

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   ### Get new copy of the service
   tarpnget statusmonitor-service.txt
   ### Check if we have the newly downloaded service file now.
   if [ -f statusmonitor-service.txt ];
   then
      echo "##### received STATUSMONITOR-SERVICE.TXT script"
      #### rename the service file from what the developer needs to what the Raspberry PI needs
      mv statusmonitor-service.txt statusmonitor.service

      sudo rm /etc/systemd/system/statusmonitor.service
      if [ -f /etc/systemd/system/statusmonitor.service ];
      then
         echo "#### ERROR8: statusmonitor service did not delete. "
      else
         sudo mv ~/statusmonitor.service /etc/systemd/system/statusmonitor.service
         if [ -f /etc/systemd/system/statusmonitor.service ];
         then
            echo "##### statusmonitor.service has been replaced"
            echo ##### reload service
            sudo systemctl daemon-reload
            sudo systemctl enable statusmonitor.service
            echo "##### STATUSMONITOR_BACKGROUND script has been updated and the"
            echo "##### OS has been told to resume calling it."
            echo -e "\n\n\n\n"
         else
            echo "##### ERROR9b.1: statusmonitor.service was deleted before update but we were"
            echo "#####           unable to re-install the new copy."
            echo
            echo "##### Aborting"
            exit 1;
         fi
      fi
   else
      ls -lrats
      echo "##### ERROR10c.1   Did not receive STATUSMONITOR-SERVICE.TXT."
      echo
      echo "##### Aborting"
      exit 1;
   fi
fi
rm -f statusmonitor.service*
rm -f statusmonitor-service*



rm -f statusmonitor.sh*

tarpnget statusmonitor.sh

### Check if we have the script file now.
if [ -f statusmonitor.sh ];
then
   echo "##### received STATUSMONITOR_BACKGROUND script"

   ### Check if we have the newly downloaded service file now.
   echo "##### moving new background shell script file into place"
   chmod +x statusmonitor.sh
   sudo mv statusmonitor.sh /usr/local/sbin/statusmonitor.sh
   echo "##### STATUSMONITOR_BACKGROUND script has been updated."
   echo -e "\n\n"
else
   ls -lrats
   echo "##### ERROR10c.2   Did not receive STATUSMONITOR.SH."
   echo
   echo "##### Aborting"
   exit 1;
fi
rm -f statusmonitor.sh*

echo
uptime
echo


######## Check to see if the user has the HOME service installed.  If not, install it.  If so, just upgraded it.
if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo "##### Check NC4FG TARPN HOME service and home_background.sh"
   cd /home/pi
   ######## UPDATE home_background.sh
   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f home-service.txt
   rm -f home.service*

   ### Get new copy of the script
   tarpnget home-service.txt

   ### Check if we have the home-service.txt file.
   if [ -f home-service.txt ];
   then
      echo "##### received HOME-SERVICE.TXT script"
      mv home-service.txt home.service
   else
      echo "##### ERROR706.701   Did not receive HOME-SERVICE.TXT.  "
      echo
      echo "##### Aborting"
      exit 1;
   fi

   sudo rm /etc/systemd/system/home.service
   if [ -f /etc/systemd/system/home.service ];
   then
      echo "#### ERROR706.702: home service did not delete. "
      echo
      echo "##### Aborting"
      exit 1;
   else
      sudo mv ~/home.service /etc/systemd/system/home.service
      if [ -f /etc/systemd/system/home.service ];
      then
          echo "##### home.service has been replaced"
          echo ##### reload service
          sudo systemctl daemon-reload
          sudo systemctl enable home.service
          sudo systemctl start home.service
          echo "##### HOME_BACKGROUND script has been updated and the"
          echo "##### OS has been told to resume calling it."
          echo -e "\n\n\n\n"
      else
          echo "##### ERROR706.703: home.service was deleted before update but we were"
          echo "#####          unable to re-install the new copy."
          echo
          echo "##### Aborting"
          exit 1;
      fi
   fi
fi


echo "##### Check NC4FG TARPN HOME home_background.sh"

#### Delete local temp copy of home background.
rm -f home_background.sh*
tarpnget home_background.sh
### Check if we have the script file now.
if [ -f home_background.sh ];
then
   echo "##### received HOME_BACKGROUND script"
   echo "##### moving new background shell script file into place"
   chmod +x home_background.sh
   sudo killall home_background.sh
   sudo mv home_background.sh /usr/local/sbin/home_background.sh
   echo "##### home_background script has been updated."
else
   echo
   echo
   echo "###### ERROR706.710  Failure to fetch home_background.sh"
   echo
   echo
   echo "##### Aborting"
   exit 1;
fi



rm -f home-service.txt
rm -f home.service*
rm -f home_background.sh*
echo
uptime
echo

########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
echo
echo "##### Install LINKTEST Application"
echo

cd /home/pi/zip-temp

tarpnget linktest.zip
if [ -f /home/pi/zip-temp/linktest.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.052.  Failed to obtain linktest.zip from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.052!  Failed to obtain linktest.zip from the web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR706.052: Aborting"
   exit 1
fi

unzip linktest.zip

if [ -f /home/pi/zip-temp/linktest-app ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.051.  Error in unzipping linktest.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.051! Error in unzipping linktest.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.051: Aborting"
   exit 1
fi

sudo mv linktest-app /usr/local/sbin/linktest
rm linktest.zip


echo
uptime
echo

echo "#####"
echo "##### Get telnetlib3"
echo "#####"
sudo pip install telnetlib3




cd ~/zip-temp


echo "#####"
echo "##### Download g8bpq_link_stress.py"
echo "#####"
tarpnget g8bpq_link_stress.zip
if [ -f g8bpq_link_stress.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.053.  Error in downloading g8bpq_link_stress.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.053! Error in dpwnloading g8bpq_link_stress.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.053: Aborting"
   exit 1
fi

echo "#####"
echo "##### Unzip g8bpq_link_stress.zip"
echo "#####"
unzip g8bpq_link_stress.zip
if [ -f g8bpq_link_stress.py ];
then
   echo "##### unzip successful.  Moving g8bpq_link_stress.py sbin"
   sudo mv g8bpq_link_stress.py /usr/local/sbin/g8bpq_link_stress.py
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.054.  Error in unzip of g8bpq_link_stress.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.054! Error in unzip of g8bpq_link_stress.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.054: Aborting"
   exit 1
fi

echo
uptime
echo

#######################################################################################################################################

########### UPDATE LISTEN Application ###########################################3
########### UPDATE LISTEN Application ###########################################3
########### UPDATE LISTEN Application ###########################################3
########### UPDATE LISTEN Application ###########################################3
echo
echo "##### Update LISTEN Application"
echo

cd /home/pi/zip-temp

tarpnget listen.zip

if [ -f /home/pi/zip-temp/listen.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.062.  Failed to obtain listen.zip from web server"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.062!  Failed to obtain listen.zip from the web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR706.052: Aborting"
   exit 1
fi

unzip listen.zip

if [ -f /home/pi/zip-temp/listen ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
   echo "update.sh ERROR706.061.  Error in unzipping listen.zip"  >> $TARPNCOMMANDLOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.061! Error in unzipping listen.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.061: Aborting"
   exit 1
fi

sudo mv listen /usr/local/sbin/listen
rm listen.zip
#########################
### old ###
### old ###   rm -f listen-app*
### old ###
### old ###   wget -o /dev/null $_source_url/listen-app
### old ###
### old ###   ### Check if we have the listen-app file now.
### old ###   if [ -f listen-app ];
### old ###   then
### old ###      echo "##### received listen-app"
### old ###      chmod +x listen-app
### old ###      sudo mv listen-app /usr/local/sbin/listen
### old ###   else
### old ###      echo "##### Error getting listen-app! !!!!"
### old ###      echo "##### Error getting listen-app! !!!!"
### old ###      echo "##### Error getting listen-app! !!!!"
### old ###      echo "##### Error getting listen-app! !!!!"
### old ###      sleep 1;
### old ###      ls
### old ###      echo
### old ###      echo "##### Aborting"
### old ###      exit 1;
### old ###   fi
### old ###


if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo
   uptime
   echo
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "TARPN UPDATE Resuming pi-shutdown-service" >> $NPA_LOGFILE
   sudo systemctl start neighbor_port_association.service
   echo "Neighbor-Port-Assocation SERVICE started"
fi


if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo
   uptime
   echo
   echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
   echo "TARPN UPDATE Resuming statusmonitor-service" >> $STATUSMONITOR_LOGFILE
   sudo systemctl start statusmonitor.service
   echo "statusmonitor SERVICE started"
fi

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo
   uptime
   echo
   echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
   echo "TARPN UPDATE Starting/resuming rx-tarpnstat service" >> $RX_TARPNSTAT_LOGFILE
   sudo systemctl start rx_tarpnstat.service
   echo "rx-tarpnstat SERVICE started"
fi

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo
   uptime
   echo
   echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
   echo "TARPN UPDATE resuming pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
   sudo systemctl start pi_shutdown.service
   echo "pi_shutdown SERVICE started"
fi

if [ -f $DOWNLOAD_SCRIPT_PERMISSION ];
then
   echo "#### starting/resuming tarpn-mon service"
   echo
   uptime
   echo
   echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
   echo "TARPN UPDATE starting/resuming tarpn-mon service" >> $TARPNMON_RUNNER_LOG
   sudo systemctl start $TARPN_MON_SERVICE_FILE
   echo "tarpn-mon SERVICE started"
fi

echo
uptime
echo



echo
echo "#####"
echo "#####"
echo "##### successful completion of UPDATE"
echo
   echo -ne "TARPN command:           "
   grep "\--TARPNVERSION--" /usr/local/sbin/tarpn | grep -v "grep" | cut -d# -f4 | cut -d\" -f1
   echo
   grep --text "\--VERSION--" /usr/local/sbin/tarpn_start1.sh | cut -d# -f7 | cut -d\" -f1
   grep --text "\--VERSION--" /usr/local/sbin/tarpn_start1dl.sh | cut -d# -f7 | cut -d\" -f1
   grep --text "\--VERSION--" /usr/local/sbin/tarpn_start2.sh | cut -d# -f7 | cut -d\" -f1
   grep --text "\--VERSION--" /usr/local/sbin/update.sh | grep -v "grep" | cut -d- -f5
   grep --text "\--VERSION--" /home/pi/bpq/configure_node_ini.sh | cut -d- -f5



   grep --text "\--VERSION--" /usr/local/sbin/runbpq.sh | cut -d= -f2
   grep --text "\--VERSION--" /home/pi/bpq/make_local_bpq.sh | cut -d- -f5

   echo
   echo
   echo "### Background service scripts:"

   grep --text "\--VERSION--" /usr/local/sbin/tarpn_background.sh | cut -d- -f5
   grep --text "\--VERSION--" /usr/local/sbin/home_background.sh | cut -d- -f6
   grep --text "\--VERSION--" /usr/local/sbin/pi_shutdown_background.sh | cut -d- -f5
   grep --text "\--VERSION--" /usr/local/sbin/rx_tarpnstat.sh | cut -d- -f5
   grep --text "\--VERSION--" /usr/local/sbin/statusmonitor.sh | cut -d- -f5
   grep --text "\--VERSION--" /usr/local/sbin/tarpnmon-runner.sh | cut -d- -f5
   grep --text "\--VERSION--" /usr/local/sbin/npa.sh | cut -d= -f2
   echo
   /usr/local/sbin/neighbor_port_association.app a
   echo

   grep --text "\--VERSION--" /usr/local/sbin/logfiletruncate.sh | cut -d= -f2
   grep --text "\--VERSION--" /usr/local/sbin/tarpnget.sh | cut -d- -f5
   echo
   /usr/local/sbin/sendroutestocq x
   /usr/local/sbin/listen x
   /usr/local/sbin/linktest x
   /usr/local/sbin/rx_tarpnstatapp -v | grep "rx_tarpnstatapp"
   echo -n "TARPN Monitor application "
   tarpn-mon -version

   #grep getElementById /usr/local/sbin/home_web_app/index.html | grep About | cut -d\> -f4
   /home/pi/bpq/linbpq -v | grep "System"



echo
echo
echo "##### how long did that take?  "

echo -e "start time was "
cat ~/update_start_date.txt
echo -e "  end time is  "
date
rm ~/update_start_date.txt
sudo rm -f /usr/local/etc/update_last_completed.txt
sudo rm -f ~/update_last_completed.txt
date > ~/update_last_completed.txt
sudo mv ~/update_last_completed.txt /usr/local/etc/update_last_completed.txt

TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
sudo touch $TARPNCOMMANDLOGFILE
sudo chown pi $TARPNCOMMANDLOGFILE



echo -ne $(date) "" >> $HOME_LOGFILE
echo "### TARPN UPDATE good exit"  >> $HOME_LOGFILE

echo -ne $(date) "" >> $TARPN_SERVICE_LOG
echo "### TARPN UPDATE good exit"  >> $TARPN_SERVICE_LOG

echo -ne $(date) "" >> $TARPN_CONTROL_PANEL_LOGFILE
echo "### TARPN UPDATE good exit"  >> $TARPN_CONTROL_PANEL_LOGFILE

echo -ne $(date) "" >> $START_STOP_LOGFILE
echo "### TARPN UPDATE good exit"  >> $START_STOP_LOGFILE

echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo "### TARPN UPDATE good exit"  >> $TARPNCOMMANDLOGFILE

echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
echo "### TARPN UPDATE good exit"  >> $TARPNMON_RUNNER_LOG

echo -ne $(date) "" >> $NPA_LOGFILE
echo "### TARPN UPDATE good exit"  >> $NPA_LOGFILE

echo -ne $(date) "" >> $RX_TARPNSTAT_LOGFILE
echo "### TARPN UPDATE good exit"  >> $RX_TARPNSTAT_LOGFILE

echo -ne $(date) "" >> $STATUSMONITOR_LOGFILE
echo "### TARPN UPDATE good exit"  >> $STATUSMONITOR_LOGFILE

###################################################################################################
echo
echo "##### Resume execution of background scripts"
sudo rm -rf $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE
sudo rm -rf /tmp/tarpn
sudo rm -rf $DOWNLOAD_SCRIPT_PERMISSION
###################################################################################################


echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
echo -ne "TARPN UPDATE: TARPN version is: " >> $TARPNCOMMANDLOGFILE
cat /usr/local/sbin/tarpn | grep -e "=TARPN" | grep -v cut | cut -d= -f2 >> $TARPNCOMMANDLOGFILE


echo
echo "Thank you for running tarpn update and we look forward to seeing you next time!"

sudo rm -rf /home/pi/zip-temp
rm -rf /home/pi/migrate.sh

exit 0

