#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2023.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

cd ~
echo "######"
sleep 0.5
echo "######"
sleep 0.5
#### 012  fix echo stating the name of the instructions web page.
#### 013  change the final shutdown from shutdown -rF  to shutdown -r.    The F is not supported in Wheezy JESSIE.
#### JESSIE-101  add support for JESSIE.
#### JESSIE-102  call for FSCK at the end when we reboot.
#### JESSIE-103  add debug code for downloading tarpn.service.
#### JESSIE-104  add a check for a flag to make sure tarpn-start-1 completed.
#### JESSIE-105  add a note that you can ignore the NODE INIT error message
#### JESSIE-106  add PI SHUTDOWN service
#### JESSIE-107  Remove some excess copied stuff from PI SHUTDOWN installer
#### JESSIE-108  tarpn.log has moved to /var/log/tarpn.log.  Change where we cat the log from.
#### JESSIE-109  do update and dist-upgrade again, now that the boot firmware has been updated.
#### JESSIE-110  use com7 for tarpn host instead of com4
#### JESSIE-111  Put back com4 link to tty8  sudo ln -s /home/pi/minicom/com4 tty8
#### STRETCH-001  support for STRETCH
#### STRETCH-002  turn off systemctl status because that prompted the user for Q and we don't need it.
#### STRETCH-003  add some -y options to apt-get for updates and upgrades
#### STRETCH-004  add install of statusmonitor.sh and bbs checker application
#### STRETCH-005  install linktest-app and listen-app
#### STRETCH-006  add download of rx_tarpnstat, service, app and shellscript.  Change the name of the service downloads from the web site from .service to -service.txt
#### STRETCH-007  add download of sendroutestocq application.
#### STRETCH-008  Minor changes to fix bug K4RGN ran into around tarpn-service.txt
#### STRETCH-009  Fix bug in tarpn_start1_finished.flag check
#### STRETCH-010  Write to tarpn_command.log on completion
#### BUSTER-001   Change the name to remove confusion from STRETCH to BUSTER
#### BUSTER-002   don't proceed if tarpn_start2 has already been run
#### BUSTER-003   remove specific TNC-PI claims.
#### BULLSEYE-001 don't subscribe to the I2C group anymore
#### BULLSEYE-002 fix trailing null in source-url
#### BULLSEYE-003 Create the tarpn.log before we use it - write good data into tarpncommand log file as well as tarpn.log.
#### BULLSEYE-004 Use the ZIP file version of rx_tarpnstatapp.
#### BULLSEYE-005 Move the install of ZIP to tarpn_start1dl.
#### BULLSEYE-006 move bbs-checker and sendroutestocq to being go via ZIP file.
#### BULLSEYE-007 fix two errors where the ZIP operations were wrongly referencing zip-temp.
#### BULLSEYE-008 Fix error in version string, affecting tarpn sysinfo.
#### BULLSEYE-009 Fix bug where rx_tarpnstat050app was still expected. Now rx_tarpnstatapp.
#### BULLSEYE-010 Add install of logfiletruncate.sh
#### BULLSEYE-011 delete/rm leftover zip-files before quiting tarpn-start2
#### BULLSEYE-012 fix install of linktest via zip for bullseye OS
#### BULLSEYE-013 fix install of listen via zip for bullseye OS
#### BULLSEYE-014 Change the name of the log we create here to tarpn_startstop.log - also create /var/log/tarpn_service.log here
#### BULLSEYE-015 tarpn.log features are moved to tarpn_service.log.
#### BULLSEYE-016 minor change to the ignore-the-error message before starting TARPN service.
#### BULLSEYE-017 move log file creation to tarpn-start-1dl
#### BULLSEYE-018 it is ok for tarpn_service.log to exist.  remove failure
#### BULLSEYE-019 just before starting pi-shutdown service, write to the log announcing that we're doing so.
#### BULLSEYE-020 Install Midori web browser
#### 10-15-2022 BULLSEYE-021  add a -y directive to the midori install
#### 03-22-2023 BULLSEYE-022  download 10K test file
#### 05-06-2023 BULLSEYE-023  use tarpnget and tarpnget_path_and_filename
#### 06-05-2023 BULLSEYE-024  Add ncpacket wallpaper for Raspberry PI desktop
#### 06-08-2023 BULLSEYE-025  Fix address for storing the ncpacket wallpaper
#### 06-08-2023 BULLSEYE-026  Change the error message numbers to be somewhat consistant and non redundant
#### 01-01-2024 BULLSEYE-027  Use CONTROL_PANEL log instead of PWRMAN log
#### 01-29-2024 BOOKWORM-030  Mod for Bookworm   /usr/tarpn etc..
#### 01-29-2024 BOOKWORM-031  fix typo in echo prints
#### 01-31-2024 BOOKWORM-032  put back "move along" print
#### 02-03-2024 BOOKWORM 033  getver.py
#### 02-23-2024 BOOKWORM 034  Add some uptime prints
#### 05-09-2024 BOOKWORM 035  Fix typo with the getver python script installation.
#### 10-18-2025 BOOKWORM 036  Add download and install of gpio_for_controlpanel.sh.
#### 10-27-2025 BOOKWORM 037  Fix bug in pi_shutdown-service installation.
#### 02-04-2026 Bookworm050 chgrp and chown tarpn.service to root.  Move install of logfiletruncate.sh to earlier as it is a prerequisite for tarpn_background.sh
#### 02-05-2026 Bookworm051 add /app to bbs_checker_bw.app  This script was downloading the bullseye version of bbs checker.  Fixed that too
#### 02-06-2026 Bookworm052 do rm -f bbs_checker_bw.zip after it is successfully unzipped.
#### 02-07-2026 Bookworm053 -use sudo when changing group or owner to root.  I think this was incorrect when installing services.

