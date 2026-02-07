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
}


HOME_LOGFILE="/var/log/tarpn_home.log"
TARPN_SERVICE_LOG="/var/log/tarpn_service.log"
START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
TARPN_COMMAND_LOGFILE="/var/log/tarpn_command.log"
TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"
TARPNMON_RUNNER_LOG="/var/log/tarpn_mon.log";
NPA_LOGFILE="/var/log/tarpn_neighbor_port_association.log"
RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rxtarpnstat_service.log"
STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log";

TARPN_MON_SERVICE_FILE="tarpn_mon.service";
sudo touch $TARPN_COMMAND_LOGFILE
sudo chown pi $TARPN_COMMAND_LOGFILE

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
###########    6-04-2023 vBullseye021 -- move stress test program to /usr-local/sbin now that tarpn command knows about it.
###########    7-18-2023 vBullseye022 -- get ncpacket wallpaper
###########   10-24-2023 vBullseye023 -- Add a completion date file so tinfo can read it out.
###########   10-25-2023 vBullseye024 -- fix bug in completion date file.
###########   11-26-2023 vBullseye025 -- add L4LISTEN.
###########    1-01-2024 vBullseye026 -- Use new CONTROL_PANEL_LOG file
###########    1-01-2024 vBullseye027 -- Set the rights for the log files, in case they weren't set before.
###########    1-29-2024 vBookworm030 -- remove l4listen.
###########    1-29-2024 vBookworm031 -- node-config-ini.sh is now in /usr/tarpn/sbin instead of /home/pi/bpq.
###########    1-29-2024 vBookworm032 -- update initd and systemd loads
###########    2-03-2024 vBookworm033 -- Move check for python configparser to the end, because it will fail until Fin and I get together on this.
###########    2-03-2024 vBookworm034 -- add getver.py
###########    2-15-2024 vBookworm035 -- remove check for python configparser
###########   11-10-2024 vBookworm036 -- fix an unnecessary "CD" when installing the newly downloaded NinoTNC firmware versions
###########    5-09-2025 vBookworm037 -- Move modern start/stop and taprn-mon code from bullseye
###########    5-09-2025 vBookworm038 -- fix typo with getver.py installation    tarpn_rxtarpnstat_service.log is correct.  tarpn_rx_tarpnstat_service.log is not  Add logging when starting and stopping services
###########    6-07-2025 vBookworm039 -- Add install of the Fix-Vnc-Headless.sh script file
###########   10-18-2025 vBookworm040 -- Add download and install of gpio_for_controlpanel.sh
###########   10-30-2025 vBookworm041 -- change the owner and group of a service file before moving it into /etc/systemd/system
###########   10-30-2025 vBookworm042 -- Change the name of the bbs checker app to bbs_checker_bw  (BookWorm)
###########   02-04-2026 Bookworm043 -- Stop downloading and updating tarpn.service and pi_shutdown.service
###########   02-05-2026 Bookworm044 -- bbs_checker_bw.app      renamed to include .app.
###########   02-05-2026 Bookworm045 -- Some improvements to update.sh log output
###########   02-06-2026 Bookworm046 -- Fix acquisition of TRR.APP.
###########   02-06-2026 Bookworm047 -- use trrbw1.zip instead of trr.zip to get around the slow caching of our web server.
###########   02-06-2026 Bookworm048 -- stop doing chown of the home.service       fix touch to use a proper alias to command logfile.
###########   02-07-2026 Bookworm049 -- Use N2IRZ method to install telnetlib3.
###########   02-07-2026 Bookworm050 -- use sudo when changing group or owner to root.  I think this was incorrect when installing services.


echo "#####"
echo "#####"
echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
echo "####  UPDATE.SH                 Bookworm050 " >> $TARPN_COMMAND_LOGFILE
echo "#### =UPDATE.SH                 Bookworm050="; #  --VERSION--#########
echo "#####"


echo "Hello user " $(whoami);

if [ $(whoami) != "pi" ]; then
    echo "TARPN UPDATE should only be run by user pi"
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  FAIL: User is $(whoami) -- must be pi" >> $TARPN_COMMAND_LOGFILE
    exit 1               #wrong user
fi


sudo echo date >> $TARPN_COMMAND_LOGFILE
sudo chmod 666 $TARPN_COMMAND_LOGFILE

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

sudo rm /usr/tarpn/etc/ag.dat

### Establish a source URL for acquiring updated materials
cd /home/pi
if [ -f /usr/tarpn/etc/source_url.txt ];
then
    echo -n;
else
   echo "##### ERROR706.043: source URL file not found."
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo " update.sh ERROR706.043 trying to get Source URL - QUIT" >> $TARPN_COMMAND_LOGFILE
   echo
   echo "##### Aborting"
   exit 1
fi
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);

if [ -f /usr/tarpn/sbin/test_internet.sh ];
then
    echo "Internet test code is loaded"
else
    sudo rm -f test_internet.sh
    startget test_internet.sh
    if [ -f test_internet.sh ];
    then
        if grep -q "copyright Tadd Torborg KA2DEW" test_internet.sh; then
           chmod +x test_internet.sh
           sudo cp test_internet.sh /usr/tarpn/sbin
        else
           echo "FAIL1 getting access to Internet for update"
           echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
           echo " update.sh FAIL1 trying to read files from Internet - QUIT" >> $TARPN_COMMAND_LOGFILE
           exit 1
        fi
    else
        echo "ERROR706.042:  FAIL2 getting access to Internet for update"
        echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
        echo "ERROR706.042:   update.sh FAIL2 trying to read files from Internet - QUIT" >> $TARPN_COMMAND_LOGFILE
        exit 1
    fi
fi






echo "##### Verify script WRITE access to the /home/pi user directory"
cd /home/pi
source test_internet.sh
getTestFile
if [ $? -lt 1 ];       ## if no errors, move on
then
   echo "We have access to the TARPN repository"
else
    echo "ERROR706.041  FAIL getting access to Internet for update"
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "ERROR706.041  update.sh failed to read files from Internet - QUIT" >> $TARPN_COMMAND_LOGFILE
    exit 1;
fi

###########  Get UNIX EPOCH TIME and write it to the card.
if [ -f /usr/tarpn/sbin/tarpn_start1dl_starttime.txt ];
then
   echo -n "This SD card had the datecode of "
   cat /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
else
   date +%s > /home/pi/datetemp.txt
   sudo mv /home/pi/datetemp.txt /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
   echo -n "This SD card is "
   cat /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
fi




rm -f tarpn
rm -f runbpq.sh


sudo chmod 666 $START_STOP_LOGFILE
echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### TARPN UPDATE starting"  >> $START_STOP_LOGFILE

echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
echo "### TARPN UPDATE starting"  >> $TARPN_COMMAND_LOGFILE



echo

##################################################################################################
echo "###### Download TARPNGET"
startget tarpnget.sh
if [ -f tarpnget.sh ];
then
   echo "##### tarpnget downloaded successfully"
   chmod +x tarpnget.sh;
   sudo mv tarpnget.sh /usr/tarpn/sbin/tarpnget.sh
else
   echo -e "\n\n\n\n\nERROR: UPDATE Failed retrieving tarpnget.  Something is wrong"
   echo -e "ERROR: UPDATE Aborting\n\n\n\n\n"
   exit 1;
fi

source /usr/tarpn/sbin/tarpnget.sh
echo
echo "###### Download SLEEP-WITH-COUNT"
tarpnget sleep_with_count.sh
if [ -f sleep_with_count.sh ];
then
   echo "##### sleep_with_count downloaded successfully"
   chmod +x sleep_with_count.sh;
   sudo mv sleep_with_count.sh /usr/tarpn/sbin/sleep_with_count.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving sleep_with_count.  Something is wrong"
   echo -e "ERROR: UPDATE Aborting\n\n\n\n\n"
   exit 1;
fi


source /usr/tarpn/sbin/sleep_with_count.sh
##################################################################################################
echo




echo "#### shutting down tarpn service"
sudo systemctl stop tarpn.service
echo "#### systemctl STOP sent to tarpn service"


sudo chmod 666 $TARPN_SERVICE_LOG
echo -ne $(date) "" >> $TARPN_SERVICE_LOG
echo "### TARPN UPDATE starting"  >> $TARPN_SERVICE_LOG