echo -e "######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n"
echo "###### =TARPN_START2.SH           Bookworm053=" #  --VERSION--#########
echo -e "\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n"

uptime

echo -e "\n######\n######\n######\n"

if [ -f /usr/tarpn/sbin/tarpn_start1_finished.flag ];
then
   echo " --- "
   echo "###### TARPN START 1 completed ok.  We're almost done"
   echo " --- "
   sleep 1
else
   sleep 1
   echo " -- "
   echo " -- "
   echo " -- "
   echo "### ERROR801.001:TARPN START 1 didn't finish.  Please restart "
   echo "###              the init process (from newly imaged boot drive) "
   echo "###              and complain to the author."
   echo " -- "
   exit 1
fi

if [ -f /usr/tarpn/etc/tarpn_start2_top.txt ];
then
   ls -lrats
   echo "### ERROR801.002:TARPN INSTALL 2 has already run. "
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io."
   echo "###              Aborting"
   exit 1;
fi
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);
rm -f ~/tarpn_start1*



source /usr/tarpn/sbin/tarpnget.sh
source /usr/tarpn/sbin/sleep_with_count.sh



echo "######"
echo "######   LOG-FILE-TRUNCATE script"
######### Install logfiletruncate.sh   -- this is a dependency in tarpn_background.sh
tarpnget logfiletruncate.sh

if [ -f logfiletruncate.sh ];
then
    chmod +x logfiletruncate.sh
    sudo rm -f /usr/tarpn/sbin/logfiletruncate.sh
    sudo mv logfiletruncate.sh /usr/tarpn/sbin/logfiletruncate.sh
    echo "##### logfiletruncate.sh script has been installed."
else
    echo
    echo
    echo "### ERROR801.007:Something is wrong.  Program had access to TARPN server but "
    echo "###              could not acquire the logfiletruncate.sh script from TARPN"
    echo "###              server.  Please send a missive about this to tarpn@groups.io."
    echo "###              Abort"
    exit 1;
fi

################################### INSTALL TARPN SERVICES

if [ -f ~/tarpn.service ];
then
   ls -lrats
   echo "### ERROR801.003:Premature existence of tarpn.service file in home directory"
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io."
   echo "###              Aborting"
   exit 1;
fi

echo -e "\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET-UPDATE"
echo "#####   --- I know we just did this."
echo "#####   --- It won't take long if there is nothing to update."
cd ~
sleep 1
sudo apt-get -y update
echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"

sleep 1
echo "#####"
echo "#####"
echo "##### APT-GET DIST-UPGRADE"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y dist-upgrade


echo -e "######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"

###################################### AFTER THIS we are not allowed to run TARPN START2 over again. ########################################
###################################### AFTER THIS we are not allowed to run TARPN START2 over again. ########################################
###################################### AFTER THIS we are not allowed to run TARPN START2 over again. ########################################
###################################### AFTER THIS we are not allowed to run TARPN START2 over again. ########################################

sudo touch /usr/tarpn/etc/tarpn_start2_top.txt





echo "#####"
echo "#####"
echo "##### Set up minicom port linkage so minicom can find host port"
echo "#####"
echo "#####"
sleep 1
cd /etc
sudo ln -s /home/pi/minicom/com4 tty8
sleep 1

cd ~
sleep 1
echo
echo "##### Turn up the volume to max.  You can adjust amixer cset numid=1 -- 100%  "
amixer cset numid=1 -- 100%
echo
sleep 1


echo "######"
echo "######"
echo "######"
echo "######"
echo "######  Adding service for tarpn background operations"

tarpnget tarpn-service.txt
##### now tarpn-service.txt should exist in the home directory
if [ -f ~/tarpn-service.txt ];
then
   echo " "
else
   ls -lrats
   echo "### ERROR801.004:Failed to obtain TARPN-SERVICE.TXT from the web server."
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io"
   echo "###              Note: Outputting debug information to be relayed to debugger."
   pwd
   echo "url"
   echo $_source_url
   echo "###              Aborting"
   exit 1
fi

cd ~

if [ -f /etc/systemd/system/tarpn.service ];
then
   echo "### ERROR801.005:TARPN SERVICE file already existed in /etc/system.d/system."
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io."
   echo "###              Aborting"
   exit 1;
fi




STARTSTOPLOGFILE="/var/log/tarpn_startstop.log"
TARPN_SERVICE_LOG="/var/log/tarpn_service.log"
TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"

echo -ne $(date) " " >> $STARTSTOPLOGFILE
echo "New TARPN install in progress - running tarpn-start2.sh" >> $STARTSTOPLOGFILE

echo -ne $(date) " " >> $TARPN_SERVICE_LOG
echo "New TARPN install in progress - running tarpn-start2.sh" >> $TARPN_SERVICE_LOG

sudo chown root tarpn-service.txt
sudo chgrp root tarpn-service.txt
sudo mv tarpn-service.txt tarpn.service
sudo mv tarpn.service /etc/systemd/system/tarpn.service
if [ -f /etc/systemd/system/tarpn.service ];
then
   echo "tarpn.service moved to system.d"
else
   echo " "
   echo " "
   echo " "
   pwd
   echo "/etc/systemd/system directory contains"
   ls -lrats /etc/systemd/system
   echo "local system /home/pi directory contains"
   ls -lrats
   echo " "
   echo "### ERROR801.006:TARPN SERVICE file failed to copy to /etc/system.d/system."
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io"
   echo "###              Aborting"
   exit 1;
fi


### get the desktop/wallpaper image for ncpacket
tarpnget ncpacket-wallpaper.gif
sudo mv ncpacket-wallpaper.gif /usr/share/rpd-wallpaper


################# getver.py
cd /home/pi
tarpnget getver.py
chmod +x getver.py
sudo mv getver.py /usr/tarpn/sbin


### Download files related to automatic operation   ##
tarpnget tarpn_background.sh
chmod +x tarpn_background.sh
sudo mv tarpn_background.sh /usr/tarpn/sbin


#### Disable background execution of G8BPQ node
sudo rm -f /usr/tarpn/etc/background.ini
sudo rm -f ~/bpq/background.ini
echo "BACKGROUND:OFF" > ~/background.ini
sudo mv ~/background.ini /usr/tarpn/etc/background.ini
sudo chown root /usr/tarpn/etc/background.ini

### Start TARPN service from the OS
echo "##### TARPN SERVICE file installed"
sudo systemctl daemon-reload
sudo systemctl enable tarpn.service
sudo systemctl start tarpn.service
echo "##### starting TARPN service  pause 10 seconds"
sleep_with_count_10
echo "######"
##sudo systemctl status tarpn.service
echo "######"
sleep 1
echo "###### NOTE!   You will see an error message that says:"
sleep 1
echo "#######        NODE INIT file not found "
echo "#######    and  Aborting in 180 seconds"
sleep 1
echo "#######"
echo "#######     That's OK.  Nothing to see here.  These are not the"
echo "                        error messages you are looking for."
sleep 1
echo "            Move along..."
sleep 1
echo "########"
sleep 1
echo "###########################################################"
sleep 1
cat $TARPN_SERVICE_LOG
echo "###########################################################"
sleep 2
echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"