echo -ne $(date) "" >> $TARPN_SERVICE_LOG
echo "### UPDATE: Stopped tarpn service"  >> $TARPN_SERVICE_LOG

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
    echo "##### 5 second wait for everything to quit"
    sleep_with_count_5
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


echo "##### Removing old zip-temp directory (if it exists)"
sudo rm -rf /home/pi/zip-temp

sudo chmod 666 $HOME_LOGFILE
echo -ne $(date) "" >> $HOME_LOGFILE
echo "Starting TARPN-UPDATE  -- this will kill off the home service" >> $HOME_LOGFILE

echo -e "\n\n" >> $HOME_LOGFILE
echo -ne $(date) "" >> $HOME_LOGFILE
echo "Starting TARPN-UPDATE  -- this will kill off the home service" >> $HOME_LOGFILE

#### Shutdown all of our background services.
echo "shutting down neighbor_port_association service"
echo -e "\n\n" >> $NPA_LOGFILE
echo -ne $(date) "" >> $NPA_LOGFILE
echo "TARPN UDPATE starting -- suspending NPA service" >> $NPA_LOGFILE
sudo systemctl stop neighbor_port_association.service


echo "shutting down rx_tarpnstat service"
echo -e "\n\n" >> $RX_TARPNSTAT_LOGFILE
echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
echo "TARPN UDPATE starting -- suspending rx-tarpnstat-service" >> $RX_TARPNSTAT_LOGFILE
sudo systemctl stop rx_tarpnstat.service


echo "shutting down home service"
echo -e "\n\n" >> $HOME_LOGFILE
echo -ne $(date) " " >> $HOME_LOGFILE
echo "TARPN UDPATE starting -- suspending home.service" >> $HOME_LOGFILE
sudo systemctl stop home.service


echo "shutting down statusmonitor service"
echo -e "\n\n" >> $STATUSMONITOR_LOGFILE
echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "TARPN UDPATE starting -- suspending statusmonitor-service" >> $STATUSMONITOR_LOGFILE
sudo systemctl stop statusmonitor.service

echo "shutting down pi_shutdown service"
sudo chmod 666 $TARPN_CONTROL_PANEL_LOGFILE
echo -e "\n\n" >> $TARPN_CONTROL_PANEL_LOGFILE
sudo echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
sudo echo "TARPN UDPATE starting -- suspending pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
sudo systemctl stop pi_shutdown.service

echo "shutting down tarpn-mon service"
sudo systemctl stop $TARPN_MON_SERVICE_FILE
echo -e "\n\n" >> $TARPNMON_RUNNER_LOG
echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
echo "TARPN UDPATE starting -- suspending tarpn-mon service" >> $TARPNMON_RUNNER_LOG
echo " "
echo " "
echo " "
echo " "


rm -rf /tmp/tarpn


#### to install the custom bpq commands we need to do this
### install xinetd
### once-installed, create a file called /usr/tarpn/etc/xinitd.001

### download the custom-bpq-commands-services.001 file
### copy custom-bpq-commands-services.001 to /etc/services
### once copied/installed, create /usr/tarpn/etc/custom-bpq-commands-services.001

### download the custom-bpq-commands-inetd.001 file
### copy contents of custom-bpq-commands-inetd.001 to /etc/inetd.conf
### once copied/installed, create /usr/tarpn/etc/custom-bpq-commands-inetd.001


##### get rid of any temporary files leftover from a previous run of update
rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*
rm -f ~/neighbor_port_association*
############ Update inet.d configuration

if [ -f /usr/tarpn/etc/xinetd.001 ];
then
   echo "### xinetd already installed"
else
   echo "### XINETD not installed.  Will do so now."
   sudo apt-get -y install xinetd
   sudo touch /usr/tarpn/etc/xinetd.001
fi
echo " "
echo " "


######### Get a 10K test file and put it in the Files folder
if [ -d /home/pi/bpq/Files ]; then
   echo "  Files folder already exists"
else
   cd /home/pi/bpq
   mkdir Files
   echo "  Files folder was missing.  Create it"
fi


cd ~
sudo rm -f g8bpqloop.txt
tarpnget g8bpqloop.txt
if [ -f /home/pi/bpq/Files/g8bpqloop.txt ]; then
   sudo mv g8bpqloop.txt /home/pi/bpq/Files
else
   echo "ERROR706.055: Failed to get g8bpqloop.txt file"
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.055.  Failed to get g8bpqloop.txt file from web server"  >> $TARPN_COMMAND_LOGFILE
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


######### INSTALL WALLPAPER ###################################################################
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


######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
cd ~
mkdir zip-temp
cd zip-temp


tarpnget npa.zip
##### now neighbor_port_association-service.app should exist in the home directory
if [ -f /home/pi/zip-temp/npa.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.030.  Failed to obtain npa.zip from web server"  >> $TARPN_COMMAND_LOGFILE
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

unzip npa.zip

if [ -f /home/pi/zip-temp/neighbor_port_association.app ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.029.  Error in unzipping npa.zip"  >> $TARPN_COMMAND_LOGFILE
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

cd /home/pi
tarpnget npa.sh
##### now npa.sh should exist in the home directory
if [ -f ~/npa.sh ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.028.  Failed to obtain npa.sh from web server"  >> $TARPN_COMMAND_LOGFILE
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

chmod +x npa.sh
sudo mv npa.sh /usr/tarpn/sbin
chmod +x zip-temp/neighbor_port_association.app
sudo mv zip-temp/neighbor_port_association.app /usr/tarpn/sbin
if [ -x /usr/tarpn/sbin/npa.sh ];
then
   echo "##### Neighbor-Port-Association script updated"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.027.  Neighbor-port-association script file failed to install."  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "ERROR706.027! Neighbor-Port-Association script file failed to install."
   echo "              Please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.027: Aborting"
   exit 1;
fi

if [ -x /usr/tarpn/sbin/neighbor_port_association.app ];
then
   echo "##### Neighbor-Port-Assocation APP updated"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.026.  Neighbor-port-association app file failed to install."  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "ERROR706.026! Neighbor-Port-Assocation APP file failed to install."
   echo "              Please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.026: Aborting"
   exit 1;
fi


echo
echo "##### See if we need to install the Neighbor Port Association SERVICE"

if [ -e /usr/tarpn/etc/npa_installed.002 ];
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
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh  ERROR706.025.  Neighbor-port-association service failed to download."  >> $TARPN_COMMAND_LOGFILE
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

   sudo chown root neighbor_port_association-service.txt
   sudo chgrp root neighbor_port_association-service.txt
   sudo mv neighbor_port_association-service.txt neighbor_port_association.service

   if [ -f /etc/systemd/system/neighbor_port_association.service ];
   then
      sudo rm /etc/systemd/system/neighbor_port_association.service
   fi

   if [ -f /etc/systemd/system/neighbor_port_association.service ];
   then
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh ERROR706.024.  unable to remove prior neighbor port association service."  >> $TARPN_COMMAND_LOGFILE
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
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh  ERROR706.023.  Neighbor-port-association SERVICE failed to copy to system.d"  >> $TARPN_COMMAND_LOGFILE
      resume_services
      echo "ERROR706.023! Neighbor-Port-Assocation SERVICE file failed"
      echo "              to copy to /etc/system.d/system."
      echo "              Please send a missive about this to tarpn@groups.io"
      echo "              Include the terminal output from this update."
      echo "ERROR706.023: Aborting"
      exit 1;
   fi

   ### put a token in the etc directory indicating that this version of npa was installed.
   echo date >> npa_installed.002
   sudo mv npa_installed.002 /usr/tarpn/etc
fi

######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################



########################### TARPN-MON executable ###########################################################################################################
########################### TARPN-MON executable ###########################################################################################################
########################### TARPN-MON executable ###########################################################################################################

TARPN_MON_SERVICE_PATH_AND_FILE="/etc/systemd/system/tarpn_mon.service";
### defined at top ### TARPN_MON_SERVICE_FILE="tarpn_mon.service";
TARPN_MON_SERVICE_DOWNLOAD_NAME="tarpn-mon-service.txt";
TARPN_MON_SCRIPT_NAME="tarpnmon-runner.sh"
TARPN_MON_SCRIPT_PATH_AND_NAME="/usr/tarpn/sbin/tarpnmon-runner.sh"

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

tarpnget $TARPN_MON_SCRIPT_NAME
if [ -f $TARPN_MON_SCRIPT_NAME ];
then
    chmod +x $TARPN_MON_SCRIPT_NAME
    sudo mv $TARPN_MON_SCRIPT_NAME $TARPN_MON_SCRIPT_PATH_AND_NAME
    echo "The current runner script from the repository has been installed."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.044. Cound not acquire tarpnmon-runner script from TARPN server"  >> $TARPN_COMMAND_LOGFILE
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

if [ -f /usr/tarpn/sbin/tarpn-mon ];
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
tarpnget tarpn-mon-version.txt
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
        tarpnget tarpn-mon.linux-arm32.zip

        if [ -f tarpn-mon.linux-arm32.zip ];
        then
            unzip tarpn-mon.linux-arm32.zip
            sudo rm -rf __MACOSX
            rm -rf tarpn-mon-linux-arm32.zip
            mv tarpn-mon.linux-arm32 tarpn-mon
            chmod +x tarpn-mon
            sudo rm -f /usr/tarpn/sbin/tarpn-mon
            sudo mv tarpn-mon /usr/tarpn/sbin/tarpn-mon
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




############### TARPN-MON service
############### TARPN-MON service
############### TARPN-MON service
echo
echo "See if we need to install the systemd SERVICE for TARPN-MON."

cd ~
sudo rm -rf download_temp_folder
mkdir download_temp_folder
cd download_temp_folder


if [ -e $TARPN_MON_SERVICE_PATH_AND_FILE ];
then
    echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
    echo "##### tarpn-mon service is already installed" >> $TARPNMON_RUNNER_LOG
    echo "##### tarpn-mon service is already installed"
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
        echo "update.sh  tarpn-mon-service is enabled - waiting for start."  >> $TARPNMON_RUNNER_LOG
        echo "tarpn-mon-service is enabled - waiting for start."
    else
        echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
        echo "update.sh  ERROR706.098.  tarpn-mon-service.txt failed to download."  >> $TARPNMON_RUNNER_LOG
        echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
        echo "update.sh  ERROR706.098.  tarpn-mon-service.txt failed to download."  >> $TARPN_COMMAND_LOGFILE
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
        echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
        echo "update.sh  ERROR706.099.  TARPN-MON SERVICE failed to copy to system.d"  >> $TARPN_COMMAND_LOGFILE
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


######## Update the Fix-VNC-Headless script
rm -f /home/pi/fix-vnc-headless.sh
tarpnget fix-vnc-headless.sh
if [ -f /home/pi/fix-vnc-headless.sh ];
then
   chmod +x /home/pi/fix-vnc-headless.sh
   sudo chown root /home/pi/fix-vnc-headless.sh
   sudo mv /home/pi/fix-vnc-headless.sh /usr/tarpn/sbin/fix-vnc-headless.sh
   echo "### Updated fix-vnc-headless.sh"
   rm -f /home/pi/fix-vnc-headless.sh
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.032.  failure getting fix-vnc-headless.SH script from TARPN server."  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706.032  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the fix-vnc-headless.sh script. "
    echo "              Post to tarpn@groups.io including this error message."
    echo "              Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi




#### Install BPQ Services, custom scripts and whatnot

## for upgrading inetd and systemd   if [ -f /usr/tarpn/etc/custom-bpq-commands-services.002 ];
## for upgrading inetd and systemd   then
## for upgrading inetd and systemd      echo "### version 002 BPQ custom commands SERVICES already installed"
## for upgrading inetd and systemd   else
## for upgrading inetd and systemd       echo " "
## for upgrading inetd and systemd       echo "CUSTOM-BPQ-COMMANDS.002 not installed. Doing so now."
## for upgrading inetd and systemd       ### if there are already changes for .001, blow them away so we can act like we're starting with a fresh system.
## for upgrading inetd and systemd       if [ -f /usr/tarpn/etc/custom-bpq-commands-services.001 ];
## for upgrading inetd and systemd       then
## for upgrading inetd and systemd          echo "### we already had version 001, so turn off all of the 001 features of the services file"
## for upgrading inetd and systemd          sudo rm -f /home/pi/services-copy
## for upgrading inetd and systemd          cp /etc/services /home/pi/services-copy                                            ## copy the services OS file to our local folder
## for upgrading inetd and systemd          sudo sed -i 's/custom-bpq-commands-services-001/cus##tom-b##pq-comm##ands-servi##ces-0##01/g' /home/pi/services-copy
## for upgrading inetd and systemd          sudo sed -i 's/trr     63000/###trr     63##000/g' /home/pi/services-copy
## for upgrading inetd and systemd          sudo sed -i 's/linux   63001/###linux   630##01/g' /home/pi/services-copy
## for upgrading inetd and systemd          sudo sed -i 's/tchat   63002/###tchat   63##002/g' /home/pi/services-copy
## for upgrading inetd and systemd          sudo sed -i 's/tinfo   63003/###tinfo   63##003/g' /home/pi/services-copy
## for upgrading inetd and systemd          sudo chown root /home/pi/services-copy                                             ## make our copy of services look like the original root ownership
## for upgrading inetd and systemd          sudo chgrp root /home/pi/services-copy                                             ## make our copy of services look like the original root group
## for upgrading inetd and systemd          sudo mv /home/pi/services-copy /etc/services
## for upgrading inetd and systemd       fi
## for upgrading inetd and systemd       if grep -q "63000" /etc/services; then
## for upgrading inetd and systemd          echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          echo "update.sh  ERROR706.022.  Port 63000 already present in /etc/services.  FAIL"  >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          echo "### Contact tarpn@groups.io - this is a bug."
## for upgrading inetd and systemd          resume_services
## for upgrading inetd and systemd          echo "### ERROR706.022  fail in CUSTOM-BPQ-COMMANDS."
## for upgrading inetd and systemd          echo "###               Note: port 63000 already present in /etc/services"
## for upgrading inetd and systemd          echo "###               Contact tarpn@groups.io  -- this is a bug."
## for upgrading inetd and systemd          exit 1;
## for upgrading inetd and systemd       fi
## for upgrading inetd and systemd       tarpnget custom-bpq-commands-services.002
## for upgrading inetd and systemd       if [ -f custom-bpq-commands-services.002 ];
## for upgrading inetd and systemd       then
## for upgrading inetd and systemd          cp /etc/services /home/pi/services-copy                                            ## copy the services OS file to our local folder
## for upgrading inetd and systemd          sudo cat /home/pi/custom-bpq-commands-services.002 >> /home/pi/services-copy       ## add the /etc/services info for BPQ command extension
## for upgrading inetd and systemd          sudo chown root /home/pi/services-copy                                             ## make our copy of services look like the original root ownership
## for upgrading inetd and systemd          sudo chgrp root /home/pi/services-copy                                             ## make our copy of services look like the original root group
## for upgrading inetd and systemd          sudo mv /home/pi/services-copy /etc/services                                       ## put the new version of services back to the /etc directory where it lives
## for upgrading inetd and systemd          sudo touch /usr/tarpn/etc/custom-bpq-commands-services.002       ## add the flag-file to tell us not to install this again
## for upgrading inetd and systemd          echo "### version 002 BPQ custom commands SERVICES now newly installed"
## for upgrading inetd and systemd          echo " "
## for upgrading inetd and systemd       else
## for upgrading inetd and systemd          echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          echo "update.sh  ERROR706.021.  Port 63000 already present in /etc/services."  >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          resume_services
## for upgrading inetd and systemd          echo "### ERROR706.021: Fail in CUSTOM-BPQ-COMMANDS in retrieving the /etc/services details from tarpn.com"
## for upgrading inetd and systemd          echo "###               Contact tarpn@groups.io  -- this is a bug."
## for upgrading inetd and systemd          exit 1;
## for upgrading inetd and systemd       fi
## for upgrading inetd and systemd   fi
## for upgrading inetd and systemd
## for upgrading inetd and systemd
## for upgrading inetd and systemd   if [ -f /usr/tarpn/etc/custom-bpq-commands-inetd.004 ];
## for upgrading inetd and systemd   then
## for upgrading inetd and systemd      echo "### version 004 BPQ custom commands INETD already installed"
## for upgrading inetd and systemd   else
## for upgrading inetd and systemd       echo "Version 004 BPQ custom commands INETD not installed. Doing so now."
## for upgrading inetd and systemd       tarpnget custom-bpq-commands-inetd.004
## for upgrading inetd and systemd       if [ -f custom-bpq-commands-inetd.004 ];
## for upgrading inetd and systemd       then
## for upgrading inetd and systemd          if [ -f /etc/inetd.conf ];                                                          ## see if there is already an inetd.conf.
## for upgrading inetd and systemd          then
## for upgrading inetd and systemd              sudo rm -f /etc/inetd.conf                                             ## yes.  blow it away
## for upgrading inetd and systemd          fi
## for upgrading inetd and systemd          sudo rm -f /home/pi/inetdconf-copy
## for upgrading inetd and systemd          sudo mv /home/pi/custom-bpq-commands-inetd.004 /home/pi/inetdconf-copy       ## add the /etc/inetd.conf reconfig info for BPQ command extension
## for upgrading inetd and systemd          sudo chown root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root ownership
## for upgrading inetd and systemd          sudo chgrp root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root group
## for upgrading inetd and systemd          sudo mv /home/pi/inetdconf-copy /etc/inetd.conf                  ## put the new version of inetd.conf back to the /etc directory where it lives
## for upgrading inetd and systemd          sudo touch /usr/tarpn/etc/custom-bpq-commands-inetd.004          ## add the flag-file to tell us not to install this again
## for upgrading inetd and systemd          sudo /etc/init.d/xinetd restart                                  ## kick the xinetd service so it uses our new stuff
## for upgrading inetd and systemd          echo "### version 004 BPQ custom commands INETD now newly installed"
## for upgrading inetd and systemd       else
## for upgrading inetd and systemd          echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          echo "update.sh ERROR706.020.  Fail in version 004 BPQ custom commands INETD."  >> $TARPN_COMMAND_LOGFILE
## for upgrading inetd and systemd          resume_services
## for upgrading inetd and systemd          echo "ERROR706.020: Fail in version 004 BPQ custom commands INETD in retrieving"
## for upgrading inetd and systemd          echo "              the /etc/inetd details from tarpn.com"
## for upgrading inetd and systemd          echo "              Contact tarpn@groups.io  -- this is a bug."
## for upgrading inetd and systemd          exit 1;
## for upgrading inetd and systemd       fi
## for upgrading inetd and systemd   fi
## for upgrading inetd and systemd

rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*

echo " "
echo " "
echo " "


######### Update the Linux script
rm -f /home/pi/linux.sh
tarpnget linux.sh
if [ -f /home/pi/linux.sh ];
then
   chmod +x linux.sh
   sudo chown root linux.sh
   sudo mv /home/pi/linux.sh /usr/tarpn/sbin/linux.sh
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
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.019.  failure getting Linux.SH script from TARPN server."  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706.019  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the linux.sh script from TARPN server. "
    echo "              Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi


######### Update the TRR script
rm -f trr.sh*
tarpnget trr.sh
if [ -f trr.sh ];
then
   chmod +x trr.sh
   sudo chown root trr.sh
   sudo mv trr.sh /usr/tarpn/sbin/trr.sh
   echo "### Updated trr.sh"
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.018.  Failure getting trr.sh script from TARPN server."  >> $TARPN_COMMAND_LOGFILE
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

tarpnget trrbw1.zip

if [ -f trrbw1.zip ];
then
    unzip trrbw1.zip
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706BW.017. Cound not acquire the trrbw1.zip script from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706BW.017 Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the trrbw1.zip from TARPN server.  "
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi

if [ -f trr.app ];
then
    rm -f trrbw1.zip
    chmod +x trr.app
    sudo mv trr.app /usr/tarpn/sbin
    echo -ne "update.sh  TRR.APP is installed.  Version is: "
    /usr/tarpn/sbin/trr.app v
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706BW.091. trrbw1.zip acquired but contents were not correct!"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706BW.091 Something is wrong.  I had access to TARPN server and"
    echo "             trrbw1.zip acquired but contents were not correct!"
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi


######### Update the TINFO application
sudo rm -f tinfo.sh*

tarpnget tinfo.sh

if [ -f tinfo.sh ];
then
    chmod +x tinfo.sh
    sudo rm -f /usr/tarpn/sbin/tinfo.sh
    sudo mv tinfo.sh /usr/tarpn/sbin/tinfo.sh
    echo "##### TINFO script has been updated."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.016. Cound not acquire TINFO.SH from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706.016 Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the TINFO.SH script from TARPN server.  "
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi

######### Update the LATLON application
sudo rm -f latlon.sh*

tarpnget latlon.sh

if [ -f latlon.sh ];
then
    chmod +x latlon.sh
    sudo rm -f /usr/tarpn/sbin/latlon.sh
    sudo mv latlon.sh /usr/tarpn/sbin/latlon.sh
    echo "##### latlon script has been updated."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.016. Cound not acquire latlon.SH from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706.016 Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the latlon.SH script from TARPN server.  "
    echo "             Abort"
    echo
    echo "##### Aborting"
    exit 1;
fi




######### Update logfiletruncate.sh
sudo rm -f logfiletruncate.sh*

tarpnget logfiletruncate.sh

if [ -f logfiletruncate.sh ];
then
    chmod +x logfiletruncate.sh
    sudo rm -f /usr/tarpn/sbin/logfiletruncate.sh
    sudo mv logfiletruncate.sh /usr/tarpn/sbin/logfiletruncate.sh
    echo "##### logfiletruncate.sh script has been updated."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.101. Cound not acquire logfiletruncate.sh script from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "#### ERROR706.101"
    echo "#### Something is wrong.  I had access to TARPN server but could"
    echo "#### not acquire the logfiletruncate.sh script from TARPN server.  "
    echo "#### Abort"
    exit 1;
fi



##############################################################################################################################
##############################################################################################################################
##############################################################################################################################



echo " "
echo " "
echo " "


######### Update the NODE-CALLS-LINKTEST script
sudo rm -f node_calls_linktest.sh*

tarpnget node_calls_linktest.sh

if [ -f node_calls_linktest.sh ];
then
    chmod +x node_calls_linktest.sh
    sudo rm -f /usr/tarpn/sbin/node_calls_linktest.sh
    sudo mv node_calls_linktest.sh /usr/tarpn/sbin/node_calls_linktest.sh
    echo "##### NODE_CALLS_LINKTEST script has been updated."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.015. Cound not acquire NODE_CALLS_LINKTEST script from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "#### ERROR706.015"
    echo "#### Something is wrong.  I had access to TARPN server but could"
    echo "#### not acquire the NODE_CALLS_LINKTEST script from TARPN server.  "
    echo "#### Abort"
    exit 1;
fi


echo " "
echo " "
echo " "



############# Update the l4listen program
####rm -f l4listen*
####tarpnget l4listen.zip
####if [ -f l4listen.zip ];
####then
####   unzip l4listen.zip
####   sudo mv l4listen /usr/tarpn/sbin/l4listen
####   echo "### Updated l4listen"
####else
####   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
####   echo "update.sh  ERROR706.031. Cound not acquire l4listen.zip from TARPN server"  >> $TARPN_COMMAND_LOGFILE
####   resume_services
####   echo "#### ERROR706.031"
####   echo "### l4listen.zip failed to download.  This is a bug."
####   echo "### complain to tarpn@groups.io"
####   echo " "
####   exit 1
####fi
####rm -f l4listen.zip
####echo " "
####echo " "
#### echo " "

######### Update the flashtnc.py program
rm -f flashtnc.py*
tarpnget flashtnc.py
if [ -f flashtnc.py ];
then
   chmod +x flashtnc.py
   sudo chown root flashtnc.py
   sudo mv flashtnc.py /usr/tarpn/sbin/flashtnc.py
   echo "### Updated flashtnc.py"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.015. Cound not acquire flashtnc.py from TARPN server"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "#### ERROR706.015"
   echo "### flashtnc.py failed to download.  This is a bug."
   echo "### complain to tarpn@groups.io"
   echo " "
   exit 1
fi
rm -f flashtnc.py


######### Update the get_tnc_version.py program
rm -f get_tnc_version.py*
tarpnget get_tnc_version.py
if [ -f get_tnc_version.py ];
then
   chmod +x get_tnc_version.py
   sudo chown root get_tnc_version.py
   sudo mv get_tnc_version.py /usr/tarpn/sbin/get_tnc_version.py
   echo "### Updated get_tnc_version.py"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.014. Cound not acquire get_tnc_version.py from TARPN server"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "#### ERROR706.014"
   echo "#### get_tnc_version.py failed to download.  This is a bug."
   echo "#### complain to tarpn@groups.io"
   echo " "
   exit 1
fi
rm -f get_tnc_version.py

############## Create the ninotnc versions directory
if [ -d /usr/tarpn/etc/ninotnc ];
then
     echo "### NinoTNC directory is present"
else
     sudo mkdir /usr/tarpn/etc/ninotnc
     if [ -d /usr/tarpn/etc/ninotnc ];
     then
          echo "### created ninotnc directory"
     else
          echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
          echo "update.sh  ERROR706.012  Cound not create NinoTNC directory"  >> $TARPN_COMMAND_LOGFILE
          resume_services
          echo "#### ERROR706.012"
          echo "#### FAILURE creating NinoTNC directory"
          echo "#### Please complain to tarpn@groups.io"
          exit 1
     fi
fi

if [ -d /usr/tarpn/etc/ninotnc/versions ];
then
     echo "### NinoTNC Versions directory is present"
else
     sudo mkdir /usr/tarpn/etc/ninotnc/versions
     if [ -d /usr/tarpn/etc/ninotnc/versions ];
     then
          echo "### created Ninotnc Versions directory"
     else
          echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
          echo "update.sh   ERROR706.011   Cound not create NinoTNC Versions directory"  >> $TARPN_COMMAND_LOGFILE
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
sudo rm -rf /usr/tarpn/etc/ninotnc/versions/latest_ninotnc
tarpnget latest_ninotnc.zip
if [ -f latest_ninotnc.zip ];
then
    mkdir temp_latest_ninotnc
    cd temp_latest_ninotnc
    unzip -q /home/pi/latest_ninotnc.zip
    rm -rf *MACOSX
    #cd latest_ninotnc
    echo "downloaded NinoTNC program file(s): "
    ls -1
    sudo mv * /usr/tarpn/etc/ninotnc/versions
    cd ..
    rm -rf latest_ninotnc
    cd ..
    rm -f latest_ninotnc.zip
    rm -rf temp_latest_ninotnc
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.010 No NinoTNC code versions available"  >> $TARPN_COMMAND_LOGFILE
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
    sudo mv tarpn /usr/tarpn/sbin/tarpn
    echo "##### TARPN command has been updated."
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.009. could not get new tarpn script - Aborting"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "ERROR706.009  Something is wrong.  I had access to the TARPN server but could"
    echo "              not acquire the tarpn script from the TARPN server.  "
    echo "              Abort, old TARPN script is intact."
    echo
    echo "##### Aborting"
    exit 1;
fi

#### Disable the console GETTY service
sudo systemctl stop serial-getty@ttyAMA0.service
sudo systemctl disable serial-getty@ttyAMA0.service

sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt




############ UPDATE runbpq.sh
cd /home/pi
tarpnget runbpq.sh
if [ -f runbpq.sh ];
then
    echo "##### received RUNBPQ - BPQ node execution script"
    chmod +x runbpq.sh
    sudo mv runbpq.sh /usr/tarpn/sbin/runbpq.sh
    echo "##### BPQ node execution script has been updated."
else
     echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
     echo "update.sh  ERROR706.007. Did not receive RUNBPQ from TARPN server"  >> $TARPN_COMMAND_LOGFILE
     resume_services
     echo "##### ERROR706.007    Did not receive RUNBPQ."
     echo
     echo "##### Abort -- complain to tarpn@groups.io."
     exit 1
fi

echo " "
echo " "
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
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.006. rx_tarpnstatapp.zip not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
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
    sudo mv rx_tarpnstatapp /usr/tarpn/sbin/rx_tarpnstatapp
    echo -e "##### rx_tarpnstatapp application has been updated.\n"
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR706.005. rx_tarpnstatapp not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
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
echo " "
echo " "


############################# UPDATE BBS-CHECKER APPLICATION FROM ZIP FILE

sudo killall bbs_checker_bw

cd /home/pi/zip-temp

tarpnget bbs_checker_bw.zip
##### now bbs_checker.zip should exist in the zip-temp directory
if [ -f /home/pi/zip-temp/bbs_checker_bw.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.004.  Failed to obtain bbs_checker_bw.zip from web server"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.004! Failed to obtain bbs_checker_bw.zip from the web server."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.004: Aborting"
   exit 1
fi

unzip bbs_checker_bw.zip

if [ -f /home/pi/zip-temp/bbs_checker_bw.app ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.003.  Error in unzipping bbs_checker_bw.zip"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR706.003! Error in unzipping bbs_checker_bw.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "ERROR706.003: Aborting"
   exit 1
fi

echo "##### received bbs_checker_bw.app  application"
chmod +x bbs_checker_bw.app
sudo mv bbs_checker_bw.app /usr/tarpn/sbin/bbs_checker_bw.app
/usr/tarpn/sbin/bbs_checker_bw.app v
echo "##### bbs_checker_bw.app has been updated."

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
### old ###     sudo mv bbs_checker /usr/tarpn/sbin/bbs_checker
### old ###     echo -e "##### bbs_checker application has been updated.\n"
### old ### else
### old ###     echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
### old ###     echo "ERROR3b. Did not receive bbs_checker from TARPN server"  >> $TARPN_COMMAND_LOGFILE
### old ###     resume_services
### old ###     echo "##### ERROR3b   Did not receive bbs_checker.  Leaving current copy alone"
### old ###     echo
### old ###     echo "##### Abort -- complain to tarpn@groups.io."
### old ###     exit 1
### old ### fi


###################### DONE WITH BBS-CHECKER APPLICATION from ZIP FILE

############################# UPDATE SENDROUTESTOCQ APPLICATION FROM ZIP FILE

sudo killall sendroutestocq

cd /home/pi/zip-temp

tarpnget sendroutestocq.zip
##### now sendroutestocq.zip should exist in the zip-temp directory
if [ -f /home/pi/zip-temp/sendroutestocq.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.002.  Failed to obtain SENDROUTESTOCQ.zip from web server"  >> $TARPN_COMMAND_LOGFILE
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
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR706.001.  Error in unzipping SENDROUTESTOCQ.zip"  >> $TARPN_COMMAND_LOGFILE
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
sudo mv sendroutestocq /usr/tarpn/sbin/sendroutestocq
echo "##### SENDROUTESTOCQ application has been updated."


### old ### ########### UPDATE sendroutestocq application
### old ### rm -f sendroutestocq
### old ### sudo killall sendroutestocq
### old ### wget -o /dev/null $_source_url/sendroutestocq
### old ### if [ -f sendroutestocq ];
### old ### then
### old ###     echo "##### received SENDROUTESTOCQ  application"
### old ###     chmod +x sendroutestocq
### old ###     sudo mv sendroutestocq /usr/tarpn/sbin/sendroutestocq
### old ###     echo -e "##### SENDROUTESTOCQ application has been updated.\n"
### old ### else
### old ###     echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
### old ###     echo "ERROR4a. SENDROUTESTOCQ not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
### old ###     resume_services
### old ###     echo "##### ERROR4a   Did not receive sendroutestocq.  Leaving current copy alone"
### old ###     echo
### old ###     echo "##### Abort -- complain to tarpn@groups.io."
### old ###     exit 1
### old ### fi

###################### DONE WITH SENDROUTESTOCQ APPLICATION from ZIP FILE





########### UPDATE configure_node_ini.sh
cd /home/pi
rm -f configure_node_ini.sh*
tarpnget configure_node_ini.sh
if [ -f configure_node_ini.sh ];
then
    echo "##### received CONFIGURE-NODE  command script"
    chmod +x configure_node_ini.sh
    sudo mv configure_node_ini.sh /usr/tarpn/sbin/configure_node_ini.sh
    echo -e "##### CONFIGURE-NODE script has been updated.\n"
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR705.001. CONFIGURE-NODE not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "##### ERROR705.001   Did not receive CONFIGURE-NODE.  Leaving current copy alone"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi




echo " "
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
    sudo mv tarpn-home-update.sh /usr/tarpn/sbin
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "tarpn-update: Updated the tarpn-home-update script" >> $HOME_LOGFILE
    echo "Use the command     tarpn home update    to get the latest version"
    echo "of NC4FG TARPN-HOME. "
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR705.002. TARPN-HOME UPDATER not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
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
     echo "tarpn-update: Delete the tarpn-home-go.flag" >> $HOME_LOGFILE
     sudo rm -rf /tmp/tarpn/tarpn_home_go.flag          ## added log entry
     sleep 2
   fi
fi

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
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "tarpn-update: ERROR705.003 trying to get TARPN-HOME to quit"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    echo "#### ERROR705.003  FAIL FAIL in the process of stopping TARPN HOME"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi
echo "##### TARPN-HOME is stopped"
echo -ne $(date) "" >> $HOME_LOGFILE
echo "tarpn-update: TARPN-HOME is stopped" >> $HOME_LOGFILE










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
       echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
       echo "tarpn-update: ERROR705.004 trying to download chatconfig.cfg"  >> $TARPN_COMMAND_LOGFILE
       resume_services
       pwd
       ls -lrats
       echo "##### ERROR705.004 chatconfig.cfg failed to download.  ABORT! "
       echo "##### Abort -- complain to tarpn@groups.io."
       exit 1
    fi
fi
cd /home/pi


################# getver.py
cd /home/pi
tarpnget getver.py
chmod +x getver.py
sudo mv getver.py /usr/tarpn/sbin

################# get RING.WAV file

cd /home/pi
tarpnget ring.wav
sudo mv ring.wav /usr/tarpn/sbin/ring.wav


######## UPDATE tarpn_background.sh
cd /home/pi
rm -f tarpn_background.sh*
rm -f tarpn-service.txt
rm -f tarpn.service*
echo "#### GETting tarpn background"
tarpnget tarpn_background.sh
echo "#### GETting tarpn.service"
##### WAS #### wget -o /dev/null $_source_url/tarpn.service
### tarpnget tarpn-service.txt
if [ -f tarpn_background.sh ];
then
    echo "##### received TARPN_BACKGROUND script"
##    if [ -f tarpn-service.txt ];
##    then
##        echo "##### received TARPN.SERVICE configuration file"
##        #### rename the service file from what the developer needs to what the Raspberry PI needs
##        mv tarpn-service.txt tarpn.service
##        sudo chown root tarpn.service
##        sudo chgrp root tarpn.service
        echo "##### moving new background shell script file into place"
        chmod +x tarpn_background.sh
        sudo mv tarpn_background.sh /usr/tarpn/sbin/tarpn_background.sh
        echo "##### TARPN_BACKGROUND script has been updated."
##        echo ##### reload service
##        sudo systemctl daemon-reload
##        sudo systemctl enable tarpn.service
        sudo systemctl start tarpn.service
##        echo "##### TARPN_BACKGROUND service has been reloaded and the"
##        echo "##### OS has been told to resume calling it."
##        echo -e "\n\n\n\n"
##        echo -ne $(date) "" >> $TARPN_SERVICE_LOG
##        echo "### UPDATE: started tarpn service"  >> $TARPN_SERVICE_LOG
##    else
##        echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
##        echo "update.sh  ERROR 6b trying to download tarpn.service"  >> $TARPN_COMMAND_LOGFILE
##        echo "##### ERROR6b   Did not receive TARPN.SERVICE."
##        echo
##        echo "##### Abort -- complain to tarpn@groups.io."
##        exit 1;
##    fi
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "update.sh  ERROR 7 trying to download TARPN_BACKGROUND"  >> $TARPN_COMMAND_LOGFILE
    resume_services
    pwd
    ls -lrats
    echo "##### ERROR7   Did not receive TARPN_BACKGROUND. "
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1;
fi
rm -f tarpn.service*
rm -f tarpn_background.sh*






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

### Delete a temporary downloaded copy of the script (may be left-over from failed install)
rm -f pi_shutdown_background.sh*

### Get new copy of the script
tarpnget pi_shutdown_background.sh
tarpnget gpio_for_controlpanel.sh
##tarpnget pi_shutdown-service.txt

### Check if we have the script file now.
if [ -f pi_shutdown_background.sh ];
then
   echo "##### received PI_SHUTDOWN_BACKGROUND script"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR10 trying to download PI_SHUTDOWN_BACKGROUND"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   pwd
   ls -lrats
   echo "##### ERROR10   Did not receive PI_SHUTDOWN_BACKGROUND."
   echo
   echo "##### Aborting"
   exit 1;
fi

### Check if we have the gpio script file.
if [ -f gpio_for_controlpanel.sh ];
then
   echo "##### received GPIO_FOR_CONTROLPANEL script"
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh  ERROR10.1 trying to download GPIO_FOR_CONTROLPANEL"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   pwd
   ls -lrats
   echo "##### ERROR10.1   Did not receive GPIO_FOR_CONTROLPANEL."
   echo
   echo "##### Aborting"
   exit 1;
fi

### if [ -f pi_shutdown-service.txt ];
### then
###    echo "##### Got PI_SHUTDOWN-SERVICE.TXT file from web server."
### else
###    ls -lrats
###    echo "##### ERROR10a   Did not receive PI_SHUTDOWN-SERVICE.TXT."
###    echo
###    echo "##### Aborting"
###    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
###    echo "update.sh  ERROR10a trying to download PI_SHUTDOWN-SERVICE.TXT"  >> $TARPN_COMMAND_LOGFILE
###    exit 1;
### fi
###
### #### rename the service file from what the developer needs to what the Raspberry PI needs
### mv pi_shutdown-service.txt pi_shutdown.service
###
### sudo rm /etc/systemd/system/pi_shutdown.service
### if [ -f /etc/systemd/system/pi_shutdown.service ];
### then
###    echo "#### ERROR8: pi_shutdown service did not delete. "
### else
###    sudo chown root ~/pi_shutdown.service
###    sudo chgrp root ~/pi_shutdown.service
###    sudo mv ~/pi_shutdown.service /etc/systemd/system/pi_shutdown.service
    if [ -f /etc/systemd/system/pi_shutdown.service ];
    then
       echo "##### pi_shutdown.service has been replaced"
       echo "##### moving new background shell scripts file into place"
       chmod +x pi_shutdown_background.sh
       sudo mv pi_shutdown_background.sh /usr/tarpn/sbin/pi_shutdown_background.sh
       echo "##### PI_SHUTDOWN_BACKGROUND script has been updated."
###
      chmod +x gpio_for_controlpanel.sh
      sudo mv gpio_for_controlpanel.sh /usr/tarpn/sbin/gpio_for_controlpanel.sh
      echo "##### GPIO_FOR_CONTROLPANEL script has been updated."

      echo ##### reload service
      sudo systemctl daemon-reload
      echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
      echo "update.sh is Enabling pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
      sudo systemctl enable pi_shutdown.service
      echo "##### PI_SHUTDOWN_BACKGROUND script has been updated and the"
      echo "##### OS has been told to resume calling it."
      echo -e "\n\n\n\n"
   else
      echo "##### ERROR9: pi_shutdown.service was deleted before update but we were"
      echo "#####        unable to re-install the new copy."
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh  ERROR9 trying to re-install pi_shutdown.service "  >> $TARPN_COMMAND_LOGFILE
      echo "##### Aborting"
      exit 1;
   fi
### fi


rm -f pi_shutdown-service.txt
rm -f pi_shutdown.service*
rm -f pi_shutdown_background.sh*
rm -f gpio_for_controlpanel.sh*



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
   else
      ls -lrats
      echo "##### ERROR34   Did not receive RX_TARPNSTAT.SH."
      echo
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh  ERROR34 trying to download RX_TARPNSTAT.SH "  >> $TARPN_COMMAND_LOGFILE
      echo "##### Aborting"
      exit 1;
   fi

   if [ -f rx_tarpnstat-service.txt ];
   then
      echo "##### Received RX-TARPNSTAT-SERVICE from web server"
      #### rename the service file from what the developer needs to what the Raspberry PI needs
   else
      ls -lrats
      echo "##### ERROR33   Did not receive RX_TARPNSTAT-SERVICE.TXT."
      echo
      echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
      echo "update.sh  ERROR34 trying to download RX_TARPNSTAT-SERVICE.TXT "  >> $TARPN_COMMAND_LOGFILE
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
         echo "##### moving new background shell script file into place"
         chmod +x rx_tarpnstat.sh
         sudo mv rx_tarpnstat.sh /usr/tarpn/sbin/rx_tarpnstat.sh
         echo "##### RX_TARPNSTAT.SH script has been updated."
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

else
###### Install RX_TARPNSTAT service

   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f rx_tarpnstat.sh*
   rm -f rx_tarpnstat.service
   rm -f rx_tarpnstat-service.txt

   ### Get new copy of the script
   tarpnget rx_tarpnstat.sh
   tarpnget rx_tarpnstat-service.txt

   ### Check if we have the script file now.
   if [ -f rx_tarpnstat.sh ];
   then
      echo "##### received RX_TARPNSTAT script"
   else
      ls -lrats
      echo "##### ERROR37   Did not receive STATUSMONITOR_BACKGROUND."
      echo
      echo "##### Aborting"
      exit 1;
   fi

   ### Check if we have the newly downloaded service file now.
   if [ -f rx_tarpnstat-service.txt ];
   then
      echo "##### received RX_TARPNSTAT-SERVICE.TXT"
   else
      ls -lrats
      echo "##### ERROR36   Did not receive RX_TARPNSTAT-SERVICE.TXT."
      echo
      echo "##### Aborting"
      exit 1;
   fi
   #### rename the service file from what the developer needs to what the Raspberry PI needs
   sudo chown root ~/rx_tarpnstat-service.txt
   sudo chgrp root ~/rx_tarpnstat-service.txt
   sudo mv rx_tarpnstat-service.txt rx_tarpnstat.service

   sudo rm /etc/systemd/system/rx_tarpnstat.service
   if [ -f /etc/systemd/system/rx_tarpnstat.service ];
   then
      echo "#### ERROR8f: RX_TARPNSTAT service did not delete. "
   else
      sudo mv ~/rx_tarpnstat.service /etc/systemd/system/rx_tarpnstat.service
      if [ -f /etc/systemd/system/rx_tarpnstat.service ];
      then
         echo "##### rx_tarpnstat.service has been replaced"
         echo "##### moving new background shell script file into place"
         chmod +x rx_tarpnstat.sh
         sudo mv rx_tarpnstat.sh /usr/tarpn/sbin/rx_tarpnstat.sh
         echo "##### rx_tarpnstat script has been updated."
         echo ##### reload service
         sudo systemctl daemon-reload
         sudo systemctl enable rx_tarpnstat.service
         echo "##### rx_tarpnstat script has been installed and the"
         echo "##### OS has been told to call it."
         echo -e "\n\n\n\n"
      else
         echo "##### ERROR35: rx_tarpnstat.service was deleted before update but we were"
         echo "#####        unable to re-install the new copy."
         echo
         echo "##### Aborting"
         exit 1;
      fi
   fi
fi
rm -f rx_tarpnstat-service.txt
rm -f rx_tarpnstat.service*
rm -f rx_tarpnstat.sh*









########## STATUSMONITOR SERVICE, SHELL SCRIPT and APPLICATIONS
######## Check to see if the user has the statusmonitor service installed.  If not, install it.  If so, just upgraded it.
echo "##### Check statusmonitor service and statusmonitor.sh"
cd /home/pi
if [ -f /etc/systemd/system/statusmonitor.service ];
then
   ######## UPDATE statusmonitor.sh

   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f statusmonitor.sh*

   ### Get new copy of the script
   tarpnget statusmonitor.sh
   tarpnget statusmonitor-service.txt

   ### Check if we have the script file now.
   if [ -f statusmonitor.sh ];
   then
      echo "##### received STATUSMONITOR_BACKGROUND script"

      ### Check if we have the newly downloaded service file now.
      if [ -f statusmonitor-service.txt ];
      then
         echo "##### received STATUSMONITOR-SERVICE.TXT script"
         #### rename the service file from what the developer needs to what the Raspberry PI needs
         sudo chown root ~/statusmonitor-service.txt
         sudo chgrp root ~/statusmonitor-service.txt
         sudo mv statusmonitor-service.txt statusmonitor.service

         sudo rm /etc/systemd/system/statusmonitor.service
         if [ -f /etc/systemd/system/statusmonitor.service ];
         then
            echo "#### ERROR8: statusmonitor service did not delete. "
         else
            sudo mv ~/statusmonitor.service /etc/systemd/system/statusmonitor.service
            if [ -f /etc/systemd/system/statusmonitor.service ];
            then
               echo "##### statusmonitor.service has been replaced"
               echo "##### moving new background shell script file into place"
               chmod +x statusmonitor.sh
               sudo mv statusmonitor.sh /usr/tarpn/sbin/statusmonitor.sh
               echo "##### STATUSMONITOR_BACKGROUND script has been updated."
               echo ##### reload service
               sudo systemctl daemon-reload
               sudo systemctl enable statusmonitor.service
               echo "##### STATUSMONITOR_BACKGROUND script has been updated and the"
               echo "##### OS has been told to resume calling it."
               echo -e "\n\n\n\n"
            else
               echo "##### ERROR9b: statusmonitor.service was deleted before update but we were"
               echo "#####        unable to re-install the new copy."
               echo
               echo "##### Aborting"
               exit 1;
            fi
         fi
      else
         ls -lrats
         echo "##### ERROR10c   Did not receive STATUSMONITOR-SERVICE.TXT."
         echo
         echo "##### Aborting"
         exit 1;
      fi
   else
      ls -lrats
      echo "##### ERROR10d   Did not receive STATUSMONITOR_BACKGROUND."
      echo
      echo "##### Aborting"
      exit 1;
   fi
else
   ######## INSTALL statusmonitor.sh

   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f statusmonitor.sh*
   rm -f statusmonitor.service
   rm -f statusmonitor-service.txt

   ### Get new copy of the script
   tarpnget statusmonitor.sh
   tarpnget statusmonitor-service.txt

   ### Check if we have the script file now.
   if [ -f statusmonitor.sh ];
   then
      echo "##### received STATUSMONITOR_BACKGROUND script"

      ### Check if we have the newly downloaded service file now.
      if [ -f statusmonitor-service.txt ];
      then
         echo "##### received STATUSMONITOR-SERVICE.TXT"
         #### rename the service file from what the developer needs to what the Raspberry PI needs
         mv statusmonitor-service.txt statusmonitor.service

         sudo rm /etc/systemd/system/statusmonitor.service
         if [ -f /etc/systemd/system/statusmonitor.service ];
         then
            echo "#### ERROR8d: statusmonitor service did not delete. "
         else
            chown root ~/statusmonitor.service
            chgrp root ~/statusmonitor.service
            sudo mv ~/statusmonitor.service /etc/systemd/system/statusmonitor.service
            if [ -f /etc/systemd/system/statusmonitor.service ];
            then
               echo "##### statusmonitor.service has been replaced"
               echo "##### moving new background shell script file into place"
               chmod +x statusmonitor.sh
               sudo mv statusmonitor.sh /usr/tarpn/sbin/statusmonitor.sh
               echo "##### STATUSMONITOR_BACKGROUND script has been updated."
               echo ##### reload service
               sudo systemctl daemon-reload
               sudo systemctl enable statusmonitor.service
               echo "##### STATUSMONITOR_BACKGROUND script has been updated and the"
               echo "##### OS has been told to resume calling it."
               echo -e "\n\n\n\n"
            else
               echo "##### ERROR9d: statusmonitor.service was deleted before update but we were"
               echo "#####        unable to re-install the new copy."
               echo
               echo "##### Aborting"
               exit 1;
            fi
         fi
      else
         ls -lrats
         echo "##### ERROR10e   Did not receive STATUSMONITOR-SERVICE.TXT."
         echo
         echo "##### Aborting"
         exit 1;
      fi
   else
      ls -lrats
      echo "##### ERROR10f   Did not receive STATUSMONITOR_BACKGROUND."
      echo
      echo "##### Aborting"
      exit 1;
   fi
fi
rm -f statusmonitor.service*
rm -f statusmonitor.sh*



######## Check to see if the user has the HOME service installed.  If not, install it.  If so, just upgraded it.
echo "##### Check TARPN HOME service and home_background.sh"
cd /home/pi
if [ -f /etc/systemd/system/home.service ];
then
   ######## UPDATE home_background.sh

   echo "##### home.service exists"
   ### Delete a temporary downloaded copy of the script (may be left-over from failed install)
   rm -f home-service.txt
   rm -f home.service*
   rm -f home_background.sh*

   ### Get new copy of the script
   tarpnget home_background.sh
   tarpnget home-service.txt

   ### Check if we have the home-service.txt file.
   if [ -f home-service.txt ];
   then
      echo "##### received HOME-SERVICE.TXT script"
      sudo chown root ~/home-service.txt
      sudo chgrp root ~/home-service.txt
      sudo mv home-service.txt home.service
   else
      echo "##### ERROR24a   Did not receive HOME-SERVICE.TXT.  "
      echo
      echo "##### Aborting"
      exit 1;
   fi

   ### Check if we have the script file now.
   if [ -f home_background.sh ];
   then
      echo "##### received HOME_BACKGROUND script"

      sudo rm -rf /usr/tarpn/sbin/home_background.sh
      sudo rm /etc/systemd/system/home.service
      if [ -f /etc/systemd/system/home.service ];
      then
         echo "#### ERROR22: home service did not delete. "
         echo
         echo "##### Aborting"
         exit 1;
      else
         sudo mv ~/home.service /etc/systemd/system/home.service
         if [ -f /etc/systemd/system/home.service ];
         then
             echo "##### home.service has been replaced"
             echo "##### moving new background shell script file into place"
             chmod +x home_background.sh
             sudo mv home_background.sh /usr/tarpn/sbin/home_background.sh
             echo "##### home_background script has been updated."
             echo ##### reload service
             sudo systemctl daemon-reload
             sudo systemctl enable home.service
             sudo systemctl start home.service
             echo "##### HOME_BACKGROUND script has been updated and the"
             echo "##### OS has been told to resume calling it."
             echo -e "\n\n\n\n"
         else
             echo "##### ERROR23: home.service was deleted before update but we were"
             echo "#####          unable to re-install the new copy."
             echo
             echo "##### Aborting"
             exit 1;
         fi
      fi
      else
        ls -lrats
        echo "##### ERROR24   Did not receive HOME_BACKGROUND.  "
        echo
        echo "##### Aborting"
        exit 1;
    fi


###### Install home service
else
   ls -lrats
   echo "##### ERROR25   home service not found.  "
   echo
   echo "##### Aborting"
   exit 1;
fi


rm -f home-service.txt
rm -f home.service*
rm -f home_background.sh*

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
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.052.  Failed to obtain linktest.zip from web server"  >> $TARPN_COMMAND_LOGFILE
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
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.051.  Error in unzipping linktest.zip"  >> $TARPN_COMMAND_LOGFILE
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

sudo mv linktest-app /usr/tarpn/sbin/linktest
rm linktest.zip



echo "#####"
echo "#### #import telnetlib3 to bookworm using N2IRZ Jan2026 method"
echo "#####"
sudo python3 -m pip install --break-system-packages telnetlib3
echo "Install should be complete."
echo "We are told that our use of telnetlib3 as root is ok in our system."
echo "Ignore the WARNING message."
echo
echo "Next line should have OK if this worked."
python3 -c "import telnetlib3; print('OK')"
echo
echo





echo "#####"
echo "##### Download g8bpq_link_stress.py"
echo "#####"
cd ~/zip-temp
tarpnget g8bpq_link_stress.zip
if [ -f g8bpq_link_stress.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.053.  Error in downloading g8bpq_link_stress.zip"  >> $TARPN_COMMAND_LOGFILE
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
   sudo mv g8bpq_link_stress.py /usr/tarpn/sbin/g8bpq_link_stress.py
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.054.  Error in unzip of g8bpq_link_stress.zip"  >> $TARPN_COMMAND_LOGFILE
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
cd ~


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
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.062.  Failed to obtain listen.zip from web server"  >> $TARPN_COMMAND_LOGFILE
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
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "update.sh ERROR706.061.  Error in unzipping listen.zip"  >> $TARPN_COMMAND_LOGFILE
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

sudo mv listen /usr/tarpn/sbin/listen
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
### old ###      sudo mv listen-app /usr/tarpn/sbin/listen
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


########## Test to see if python configparser is present.
#### If not, just exit.  We need configparser for tarpn home and that must be added by tarpn updateapps.
## not needed for bookworm 2024-02-15-##     echo "##### checking for python-configparser"
## not needed for bookworm 2024-02-15-##
## not needed for bookworm 2024-02-15-##     sudo rm -f /home/pi/home_test_file.txt
## not needed for bookworm 2024-02-15-##     dpkg-query -W -f='${binary:Package} ${Version}\t${Maintainer}\n' python-configparser | wc -l  > /home/pi/home_test_file.txt;
## not needed for bookworm 2024-02-15-##     _count=$( cat /home/pi/home_test_file.txt );
## not needed for bookworm 2024-02-15-##     sudo rm -f /home/pi/home_test_file.txt
## not needed for bookworm 2024-02-15-##     _value=1
## not needed for bookworm 2024-02-15-##     if [ $_value -ne $_count ]; then
## not needed for bookworm 2024-02-15-##         echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
## not needed for bookworm 2024-02-15-##         echo "ERROR. Python ConfigParser not present"  >> $TARPN_COMMAND_LOGFILE
## not needed for bookworm 2024-02-15-##         resume_services
## not needed for bookworm 2024-02-15-##         echo "###### ERROR706.008: python configparser not present.  "
## not needed for bookworm 2024-02-15-##         echo "######               Please fix by running   tarpn updateapps. "
## not needed for bookworm 2024-02-15-##         echo
## not needed for bookworm 2024-02-15-##         echo "##### Aborting"
## not needed for bookworm 2024-02-15-##         exit 1;
## not needed for bookworm 2024-02-15-##     else
## not needed for bookworm 2024-02-15-##         echo "##### python-configparser is present.  Moving on."
## not needed for bookworm 2024-02-15-##     fi
## not needed for bookworm 2024-02-15-##
## not needed for bookworm 2024-02-15-##



echo -ne $(date) " " >> $NPA_LOGFILE
echo "TARPN UPDATE complete. --  resuming pi-shutdown-service" >> $NPA_LOGFILE
sudo systemctl start neighbor_port_association.service
echo "Neighbor-Port-Assocation SERVICE started"

echo -ne $(date) " " >> $STATUSMONITOR_LOGFILE
echo "TARPN UPDATE complete. --  resuming statusmonitor-service" >> $STATUSMONITOR_LOGFILE
sudo systemctl start statusmonitor.service
echo "statusmonitor SERVICE started"

echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
echo "TARPN UPDATE complete.  Starting/resuming rx-tarpnstat service" >> $RX_TARPNSTAT_LOGFILE
sudo systemctl start rx_tarpnstat.service
echo "rx-tarpnstat SERVICE started"

echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
echo "TARPN UPDATE complete.  starting pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE
sudo systemctl start pi_shutdown.service
echo "pi_shutdown SERVICE started"

echo "#### starting/resuming tarpn-mon service"
echo -ne $(date) " " >> $TARPNMON_RUNNER_LOG
echo "TARPN UPDATE complete.  Starting/resuming tarpn-mon service" >> $TARPNMON_RUNNER_LOG
sudo systemctl start $TARPN_MON_SERVICE_FILE
echo "tarpn-mon SERVICE started"





echo
echo "##### successful completion of UPDATE"
echo "##### how long did that take?  "
uptime

echo -e "start time was "
cat ~/update_start_date.txt
echo -e "  end time is  "
date
rm ~/update_start_date.txt
sudo rm -f /usr/tarpn/etc/update_last_completed.txt
sudo rm -f ~/update_last_completed.txt
date > ~/update_last_completed.txt
sudo mv ~/update_last_completed.txt /usr/tarpn/etc/update_last_completed.txt


echo -ne $(date) " " >> $TARPN_COMMAND_LOGFILE
echo "update.sh: good exit" >> $TARPN_COMMAND_LOGFILE
echo -ne $(date) " " >> $TARPN_COMMAND_LOGFILE
echo -ne "update.sh: TARPN version is: " >> $TARPN_COMMAND_LOGFILE
grep "\--TARPNVERSION--" /usr/tarpn/sbin/tarpn | grep -v "grep" | cut -d# -f1 | cut -d\" -f2  >> $TARPN_COMMAND_LOGFILE

echo -ne $(date) "" >> $START_STOP_LOGFILE
echo "update.sh   complete"  >> $START_STOP_LOGFILE
echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
echo "update.sh  complete "  >> $TARPN_COMMAND_LOGFILE

echo
echo "Thank you for running tarpn update and we look forward to seeing you next time!"

sudo rm -rf /home/pi/zip-temp
rm -rf /home/pi/migrate.sh

exit 0