echo
echo

echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"
echo "######"
echo "######   PI SHUTDOWN SERVICE"
echo "######  Adding service for raspberry pi automatic shutdown and UP notification"
echo "######"
sleep 1
echo "########"

cd ~

rm -f pi_shutdown_background.sh*
rm -f gpio_for_controlpanel.sh*


if [ -f /etc/systemd/system/pi_shutdown-service.txt ];
then
    echo
    echo
    echo "### ERROR801.008:PI SHUTDOWN SERVICE file already existed in /etc/system.d/system."
    echo "###              If you got this message during a clean install, then"
    echo "###              Please send a missive about this to tarpn@groups.io."
    echo "###              Aborting"
   exit 1;
fi

if [ -f ~/pi_shutdown.service ];
then
   echo "### ERROR801.009:Premature existence of pi_shutdown.service file in home directory"
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io."
   echo "###              Aborting"
   exit 1;
fi
rm -f pi_shutdown.service*

rm -f pi_shutdown-service.txt*
tarpnget pi_shutdown-service.txt
##### now pi_shutdown-service.txt  should exist in the home directory
if [ -f ~/pi_shutdown-service.txt ];
then
   echo "got PI_SHUTDOWN-SERVICE.TXT"
   mv pi_shutdown-service.txt pi_shutdown.service
   sudo chown root pi_shutdown.service
   sudo chgrp root pi_shutdown.service
   sudo mv ~/pi_shutdown.service /etc/systemd/system/pi_shutdown.service
else
   echo "### ERROR801.010:Failed to obtain pi_shutdown.service from the web page."
   echo "###              If you got this message during a clean install, then"
   echo "###              please send a missive about this to tarpn@groups.io"
   echo "###        Note: Outputting debug information to be relayed to support."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR: Aborting"
   exit 1
fi

if [ -f /etc/systemd/system/pi_shutdown.service ];
then
    echo "#####  PI SHUTDOWN SERVICE Installed ok"
else
    pwd
    ls -lrats
    echo "##### ERROR801.073   Could not install pi_shutdown.service."
    echo
    echo "###              If you got this message during a clean install, then"
    echo "###              please send a missive about this to tarpn@groups.io"
    echo "###        Note: Outputting debug information to be relayed to support."
    echo
    echo "##### Aborting"
    exit 1;
fi

### Download files related to automatic operation
echo "#####  Get GPIO-FOR-CONTROLPANEL.SH"
tarpnget gpio_for_controlpanel.sh
if [ -f gpio_for_controlpanel.sh ];
then
   echo "##### received GPIO_FOR_CONTROLPANEL script"
   chmod +x gpio_for_controlpanel.sh
   sudo mv gpio_for_controlpanel.sh /usr/tarpn/sbin
   rm -f gpio_for_controlpanel.sh*
else
   pwd
   ls -lrats
   echo "##### ERROR801.071   Did not receive GPIO_FOR_CONTROLPANEL."
   echo
   echo "##### Aborting"
   exit 1;
fi
tarpnget pi_shutdown_background.sh
if [ -f pi_shutdown_background.sh ];
then
   echo "##### received PI_SHUTDOWN_BACKGROUND script"
   chmod +x pi_shutdown_background.sh
   sudo mv pi_shutdown_background.sh /usr/tarpn/sbin
   rm -f pi_shutdown_background.sh*
else
   pwd
   ls -lrats
   echo "##### ERROR801.072   Did not receive GPIO_FOR_CONTROLPANEL."
   echo
   echo "##### Aborting"
   exit 1;
fi


### Start SHUTDOWN service from the OS
echo "##### start PI SHUTDOWN SERVICE"
echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
echo "tarpn-start2 is enabling and starting pi-shutdown-service" >> $TARPN_CONTROL_PANEL_LOGFILE

echo "##### Instruct systemctl to daemon-reload"
sudo systemctl daemon-reload
echo "##### Instruct systemctl to enable pi_shutdown service"
sudo systemctl enable pi_shutdown.service
echo "##### Instruct systemctl to START pi_shutdown service"
sudo systemctl start pi_shutdown.service
echo "##### starting PI SHUTDOWN service  pause 10 seconds"
sleep_with_count_10
##sudo systemctl status pi_shutdown.service
echo "###########################################################"
echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"



########### INSTALL LISTEN Application ###########################################3
########### INSTALL LISTEN Application ###########################################3
########### INSTALL LISTEN Application ###########################################3
########### INSTALL LISTEN Application ###########################################3
echo
echo "#### INSTALL LISTEN APPLICATION"
echo

cd /home/pi

tarpnget listen.zip
if [ -f /home/pi/listen.zip ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.012:Failed to obtain listen.zip from the web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR806.062: Aborting"
   exit 1
fi

unzip listen.zip

if [ -f /home/pi/listen ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.013:Error in unzipping listen.zip."
   echo "###              please send a missive about this to tarpn@groups.io"
   echo "###              Include the terminal output from this update."
   echo "###              Aborting"
   exit 1
fi

sudo mv listen /usr/tarpn/sbin/listen
rm listen.zip


echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"




########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
########### INSTALL LINKTEST Application ###########################################3
echo
echo "#### INSTALL LINKTEST APPLICATION"
echo

cd /home/pi

tarpnget linktest.zip
##### now linktest.zip should exist in the home directory
if [ -f /home/pi/linktest.zip ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.014:Failed to obtain linktest.zip from the web server."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR801.014: Aborting"
   exit 1
fi

unzip linktest.zip

if [ -f /home/pi/linktest-app ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.015:Error in unzipping linktest.zip."
   echo "                 please send a missive about this to tarpn@groups.io"
   echo "                 Include the terminal output from this update."
   echo "###              Aborting"
   exit 1
fi

sudo mv linktest-app /usr/tarpn/sbin/linktest
rm linktest.zip

echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"



################################################################################################################################################################
################################################################################################################################################################


############################# INSTALL BBS-CHECKER APPLICATION FROM ZIP FILE

echo "##### Starting get of BBS-CHECKER app"
cd /home/pi

tarpnget bbs_checker_bw.zip
##### now bbs_checker_bw.zip should exist in the home directory
if [ -f /home/pi/bbs_checker_bw.zip ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.016:Failed to obtain bbs_checker.zip from the web server."
   echo "                 please send a missive about this to tarpn@groups.io"
   echo "                 Include the terminal output from this update."
   echo "###              Aborting"
   exit 1
fi

echo "##### received BBS-CHECKER-BW.ZIP file"
unzip bbs_checker_bw.zip

if [ -f /home/pi/bbs_checker_bw.app ];
then
   echo "##### received bbs_checker  application"
   rm -f bbs_checker_bw.zip
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.017:Error in unzipping bbs_checker.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "###             Aborting"
   exit 1
fi

chmod +x bbs_checker_bw.app
sudo mv bbs_checker_bw.app /usr/tarpn/sbin/bbs_checker_bw.app
/usr/tarpn/sbin/bbs_checker_bw.app v
echo "##### bbs_checker_bw.app has been installed."
echo
###################### DONE WITH BBS-CHECKER APPLICATION from ZIP FILE

############################# INSTALL SENDROUTESTOCQ APPLICATION FROM ZIP FILE


cd /home/pi

echo "##### Starting get of SENDROUTESTOCQ app"
tarpnget sendroutestocq.zip
##### now sendroutestocq.zip should exist in the home directory
if [ -f /home/pi/sendroutestocq.zip ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.018:Failed to obtain SENDROUTESTOCQ.zip from the web server."
   echo "                 please send a missive about this to tarpn@groups.io"
   echo "                 Include the terminal output from this update."
   echo "###              Aborting"
   exit 1
fi
echo "##### received SENDROUTESTOCQ.ZIP file"

unzip sendroutestocq.zip

if [ -f /home/pi/sendroutestocq ];
then
   echo " "
else
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.019:Error in unzipping SENDROUTESTOCQ.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "###             Aborting"
   exit 1
fi

echo "##### received SENDROUTESTOCQ  application"
chmod +x sendroutestocq
sudo mv sendroutestocq /usr/tarpn/sbin/sendroutestocq
echo "##### SENDROUTESTOCQ application has been installed."
echo



###################### DONE WITH SENDROUTESTOCQ APPLICATION from ZIP FILE

################################################################################################################################################################
################################################################################################################################################################

echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"




###################################################
echo "#### get ring.wav file for bbs checker "
cd /home/pi
tarpnget ring.wav
sudo mv ring.wav /usr/tarpn/sbin/ring.wav

###################################################
######## INSTALL statusmonitor.sh

### Delete a temporary downloaded copy of the script (may be left-over from failed install)
rm -f statusmonitor.sh*

### Get new copy of the script
tarpnget statusmonitor.sh
tarpnget statusmonitor-service.txt

### Check if we have the script file now.
if [ -f statusmonitor.sh ];
then
   echo "##### received STATUSMONITOR_BACKGROUND script"

   if [ -f /etc/systemd/system/statusmonitor.service ];
   then
      echo "### ERROR801.020:statusmonitor service already existed!. "
      echo "###              Aborting"
      exit 1;
   else
      sudo chown root statusmonitor-service.txt
      sudo chgrp root statusmonitor-service.txt
      sudo mv statusmonitor-service.txt statusmonitor.service
      sudo mv ~/statusmonitor.service /etc/systemd/system/statusmonitor.service
      if [ -f /etc/systemd/system/statusmonitor.service ];
      then
         echo "##### statusmonitor.service has been installed"
         echo "##### moving new background shell script file into place"
         chmod +x statusmonitor.sh
         sudo mv statusmonitor.sh /usr/tarpn/sbin/statusmonitor.sh
         echo "##### STATUSMONITOR_BACKGROUND script has been installed."
         echo ##### start service
         sudo systemctl daemon-reload
         sudo systemctl enable statusmonitor.service
         sudo systemctl start statusmonitor.service
         echo "##### STATUSMONITOR_BACKGROUND script has been installed and the"
         echo "##### OS has been told to call it."
         echo -e "\n\n\n\n"
      else
         echo "### ERROR801.021:statusmonitor.service was not installed"
         echo "###              Aborting"
         exit 1;
      fi
   fi
else
      echo "### ERROR801.022:Did not receive STATUSMONITOR_BACKGROUND."
   echo
   echo "##### Aborting"
   exit 1;
fi
rm -f statusmonitor-service*
rm -f statusmonitor.service*
rm -f statusmonitor.sh*




###################################################
######## INSTALL RX_TARPNSTAT

### Delete a temporary downloaded copy of the script (may be left-over from failed install)
rm -f rx_tarpnstat.sh*

### Get new copy of the script
tarpnget rx_tarpnstat.sh
tarpnget rx_tarpnstat-service.txt

### Check if we have the script file now.
if [ -f rx_tarpnstat.sh ];
then
   echo "##### received rx_tarpnstat script"

   if [ -f /etc/systemd/system/rx_tarpnstat.service ];
   then
      echo "### ERROR801.023:rx_tarpnstat service already existed!. "
      echo "##### Aborting"
      exit 1;
   else
      sudo chown root rx_tarpnstat-service.txt
      sudo chgrp root rx_tarpnstat-service.txt
      sudo mv rx_tarpnstat-service.txt rx_tarpnstat.service
      sudo mv ~/rx_tarpnstat.service /etc/systemd/system/rx_tarpnstat.service
      if [ -f /etc/systemd/system/rx_tarpnstat.service ];
      then
         echo "##### rx_tarpnstat.service has been installed"
         echo "##### moving new background shell script file into place"
         chmod +x rx_tarpnstat.sh
         sudo mv rx_tarpnstat.sh /usr/tarpn/sbin/rx_tarpnstat.sh
         echo "##### STATUSMONITOR_BACKGROUND script has been installed."
         echo ##### start service
         sudo systemctl daemon-reload
         sudo systemctl enable rx_tarpnstat.service
         sudo systemctl start rx_tarpnstat.service
         echo "##### rx_tarpnstat script has been installed and the"
         echo "##### OS has been told to call it."
         echo -e "\n\n\n\n"
      else
         echo "### ERROR801.041:rx_tarpnstat.service was not installed"
         echo "##### Aborting"
         exit 1;
      fi
   fi
else
   echo "### ERROR801.042:Did not receive rx_tarpnstat.sh."
   echo
   echo "##### Aborting"
   exit 1;
fi
rm -f rx_tarpnstat-service*
rm -f rx_tarpnstat.service*
rm -f rx_tarpnstat.sh*


########### UPDATE rx_tarpnstatapp application
cd /home/pi
echo "ignore the no-process-found missive if printed here:"
sudo killall rx_tarpnstatapp
rm -f rx_tarpnstatapp*


echo "###### Install rx_tarpnstatapp"

tarpnget rx_tarpnstatapp.zip
if [ -f rx_tarpnstatapp.zip ];
then
    echo "##### received rx_tarpnstatapp  zip file"
    unzip rx_tarpnstatapp.zip
else
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "### ERROR801.046:tarpn-start2.sh: rx_tarpnstatapp.zip not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    pwd
    ls -lrats
    echo "###              Did not receive rx_tarpnstatapp.zip file.  FAIL FAIL FAIL"
    echo
    echo "###              Abort -- complain to tarpn@groups.io."
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
    echo "### ERROR801.051:tarpn-start2.sh: rx_tarpnstatapp not available from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    pwd
    ls -lrats
    echo "### ERROR801.053:Unable to unzip rx_tarpnstatapp!  FAIL FAIL FAIL"
    echo
    echo "##### Abort -- complain to tarpn@groups.io."
    exit 1
fi

sleep 1

echo "#####"
echo "##### Install Midori web browser"
sudo apt install midori -y

echo "#####"

uptime
echo  "######"

###############################################################################################################
###############################################################################################################
###############################################################################################################
###############################################################################################################

echo "Install 10K Test loop file "
######### Get a 10K test file and put it in the Files folder
if [ -d /home/pi/bpq/Files ]; then
   echo "  Files folder already exists"
else
   echo " Create bpq FILES folder"
   cd /home/pi/bpq
   mkdir Files
fi

cd /home/pi/bpq/Files
tarpnget g8bpqloop.txt
echo "Test loop file installed"

echo "######"
uptime
echo "######"



echo "#####"
echo "##### Download g8bpq_link_stress.py"
echo "#####"
tarpnget g8bpq_link_stress.zip
if [ -f g8bpq_link_stress.zip ];
then
   echo " "
else
   echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
   echo "### ERROR801.061:Error in downloading g8bpq_link_stress.zip"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.061:Error in dpwnloading g8bpq_link_stress.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "### ERROR801.061:Aborting"
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
   echo "### ERROR801.065.  Error in unzip of g8bpq_link_stress.zip"  >> $TARPN_COMMAND_LOGFILE
   resume_services
   echo "   Note: Outputting debug information to be relayed to support."
   echo "   Note: Outputting debug information to be relayed to support."
   echo "   Note: Outputting debug information to be relayed to support."
   echo "   Note: Outputting debug information to be relayed to support."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "### ERROR801.065:Error in unzip of g8bpq_link_stress.zip."
   echo "              please send a missive about this to tarpn@groups.io"
   echo "              Include the terminal output from this update."
   echo "### ERROR801.065:Aborting"
   exit 1
fi



#############################################################################################################
### Create null files with faked version strings to hold the places of files that don't get downloaded until they are needed


###############################################################################################################
###############################################################################################################
###############################################################################################################
###############################################################################################################





echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"
sleep 1
echo "##### Done.  After reboot you will be ready to test and/or "
echo "##### configure your TNC boards and to start BPQ node."
sleep 1
echo "#####"
echo "#####"

cd ~

rm -f bbs_checker.zip
rm -f rx_tarpnstatapp.zip
rm -f sendroutestocq.zip
rm -f test.txt
rm -f parse.tmp

sleep 1;
echo "######"
echo "######"
echo "######"
echo "######"
echo "######      Raspberry PI will now reboot.  All is going well so far."
echo "######      When we come back up, reconnect and try the   tarpn   command"
echo "######      as per the"
echo "######      Set Up Raspberry PI for TARPN Node - Make SDcard"
echo "######      web page"
sleep 1;
echo "######"
sleep 1;
echo "######"
echo "tarpn_start2" > /home/pi/tarpn_start2.flag;
sudo mv /home/pi/tarpn_start2.flag /usr/tarpn/sbin/tarpn_start2.flag;

TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"

echo -e "\n######\n######\n######\n"
uptime
echo -e "\n######\n######\n######\n"



uptime >> $TARPNCOMMANDLOGFILE
echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
echo "New TARPN install2 completed - rebooting in 6 seconds" >> $TARPNCOMMANDLOGFILE

echo -ne $(date) " " >> $STARTSTOPLOGFILE
echo "New TARPN install2 completed - rebooting in 6 seconds" >> $STARTSTOPLOGFILE

###### REBOOT in 5 seconds
echo -e "\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n######\n"
sleep_with_count_5
sudo touch /forcefsck
sudo shutdown -r now;
exit 0
