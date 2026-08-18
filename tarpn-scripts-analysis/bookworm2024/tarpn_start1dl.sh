#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

##### This script is supposed to be called in a particular order with other scripts.
##### Start with the recipe on the tarpn web site.  This script is called from
##### tarpn_start1.sh.

sleep 1
echo "###### This is the tarpn_start1dl script"
sleep 1

#### 034 11/11/2014  -- move PITNC utilities to /usr-local-sbin
#### 035 11/29/2014  -- move ringfolder to ~/ringfolder instead of ~/bpq/ringFolder
####                    use amixer to set volume all the way up.
#### 036 12/28/2014  -- get wiringPi GPIO tools.
#### 037  2/17/2015  -- setting pitnc* to +x was missing the *.  Why?
#### 038  2/24/2015  -- fix unexpected "fi" after installing GPIO wiringPi tools.
#### 039  3/09/2015  -- fix spelling error in echo to output
#### 040  3/28/2015  -- remove wolfram-engine from the apt-get package manager.
#### 041  4/16/2015  --  add -y option to apt-get in 2 places where it was missing.
#### 042  05/08/2015 --  remove a bunch of packages that we don't need including omxplayer, scratch.
#### 043  06-24-2015 --  Always get the same version of G8BPQ from the _source_url.
#### 044  06-25-2015 --  apt-get libpcap-dev and libcap0.8 in support of later G8BPQ versions
#### 045  07-01-2015 --  fix bug where G8BPQ was downloaded to the home directory instead of to ~/bpq
#### JESSIE 001  10-14-2015 -- fix bug in installing libcap 0.8 where the -y option was misspelled -7
#### JESSIE 002  10-15-2015 -- get piTermTCP from the source-url rather than from BPQ directly.  Install it on the Desktop
#### JESSIE 003  10-15-2015 -- turn on syntax coloring in VIM
#### JESSIE 004  10-15-2015 -- stop installing i2ckiss - stop installing ax25-tools and ax25-apps -- improve echo pretty printing
#### JESSIE 005  10-17-2015 -- call for FSCK at final reboot
#### JESSIE 006  11-08-2015 -- put back install of ax25-tools and ax25-apps.  Needed for i2c tools.
#### JESSIE 007  01-16-2016 -- Add a FLAG at the end of the script to tell TARPN-START-2 that it can run.
#### JESSIE 008  03-04-2016 -- Add install of Direwolf
#### JESSIE 009  03-04-2016 -- remove TRIGGERHAPPY  (note-- this change was in the field under 008 without the version changing!)
#### JESSIE 010  06-10-2016 -- put back WiringPi GPIO-- removed for JESSIE 008 for unknown reasons
#### JESSIE 011  10-10-2016 -- remove LibreOffice
#### JESSIE 012  10-11-2016 -- forgot the -y in apt-get removing libreoffice.
#### JESSIE 013  11-13-2016 -- still forgot the -y.
#### JESSIE 014  11-13-2016 -- Add -y to autoremove.
#### JESSIE 015  11-14-2016 -- Add 'echo' and printed remarks around firmware updates and other updates near the end of the script.
#### JESSIE 016  11-16-2016 -- more pretty-printing.  Stop installing XRDP
#### JESSIE 017   2-12-2017 -- add some prints of "uptime"
#### JESSIE 018   5-07-2017 -- Add TARPN HOME + Tornado and Python stuff.
#### JESSIE 019   5-09-2017 -- Get pitnc utilities from tarpn site.  They are no longer on the tnc-x site.
#### JESSIE 020   6-11-2017 -- use com7 for tarpn host instead of com4.
#### JESSIE 021   6-11-2017 -- get piminicom.zip from tarpn.net instead of from dropbox
#### JESSIE 022   7-29-2017 -- add python configparser.
#### JESSIE 023   7-29-2017 -- test version.. stop removing the extra packages like wolfram and libreoffice
#### JESSIE 024   7-29-2017 -- home_background.sh was not being downloaded.  Fix that.
#### JESSIE 025   7-30-2017 -- Restore removal of extra packages. .
#### STRETCH 001   8-22-2017 -- Remove get of HTML files from dropbox.  Don't have a new source yet.  Change SourceURL to 2017aug
### STRETCH 002    8-23-2017 -- don't display status of the systemctl anymore.  That ends up with a user response required.
### STRETCH 003    8-24-2017 -- Get firmware upgrade before applying it.
### STRETCH 004    9-08-2017 -- get rid of a note about hitting Q during dist-upgrade
### STRETCH 005    9-09-2017 -- add uptime at start and end.
### STRETCH 006    9-18-2017 -- Disable the console GETTY service.
### STRETCH 007    9-20-2017 -- remove Direwolf from the install.  This was taking too long for people with slow Internet.
### STRETCH 008    9-20-2017 -- Turn on the uart in boot/config.txt
### STRETCH 009    9-27-2017 -- update BPQ code downloader from updateapps.sh of today.  BBS-ready
### STRETCH 010   10-02-2017 -- fix typo in downloading bpq
### STRETCH 011   10-03-2017 -- remove conditioning in HOME SERVICE install.  We know it isn't installed already
### STRETCH 012   10-16-2017 -- add some -y options to apt-get
### STRETCH 013    1-22-2017 -- stop doing rpi-update.
### STRETCH 014    4-09-2018 -- if linbpq fails to install, abort the installation.  Fix bug in bpq install where setcap is done in the wrong directory. Stop setting syntax on for VIM editor
### STRETCH 015    4-09-2018 -- Install TELNET client
### STRETCH 016    5-05-2018 -- add check for starttime stamp -- abort, or if not exist, create it with epoch time
### STRETCH 017    5-05-2018 -- fix start time.  had perimissions error.
### STRETCH 018    5-12-2018 -- download make-local and boilerplate during install time.  This lets the first node commissioning/test be run with no internet?
### STRETCH 020    1-10-2019 -- update for TARPN HOME v2.0
### STRETCH 021    2-27-2019 -- Change web-server download from home.service to home-service.txt
### STRETCH 022    4-19-2019 -- Write to tarpn_command.log at the start
### BUSTER 001     6-26-2019 -- Buster instead of Stretch
### BUSTER 002    10-22-2019 -- add  "sudo apt-get install -y python-tornado"
### BUSTER 003     4-17-2020 -- add qttermtcp instead of bpqtermtcp
### BUSTER 004     6-07-2020 -- Install W4EIP's TRR program
### BUSTER 005     6-25-2020 -- change the name of qttermtcp from piqttermtcp to qt-term.  Pre-set .ini file with 127.0.1.1.
### BUSTER 006     8-16-2020 -- add bpq command extensions.  I mostly copied code from update.sh
### BUSTER 007     8-16-2020 -- add bpq command extensions.  I mostly copied code from update.sh
### BUSTER 008     8-28-2020 -- download trr.sh
### BUSTER 009     9-01-2020 -- Add install of the two bootload/version python programs, but not the ninotnc version files yet
### BUSTER 010     9-07-2020 -- Add install of the NinoTNC binary executables.
### BUSTER 011     10-31-2020 -- Add install of k a u p 8 r and USB-ident python scripts, compiled C app, and bash script.
### BUSTER 012     11-30-2020 -- Set get-or-set-kaup8r script to be executable
### BUSTER 013      2-13-2021 -- we don't need to remove minecraft, wolfram-alpha, scratch or nuscratch anymore.  they don't appear to be on here.
### BUSTER 014      3-24-2021 -- do apt-get install ftp
### BUSTER 015      5-19-2021 -- new bpq version
### BUSTER 016      5-21-2021 -- another new bpq version  6.0.21.40
### BUSTER 020      5-30-2021 -- add neighbor-port-association
### BUSTER 021      6-09-2021 --  stop installing KAUP8R functions
### BUSTER 022      6-21-2021  --  modify install of tarpn-home supporting python code so we get the python3 varients.
### BUSTER 023      6-30-2021  -- add test_internet.sh
### BUSTER 024      7-21-2021  -- fix some bugs in the install of NEIGBOR-PORT-ASSOCIATIOn - update python/tornado support to python3
### BUSTER 025     10-17-2021  -- install the node-calls-linktest script file
### BUSTER 026     10-17-2021  -- copy latest TARPN HOME updater code into the installer.  We had a bug where TARPN HOME latest was not getting installed here at the start.
### BUSTER 027     10-18-2021  -- Fix bug in TARPN HOME install where there was a portion done twice which resulted in erasure of the installed material.
### BUSTER 028     10-19-2021  -- Fix bug in TARPN HOME install where there was a portion done twice which resulted in erasure of the installed material.
### BUSTER 029     10-19-2021  -- Fix bug in TARPN HOME install where dateinstalled.txt wasn't written.
### BUSTER 030     10-20-2021  -- Fix typo in tarpn home installation.  Temporarily remove DIST-UPGRADE calls
### BUSTER 031     10-20-2021  -- put back the DIST-UPGRADE calls
### BULLSEYE 001   11-08-2021  -- start supporting BULLSEYE OS  no changes except the name.
### BULLSEYE 002   11-08-2021  -- change how I created date_installed to get rid of a permission denied message.
### BULLSEYE 003   11-08-2021  -- WIRINGPI did not install, amixer -PCM  PCM option not existing?, get rid of PITNC-GETPARAMS  -- attempt to set amixer sset Master PCM -- -0000
### BULLSEYE 004   11-08-2021  -- get WiringPi to install from a different git site. Not sure this is what we wanted or needed, but I have it.
### BULLSEYE 005   11-13-2021  -- fix trailing null in source-url.
### BULLSEYE 005   11-30-2021  -- Install ZIP.  Use ZIP to move the neighbor-port-association application.
### BULLSEYE 006   11-30-2021  -- Update the install procedure for neighbor-port-association app to use ZIP.
### BULLSEYE 007   11-30-2021  -- Add error reporting to minicom.zip and minicom.scr downloads.  Fix an error in the neighbor-port-association,zip downloading.
### BULLSEYE 008   11-30-2021  -- stop installing ax25 and i2c tools.   Install python-configparser twice
### BULLSEYE 009   02-05-2022  -- Improve some printed dialog
### BULLSEYE 010   09-13-2022  -- Stop installing Wiring-Pi.  This is now in the standard OS install
### BULLSEYE 011   09-13-2022  -- add write to startstop logfile just before rebooting at the end of this script
### BULLSEYE 012   09-13-2022  -- fix bug in access to start-stop log
### BULLSEYE 013   09-13-2022  -- Standardize the init of the log files
### BULLSEYE 014   05-06-2023  -- use tarpnget and sleep-with-count to do file downloads instead of wget and to do sleep of 5 and 10 seconds --   add sourcing of sleep-with-count and tarpnget
### BULLSEYE 015   05-26-2023  -- install python telnetlib3
### BULLSEYE 016   08-23-2023  -- bpq_6_0_24_2_aug_2023.zip  replaces bpq_6_0_21_40_mar_2021.zip
### BULLSEYE 017   08-28-2023  -- user https://tarpn.net when getting TARPN_Home_Latest.zip, instead of http://tarpn.net
### BULLSEYE 018   10-12-2023  -- bring back bpq_6_0_21_40_mar_2021.zip
### BULLSEYE 019   01-01-2024  -- use CONTROL PANEL log instead of PWRMAN log
### BOOKWORM 030   01-29-2024  -- mod for Bookworm.  /usr/tarpn etc..
### BOOKWORM 031   01-29-2024  -- move configure-node-ini.sh from /home/pi/bpq to /usr/tarpn/sbin
### BOOKWORM 033   01-29-2024  -- update the initd and systemd loads
### BOOKWORM 034   02-15-2024  -- chnage the tarpn home path to https://tarpn.net/f/bookworm
### BOOKWORM 035   02-23-2024  -- change some python install stuff (for TARPN HOME) as recommended by Fin
### BOOKWORM 036   03-23-2024  -- use the name control_panel_log_larva.log as a temp file name when creating the control panel log
### BOOKWORM 037   01-26-2025  -- fix the sudoers test to be in /usr/tarpn instead of /usr/local
### BOOKWORM 038   01-26-2025  -- Install WA2M tarpn-mon
### BOOKWORM 039   05-09-2025  -- Install service for tarpn-mon and create the statusmonitor logfile       tarpn_rxtarpnstat_service.log is correct.  tarpn_rx_tarpnstat_service.log is not
### BOOKWORM 040   12-18-2025  -- change home_service, tarpn-mon_service, and neighbor_port_association.service to owner and group is root
### BOOKWORM 041   02-07-2026  -- Install Python telnetlib3 using N2IRZ's method
### Bookworm042    02-07-2026  -- use sudo when changing group or owner to root.  I think this was incorrect when installing services.


echo "###### version number is:"
sleep 1
echo "###### tarpn_start1dl.sh Bookworm042   "

sleep 1
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### Verify proper environment for running this script"
echo "#####"
echo "#####"
uptime

########## The caller was supposed to have set up a source-URL for a web repository on the Internet
########## from which we download more scripts and code.  If not, then we're not being called in the right order.
########## We're only supporting a particular startup sequence.

if [ -f /usr/tarpn/etc/source_url.txt ];
then
    echo -n;
else
        echo "ERROR0: source URL file not found."
        echo "ERROR0: Aborting"
        exit 1
fi
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);



########## This script is supposed to be called tarpn_start1.sh and should be located in the present working directory.
if [ -f tarpn_start1.sh ];
then
    rm -f tarpn_start1.sh;
else
        echo "ERROR0: Incorrect calling sequence.  Please see documentation."
        echo "ERROR0: Aborting"
        exit 1
fi

####### Make sure we are in the home/pi directory
if [ $PWD == "/home/pi" ];
then
    rm -f tarpn_start1.sh;
else
        echo "ERROR0: Incorrect calling sequence.  Please see documentation."
        echo "ERROR0: Aborting"
        exit 1
fi



if [ -f tarpn_start1dl.sh ];
then
   echo
else
   echo "ERROR:  Help.  I don't know where I am.  Is this tarpn_start1dl.sh  ?"
   echo "ERROR: Aborting"
   exit 1;
fi





###########  Get UNIX EPOCH TIME and write it to the card.
if [ -f /usr/tarpn/sbin/tarpn_start1dl_starttime.txt ];
then
   echo "##### This looks like a re-install.  We shouldn't be doing that. "
   echo "violation:"
   ls -lrts /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
   echo "contents:"
   cat /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
   echo "current unix epoch time: "
   date +%s
   exit 1;
fi
date +%s > /home/pi/datetemp.txt
sudo mv /home/pi/datetemp.txt /usr/tarpn/sbin/tarpn_start1dl_starttime.txt
echo -n "This SD card is "
cat /usr/tarpn/sbin/tarpn_start1dl_starttime.txt

source /usr/tarpn/sbin/tarpnget.sh
source /usr/tarpn/sbin/sleep_with_count.sh

##echo "###### Install ZIP/UNZIP"
## sudo apt-get install zip
echo  "Install an FTP client"
sudo apt-get install -y ftp




echo "#####"
echo "##### Import telnetlib3 to bookworm using N2IRZ Jan2026 method"
echo "#####"
sudo python3 -m pip install --break-system-packages telnetlib3
echo "Install should be complete."
echo "We are told that our use of telnetlib3 as root is ok in our system."
echo "Ignore the error message."
echo
echo "Next line should have OK if this worked."
python3 -c "import telnetlib3; print('OK')"




################ Download the next script.  If we can't get it, then don't proceed with the install.
sleep 1
echo -e "\n\n\n\n\n\n"
echo "##### get TARPN install script #2 to use at next reboot"
sleep 1
rm -f tarpn_start2.*
tarpnget tarpn_start2.sh
if [ -f tarpn_start2.sh ];
then
   echo "##### script 2 downloaded successfully"
   chmod +x tarpn_start2.sh;
   sudo mv tarpn_start2.sh /usr/tarpn/sbin/tarpn_start2.sh;
else
   echo "ERROR:  Failure retrieving script #2.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi


ls /var/log

START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
echo "tarpn-start-installer" > tarpn_startstop.log
sudo mv tarpn_startstop.log $START_STOP_LOGFILE
sudo chmod 666 $START_STOP_LOGFILE
sudo chown root $START_STOP_LOGFILE
echo -ne $(date) "" > $START_STOP_LOGFILE
echo "Created" $START_STOP_LOGFILE >> $START_STOP_LOGFILE
echo "Created" $START_STOP_LOGFILE
echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $START_STOP_LOGFILE

TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
echo "tarpn-start-installer" > tarpn_command.log
sudo mv tarpn_command.log $TARPNCOMMANDLOGFILE
sudo chmod 666 $TARPNCOMMANDLOGFILE
sudo chown root $TARPNCOMMANDLOGFILE
echo -ne $(date) "" > $TARPNCOMMANDLOGFILE
echo "Created" $TARPNCOMMANDLOGFILE >> $TARPNCOMMANDLOGFILE
echo "Created" $TARPNCOMMANDLOGFILE
echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo " ### tarpn_start1dl init log file"  >> $TARPNCOMMANDLOGFILE

NPA_LOGFILE="/var/log/tarpn_neighbor_port_association.log"
echo "tarpn-start-installer" > tarpn_neighbor_port_association.log
sudo mv tarpn_neighbor_port_association.log $NPA_LOGFILE
sudo chmod 666 $NPA_LOGFILE
sudo chown root $NPA_LOGFILE
echo -ne $(date) "" > $NPA_LOGFILE
echo "Created" $NPA_LOGFILE >> $NPA_LOGFILE
echo "Created" $NPA_LOGFILE
echo -ne $(date) "" >> $NPA_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $NPA_LOGFILE

RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rxtarpnstat_service.log"
echo "tarpn-start-installer" > tarpn_rxtarpnstat_service.log
sudo mv tarpn_rxtarpnstat_service.log $RX_TARPNSTAT_LOGFILE
sudo chmod 666 $RX_TARPNSTAT_LOGFILE
sudo chown root $RX_TARPNSTAT_LOGFILE
echo -ne $(date) "" > $RX_TARPNSTAT_LOGFILE
echo "Created" $RX_TARPNSTAT_LOGFILE >> $RX_TARPNSTAT_LOGFILE
echo "Created" $RX_TARPNSTAT_LOGFILE
echo -ne $(date) "" >> $RX_TARPNSTAT_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $RX_TARPNSTAT_LOGFILE

SERVICELOGFILE="/var/log/tarpn_service.log"
echo "tarpn-start-installer" > tarpn_service.log
sudo mv tarpn_service.log $SERVICELOGFILE
sudo chmod 666 $SERVICELOGFILE
sudo chown root $SERVICELOGFILE
echo -ne $(date) "" > $SERVICELOGFILE
echo "Created" $SERVICELOGFILE >> $SERVICELOGFILE
echo "Created" $SERVICELOGFILE
echo -ne $(date) "" >> $SERVICELOGFILE
echo " ### tarpn_start1dl init log file"  >> $SERVICELOGFILE

HOME_LOGFILE="/var/log/tarpn_home.log"
echo "tarpn-start-installer" > tarpn_home.log
sudo mv tarpn_home.log $HOME_LOGFILE
sudo chmod 666 $HOME_LOGFILE
sudo chown root $HOME_LOGFILE
echo -ne $(date) "" > $HOME_LOGFILE
echo "Created" $HOME_LOGFILE >> $HOME_LOGFILE
echo "Created" $HOME_LOGFILE
echo -ne $(date) "" >> $HOME_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $HOME_LOGFILE

LINKSTATUSLOGFILE="/var/log/tarpn_linkstatus.log"
echo "tarpn-start-installer" > tarpn_linkstatus.log
sudo mv tarpn_linkstatus.log $LINKSTATUSLOGFILE
sudo chmod 666 $LINKSTATUSLOGFILE
sudo chown root $LINKSTATUSLOGFILE
echo -ne $(date) "" > $LINKSTATUSLOGFILE
echo "Created" $LINKSTATUSLOGFILE >> $LINKSTATUSLOGFILE
echo "Created" $LINKSTATUSLOGFILE
echo -ne $(date) "" >> $LINKSTATUSLOGFILE
echo " ### tarpn_start1dl init log file"  >> $LINKSTATUSLOGFILE

RUNBPQLOG="/var/log/tarpn_runbpq.log"
echo "tarpn-start-installer" > tarpn_runbpq.log
sudo mv tarpn_runbpq.log $RUNBPQLOG
sudo chmod 666 $RUNBPQLOG
sudo chown root $RUNBPQLOG
echo -ne $(date) "" > $RUNBPQLOG
echo "Created" $RUNBPQLOG >> $RUNBPQLOG
echo "Created" $RUNBPQLOG
echo -ne $(date) "" >> $RUNBPQLOG
echo " ### tarpn_start1dl init log file"  >> $RUNBPQLOG

TARPN_HOME_COPYLOG="/var/log/tarpn_home_webapp_copylog.log"
echo "tarpn-start-installer" > tarpn_home_webapp_copylog.log
sudo mv tarpn_home_webapp_copylog.log $TARPN_HOME_COPYLOG
sudo chmod 666 $TARPN_HOME_COPYLOG
sudo chown root $TARPN_HOME_COPYLOG
echo -ne $(date) "" > $TARPN_HOME_COPYLOG
echo "Created" $TARPN_HOME_COPYLOG >> $TARPN_HOME_COPYLOG
echo "Created" $TARPN_HOME_COPYLOG
echo -ne $(date) "" >> $TARPN_HOME_COPYLOG
echo " ### tarpn_start1dl init log file"  >> $TARPN_HOME_COPYLOG

TARPN_NINOTNC_GETALL_LOG="/var/log/tarpn_ninotnc_getall.log"
echo "tarpn-start-installer" > tarpn_ninotnc_getall.log
sudo mv tarpn_ninotnc_getall.log $TARPN_NINOTNC_GETALL_LOG
sudo chmod 666 $TARPN_NINOTNC_GETALL_LOG
sudo chown root $TARPN_NINOTNC_GETALL_LOG
echo -ne $(date) "" > $TARPN_NINOTNC_GETALL_LOG
echo "Created" $TARPN_NINOTNC_GETALL_LOG >> $TARPN_NINOTNC_GETALL_LOG
echo "Created" $TARPN_NINOTNC_GETALL_LOG
echo -ne $(date) "" >> $TARPN_NINOTNC_GETALL_LOG
echo " ### tarpn_start1dl init log file"  >> $TARPN_NINOTNC_GETALL_LOG

TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"
echo "tarpn-start-installer" > control_panel_log_larva.log
sudo mv control_panel_log_larva.log $TARPN_CONTROL_PANEL_LOGFILE
sudo chmod 666 $TARPN_CONTROL_PANEL_LOGFILE
sudo chown root $TARPN_CONTROL_PANEL_LOGFILE
echo -ne $(date) "" > $TARPN_CONTROL_PANEL_LOGFILE
echo "Created" $TARPN_CONTROL_PANEL_LOGFILE >> $TARPN_CONTROL_PANEL_LOGFILE
echo -ne $(date) "" >> $TARPN_CONTROL_PANEL_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $TARPN_CONTROL_PANEL_LOGFILE

TARPN_HOME_RUNTIME_LOGFILE="/var/log/tarpn_home_runtime.log"
echo "tarpn-start-installer" > tarpn_home_runtime.log
sudo mv tarpn_home_runtime.log $TARPN_HOME_RUNTIME_LOGFILE
sudo chmod 666 $TARPN_HOME_RUNTIME_LOGFILE
sudo chown root $TARPN_HOME_RUNTIME_LOGFILE
echo -ne $(date) "" > $TARPN_HOME_RUNTIME_LOGFILE
echo "Created" $TARPN_HOME_RUNTIME_LOGFILE >> $TARPN_HOME_RUNTIME_LOGFILE
echo "Created" $TARPN_HOME_RUNTIME_LOGFILE
echo -ne $(date) "" >> $TARPN_HOME_RUNTIME_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $TARPN_HOME_RUNTIME_LOGFILE

TARPN_TARPNSTAT_LOGFILE="/var/log/tarpn_tarpnstat.log"
echo "tarpn-start-installer" > tarpn_tarpnstat.log
sudo mv tarpn_tarpnstat.log $TARPN_TARPNSTAT_LOGFILE
sudo chmod 666 $TARPN_TARPNSTAT_LOGFILE
sudo chown root $TARPN_TARPNSTAT_LOGFILE
echo -ne $(date) "" > $TARPN_TARPNSTAT_LOGFILE
echo "Created" $TARPN_TARPNSTAT_LOGFILE >> $TARPN_TARPNSTAT_LOGFILE
echo "Created" $TARPN_TARPNSTAT_LOGFILE
echo -ne $(date) "" >> $TARPN_TARPNSTAT_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $TARPN_TARPNSTAT_LOGFILE

TARPNMON_RUNNER_LOG="/var/log/tarpn_mon.log";
echo "tarpn-start-installer" > tarpnmon-runner-temp.log
sudo mv tarpnmon-runner-temp.log $TARPNMON_RUNNER_LOG
sudo chmod 666 $TARPNMON_RUNNER_LOG
sudo chown root $TARPNMON_RUNNER_LOG
echo -ne $(date) "" > $TARPNMON_RUNNER_LOG
echo "Created" $TARPNMON_RUNNER_LOG >> $TARPNMON_RUNNER_LOG
echo "Created" $TARPNMON_RUNNER_LOG
echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
echo " ### tarpn_start1dl init log file"  >> $TARPNMON_RUNNER_LOG


STATUSMONITOR_LOGFILE="/var/log/tarpn_statusmonitor.log";
echo "tarpn-start-installer" > statusmonitor_temp.log
sudo mv statusmonitor_temp.log $STATUSMONITOR_LOGFILE
sudo chmod 666 $STATUSMONITOR_LOGFILE
sudo chown root $STATUSMONITOR_LOGFILE
echo -ne $(date) "" > $STATUSMONITOR_LOGFILE
echo "Created" $STATUSMONITOR_LOGFILE >> $STATUSMONITOR_LOGFILE
echo "Created" $STATUSMONITOR_LOGFILE
echo -ne $(date) "" >> $STATUSMONITOR_LOGFILE
echo " ### tarpn_start1dl init log file"  >> $STATUSMONITOR_LOGFILE

ls -l /var/log/tarpn*

uptime >> $TARPNCOMMANDLOGFILE
date >> $TARPNCOMMANDLOGFILE
echo "tarpn-start1dl.h" >> $TARPNCOMMANDLOGFILE

#### Disable the console GETTY service
sudo systemctl stop serial-getty@ttyAMA0.service
sudo systemctl disable serial-getty@ttyAMA0.service
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt
sudo sed -i "s^/usr/local/games:/usr/games^/usr/tarpn/sbin^" /etc/profile


#### Create a BPQ directory below /home/pi
echo "##### create bpq folder below /home/pi"

cd ~
rm -rf bpq
mkdir bpq



##### Get RUNBPQ.SH
echo "##### get RUNBPQ"
cd /home/pi
tarpnget runbpq.sh
if [ -f runbpq.sh ];
then
   echo "##### runbpq.sh downloaded successfully"
   chmod +x runbpq.sh;
   sudo mv runbpq.sh /usr/tarpn/sbin/runbpq.sh;
   echo "#####"
else
   echo "ERROR: Failure retrieving runbpq.sh.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi

#### Get TEST-INTERNET.SH
echo "##### get TEST-INTERNET"
cd /home/pi
tarpnget test_internet.sh
if [ -f test_internet.sh ];
then
   echo "##### runbpq.sh downloaded successfully"
   chmod +x test_internet.sh;
   sudo mv test_internet.sh /usr/tarpn/sbin/test_internet.sh;
   echo "#####"
else
   echo "ERROR: Failure retrieving test_internet.sh.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi



#### Get CONFIGURE_NODE_INI.SH
echo "##### get CONFIGURE NODE"
cd ~
tarpnget configure_node_ini.sh
if [ -f configure_node_ini.sh ];
then
   echo "##### configure_node_ini.sh downloaded successfully"
   chmod +x configure_node_ini.sh;
   sudo mv configure_node_ini.sh /usr/tarpn/sbin
   echo "#####"
else
   echo "ERROR: Failure retrieving configure_node_ini.sh.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi


#### Get BOILERPLATE.CFG
echo "##### get BOILERPLATE.CFG"
cd /home/pi/bpq
tarpnget boilerplate.cfg
if [ -f boilerplate.cfg ];
then
   echo "##### boilerplate.cfg downloaded successfully"
   echo "#####"
else
   echo "ERROR: Failure retrieving boilerplate.cfg.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi


#### Get MAKE_LOCAL_BPQ.SH
echo "##### get MAKE_LOCAL_BPQ.SH"
cd /home/pi/bpq
tarpnget make_local_bpq.sh
if [ -f make_local_bpq.sh ];
then
   echo "##### make_local_bpq.sh downloaded successfully"
   chmod +x make_local_bpq.sh;
   echo "#####"
else
   echo "ERROR: Failure retrieving make_local_bpq.sh.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi

#### Get CHATCONFIG.CFG
echo "##### get CHATCONFIG.CFG"
cd /home/pi/bpq
tarpnget chatconfig.cfg
if [ -f chatconfig.cfg ];
then
   echo "##### chatconfig.cfg downloaded successfully"
   echo "#####"
else
   echo "ERROR: Failure retrieving chatconfig.cfg.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi



##### Get TARPN
echo "##### get TARPN script"
cd /home/pi
tarpnget tarpn
if [ -f tarpn ];
then
   echo "##### tarpn downloaded successfully"
   chmod +x tarpn;
   sudo mv tarpn /usr/tarpn/sbin/tarpn;
   echo "#####"
else
   echo "ERROR:  Failure retrieving testbpq.  Something is wrong"
   echo "ERROR: Aborting"
   exit 1;
fi


#################################  Record the date and time that we HAVE been run.  This is used
#################################  to verify proper script operation as well as to note when this
#################################  node software package was brought up.
echo -e "\n\n\n\n\n\n"
echo "tarpn_start1dl" > /home/pi/tarpn_start1dl.flag;
echo "install date:" >> /home/pi/tarpn_start1dl.flag;
date >> /home/pi/tarpn_start1dl.flag;
sudo mv /home/pi/tarpn_start1dl.flag /usr/tarpn/sbin/tarpn_start1dl.flag;

#### Now download some packages with the apt-get package manager
sleep 1
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
uptime
echo "##### APT-GET UPDATE"
echo "#####"
echo "#####"
sleep 1
############## Do Package Update using apt-get package manager
###### apt-get update  retrieves a list showing the packages and versions available
sudo apt-get -y update


############# Delete some of the unnecessary bloatware that comes with the Raspbian install

sleep 1
echo -e "\n\n\n"
uptime

echo "############# APT-GET CLEAN to remove straggler stuff. "
echo -e "\n\n\n"
sleep 0.5
sudo apt-get clean
sleep 0.5
echo -e "\n\n\n"
uptime

echo "############# APT-GET AUTOREMOVE to remove more straggler stuff. "
echo -e "\n\n\n"
sleep 0.5
sudo apt-get -y autoremove
sleep 0.5
echo -e "\n\n\n"
uptime


echo "############# APT-GET CLEAN"
echo -e "\n\n\n"
sleep 0.5
sleep 0.5
sudo apt-get clean
echo -e "\n\n\n\n\n\n"
uptime

echo "############# AUTOREMOVE extra packages"
echo -e "\n\n\n"
sudo apt-get -y autoremove
sleep 0.5


###### apt-get dist-upgrade figures out what dependencies there are for packages
###### that have changed and adds and removes all packages such that the listed
###### packages are fully upgraded and will run.  -y says don't prompt for permission.
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET dist-upgrade -- upgrade the OS and remaining packages"
echo "#####"
uptime
echo "#####"
sleep 0.5
sudo apt-get -y dist-upgrade
sleep 0.5
echo -e "\n\n\n"

echo "###### OK, big one done. "
sleep 1
uptime
sleep 1
echo -e "\n\n\n"
echo "############# Now start installing things we need. "
echo -e "\n\n\n"
sleep 1


## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "##### APT-GET install of ax25-tools"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     sleep 1
## remove nov 30 2021 ##     sudo apt-get -y install ax25-tools
## remove nov 30 2021 ##     uptime


## remove nov 30 2021 ##     echo -e "\n\n\n\n\n\n"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "##### APT-GET install of ax25-apps"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     sleep 1
## remove nov 30 2021 ##     sudo apt-get -y install ax25-apps
## remove nov 30 2021 ##     uptime
## remove nov 30 2021 ##
## remove nov 30 2021 ##     echo -e "\n\n\n\n\n\n"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "##### APT-GET install of i2c-tools"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     echo "#####"
## remove nov 30 2021 ##     sleep 1
## remove nov 30 2021 ##     sudo apt-get -y --force-yes install i2c-tools
## remove nov 30 2021 ##     uptime
## remove nov 30 2021 ##

echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of screen"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install screen
uptime


echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of libcap2-bin"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install libcap2-bin
uptime

echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of libpcap0.8"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install libpcap0.8
uptime

echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of libpcap-dev"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install libpcap-dev
uptime



echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of Minicom dumb terminal program"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install minicom

uptime
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
sleep 0.5



echo "##### install  G8BPQ's version of Minicom"
sleep 0.5
echo "#####"
echo "#####"
sleep 1
cd /home/pi
rm -Rf minicom
rm -f in*
mkdir minicom
cd minicom
tarpnget piminicom.zip
if [ -f piminicom.zip ];
then
    echo "##### piminicom.zip downloaded."
else
    echo "ERROR-989 Something is wrong.  I had access to the proper web site but could"
    echo "          not acquire the piminicom.zip data from that web site.  "
    echo "          Abort"
    echo
    echo "      Abort.   Please contact tarpn@groups.io"
    exit 1;
fi


unzip piminicom.zip
if [ -f piminicom ];
then
    echo "##### piminicom extracted from zip archive."
else
    echo "####### ERROR-987 Something is wrong.  "
    echo "        Extracting piminicom from the zip file failed."
    echo
    echo "        Abort.   Please contact tarpn@groups.io"
    exit 1;
fi
chmod +x piminicom
tarpnget minicom.scr
if [ -f minicom.scr ];
then
    echo "##### minicom.scr downloaded."
else
    echo "ERROR-988 Something is wrong.  I had access to the proper web site but could"
    echo "          not acquire the minicom.scr data from that web site.  "
    echo
    echo "      Abort.   Please contact tarpn@groups.io"
    exit 1;
fi
cd /home/pi


uptime
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
sleep 0.5
echo "##### APT-GET install of conspy"
sleep 0.5
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y install conspy

uptime
echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "##### APT-GET install of Telnet client"
echo "#####"
echo "#####"
sleep 0.5
sudo apt-get -y install telnet

uptime
echo
echo
echo "#####"
echo "#####"
echo "##### APT-GET install of VIM editor"
echo "#####"
echo "#####"
sleep 0.5
sudo apt-get -y install vim
###echo "syntax on" > .vimrc

echo
#### According to this web page: http://wiringpi.com/download-and-install/    Wiring PI is now standard with the Raspbian install.   Note from July 9, 2022
##echo "#####"
##echo "#####"
##echo "##### GIT: install GPIO wiringPi tools"
##echo "#####  NOTE: disabled in BULLSEYE 003"
##echo "#####"
##git clone git://github.com/WiringPi/WiringPi
##cd WiringPi
##./build
##
cd ~

echo "#####"
echo "#####"
sleep 0.5
uptime

### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo "#####"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo "#####"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo "##### DIREWOLF"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo "#####"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- echo "#####"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- cd ~
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- wget -o /dev/null $_source_url/direwolf-master-18-03-20-355.zip
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- if [ -f direwolf-master-18-03-20-355.zip ];
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- then
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    sudo apt-get install libasound2-dev
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    ###sudo apt-get install socat
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    mkdir direwolf
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cd direwolf
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    unzip ../direwolf*.zip
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cd direwolf-master
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    make
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp CHANGES.md CHANGES.txt
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/User-Guide.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/Raspberry-Pi-APRS.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/Raspberry-Pi-APRS-Tracker.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/APRStt-Implementation-Notes.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/A-Better-APRS-Packet-Demodulator-Part-1-1200-baud.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp doc/A-Better-APRS-Packet-Demodulator-Part-2-9600-baud.pdf .
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    cp README.md README.txt
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    sudo make install
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    make install-conf
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    make install-rpi
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- else
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    echo "#### ERROR!!  DIREWOLF file not found in tarpn repository"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --    echo "#### ERROR!!  Please notify tarpn@groups.io"
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- fi
### ---  removed 9-20-2017 -- need to figure out a way to make this faster --
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- sleep 0.5
### ---  removed 9-20-2017 -- need to figure out a way to make this faster -- uptime


#echo -e "\n\n\n\n\n\n"
#echo "#####"
#echo "#####"
#echo "##### APT-GET install of Remote Desktop service"
#echo "#####"
#echo "#####"
#sleep 0.5
#sudo apt-get -y install xrdp







echo -e "\n\n\n\n"
echo "#####"
echo "#####"
echo "##### Get PI-LIN-BPQ"
echo "#####"
echo "#####"
sleep 0.5

latest_bpq_zipfile="bpq_6_0_21_40_mar_2021"   ## the actual file will end with .zip but don't specify the .zip here
latest_bpq_file="pilinbpq.dms"
update_directory="update_bpq_dir"


cd ~/bpq
echo "latest bpq zipfile name is " $latest_bpq_zipfile
echo "latest bpq file name is " $latest_bpq_file
echo "update directory name is " $update_directory
echo " "
echo
echo
echo "###"
echo -n "present working directory is "
pwd
echo "###"
echo "### removing existing update directory if it exists"
sudo rm -rf $update_directory
echo "###"
echo "### adding a new update directory"
mkdir $update_directory
cd $update_directory
echo "### cd into new update directory"
echo -e "### current working directory is "
pwd
echo "### Now download the newest BPQ version"
echo -e "getting it from" $_source_url
tarpnget $latest_bpq_zipfile.zip

if [ -f $latest_bpq_zipfile.zip ];
then
   echo "## Got new version of pilinbpq in update directory ##"
   pwd
   unzip $latest_bpq_zipfile.zip
   cd $latest_bpq_zipfile
   ls -lrat
   echo " "
   echo "## Rename to linbpq and make it executable ##"
   cp $latest_bpq_file linbpq
   chmod +x linbpq
   pwd
   ls -lrat *nbpq
else
   echo "### ERROR: we failed to download the required zip file!"
   echo "### Complain to tadd@mac.com! Send this entire log file if you can."
   exit 1
fi
echo "## Copy new ZIP file to bpq directory"
mv *.zip ~/bpq
echo "## mv to contents of the zip file"
cd $latest_bpq_zipfile
echo "##"
echo "## moved to update directory.  Now moving .zip and linbpq to home/pi/bpq directory"
echo "## Echo the present working directory so them-that-debugs can"
echo "## check that we are in the update directory where we need to be."
pwd
ls -l
echo "##"
echo "## now do the move of linbpq and HTMLPages to the /home/pi/bpq directory"
mv linbpq ~/bpq
mv HTMLPages ~/bpq/HTML
echo ###"
echo "## Move back to the bpq directory"
cd ~/bpq
echo "## Set meta-data for the linbpq executable"
sudo setcap "CAP_NET_RAW=ep CAP_NET_BIND_SERVICE=ep" linbpq
echo "##"
echo "## linbpq updated -- show working directory, and files named *nbpq."
pwd
ls -lrat *nbpq
echo "##"
echo -n "new version (./linbpq -v): "
./linbpq -v

echo "##"
echo "##### Got pi lin bpq"
sleep 1





############################# Get piqttermtcp  -- node operations console

echo -e "\n\n\n\n"
echo "#####"
echo "#####"
echo "##### Get PiTermBpq"
echo "#####"
echo "#####"
cd ~
tarpnget piqttermtcp.dms
if [ -f piqttermtcp.dms ];
then
    mv piqttermtcp.dms piqttermtcp
    chmod +x piqttermtcp
    mv piqttermtcp ~/Desktop/qt-term
    tarpnget QtTermTCP.ini
    if [ -f QtTermTCP.ini ];
    then
       mv QtTermTCP.ini ~/Desktop
       echo "##### qt-term has been installed."
    else
        echo "ERROR76.2 Something is wrong.  I had access to the proper web site but could"
        echo "          not acquire the QtTermTCP.ini program from that web site."
        echo "          Abort!  Contact KA2DEW and note this issue. "
        echo
        exit 1;
    fi
else
    echo "ERROR41   Something is wrong.  I had access to the proper web site but could"
    echo "          not acquire the piqttermtcp program from that web site."
    echo "          Abort!  Contact KA2DEW and note this issue. "
    echo
    exit 1;
fi
sleep 0.5



################## Get Ring noises folder
echo -e "\n\n\n\n"
echo "#####"
echo "#####"
echo "##### Get ring noises"
echo "#####"
echo "#####"
cd ~
rm -f ringnoises.zip
tarpnget ringnoises.zip
if [ -f ringnoises.zip ];
then
    rm -rf ringfolder
    mkdir ringfolder
    cd ringfolder
    unzip ../ringnoises.zip
    cd ..
    rm -f ringnoises.zip
    echo "##### RING Noises folder has been downloaded."
else
        echo "ERROR42   Something is wrong.  I had access to the proper web site but could"
        echo "          not acquire the ringnoises folder from that web site."
        echo "          Abort, no changes."
        echo
        exit 1;
fi
rm -f ringnoises.zip
sleep 0.5

##### Set volume to max
amixer sset Master PCM -- -0000



### This should be put back!! ### echo -e "\n\n\n\n"
### This should be put back!! ### echo "#####"
### This should be put back!! ### echo "#####"
### This should be put back!! ### echo "##### Get HTML Config files from DropBox"
### This should be put back!! ### echo "#####"
### This should be put back!! ### echo "#####"
### This should be put back!! ### sleep 0.5
### This should be put back!! ### cd ~/bpq
### This should be put back!! ### mkdir HTML
### This should be put back!! ### cd HTML
### This should be put back!! ### wget -o /dev/null https://dl.dropbox.com/u/31910649/HTMLPages.zip
### This should be put back!! ### unzip H*.zip
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### Get Change Keyboard to US version"
echo "#####"
echo "#####"
cd ~
sudo sed -i 's/XKBLAYOUT="gb"/XKBLAYOUT="us"/' /etc/default/keyboard



#### Install telnet client
sleep 0.5
echo -e "\n\n\n\n"
uptime
echo "##### Install TELNET client"
sleep 0.5

#### In cmdline.txt, stop using tty-async-serial as the console port
### before: dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p6 rootfstype=ext4 elevator=deadline rootwait
sleep 0.5
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### Remove config for having tty-async-serial as console port from /boot/cmdline.txt"
echo "#####"
echo "#####"
sleep 0.5
sudo sed -i "s~console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 ~~" /boot/cmdline.txt
### after: dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p6 rootfstype=ext4 elevator=deadline rootwait


#### raspi-blacklist.conf  remove the i2c blacklisting
sleep 0.5
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### in /etc/modprobe.d/raspi-blacklist.conf, remove blacklisting of i2c"
echo "#####"
echo "#####"
sleep 0.5
sudo sed -i "s~blacklist i2c-bcm2708~~" /etc/modprobe.d/raspi-blacklist.conf

#### Add i2c-dev to the /etc/modules file
sleep 1
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### in /etc/modules, add i2c device"
echo "#####"
echo "#####"
sleep 1
cp /etc/modules modules.work
echo "i2c-bcm2708" >> modules.work
echo "i2c-dev" >> modules.work
sudo mv modules.work /etc/modules
sudo chown root /etc/modules
sudo chgrp root /etc/modules
sudo chmod 644 /etc/modules


#### Remove the getty on tty2.  We're going to use that to output a log file from linbpq
#sleep 1
#echo
#echo
#echo "#####"
#echo "#####"
#echo "##### in /etc/inittab, stop spawning a GETTY on tty2"
#echo "##### so we can use tty2 for log output from LINBPQ"
#echo "#####"
#echo "#####"
#sleep 1
#sudo sed -i "s=2:23:respawn:/sbin/getty 38400 tty2=#2:23:respawn:/sbin/getty 38400 tty2=" /etc/inittab




##### Remove some temporary files.
sleep 1
uptime
echo -e "\n\n\n\n"
echo "#####"
echo "#####"
echo "##### Remove temporary files"
echo "#####"
echo "#####"
sleep 1
rm -f *.zip


##### link /dev/tty8 to the virtual port created by linbpq
sleep 1
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### Link comm ports together for minicom"
echo "#####"
echo "#####"
sleep 1
sudo mv /dev/tty8 /dev/tty8a
sudo ln -s /home/pi/com7 /dev/tty8

####### W4EIP TRR LINK QUALITY PROGRAM  #######################################################################################
####### W4EIP TRR LINK QUALITY PROGRAM  #######################################################################################
####### W4EIP TRR LINK QUALITY PROGRAM  #######################################################################################


########## Get the latest TRR
echo "#####"
echo "##### Downloading and installing TRR LINK QUALITY PROGRAM"
echo "#####"

cd ~

tarpnget trr.sh
tarpnget w4eip_link_quality.txt

if [ -f trr.sh ];
then
    chmod +x trr.sh
    sudo mv trr.sh /usr/tarpn/sbin/trr.sh
    echo "##### trr.sh script has been installed."
else
    echo "ERROR-TRR Something is wrong.  I had access to the proper web site but could"
    echo "          not acquire the trr.sh script from that web site.  "
    echo "          Abort"
    echo
    echo "      Abort.   Please contact tarpn@groups.io"
    exit 1;
fi
if [ -f w4eip_link_quality.txt ];
then
    chmod +x w4eip_link_quality.txt
    sudo mv w4eip_link_quality.txt /usr/tarpn/sbin/trr
    echo "##### trr command has been installed."
else
    echo "ERROR-TRR Something is wrong.  I had access to the proper web site but could"
    echo "          not acquire the w4eip_link_quality.txt data from that web site.  "
    echo "          Abort"
    echo
    echo "      Abort.   Please contact tarpn@groups.io"
    exit 1;
fi


######### Install the flashtnc.py program
rm -f flashtnc.py*
tarpnget flashtnc.py
if [ -f flashtnc.py ];
then
   chmod +x flashtnc.py
   sudo chown root flashtnc.py
   sudo mv flashtnc.py /usr/tarpn/sbin/flashtnc.py
   echo "### Installed flashtnc.py"
else
    echo "ERROR-flashtnc.py Something is wrong.  I had access to the proper web "
    echo "                  site but could not acquire the flashtnc.py program"
    echo "                  from that web site.  "
    echo "                  Abort"
    echo
    echo "      Abort.   Please contact tarpn@groups.io"
    exit 1;
fi
rm -f flashtnc.py


######### Install the get_tnc_version.py program
rm -f get_tnc_version.py*
tarpnget get_tnc_version.py
if [ -f get_tnc_version.py ];
then
   chmod +x get_tnc_version.py
   sudo chown root get_tnc_version.py
   sudo mv get_tnc_version.py /usr/tarpn/sbin/get_tnc_version.py
   echo "### Installed get_tnc_version.py"
else
    echo "ERROR-get_tnc_version.py Something is wrong.  I had access to the proper "
    echo "      web site but could not acquire the get_tnc_version.py program from"
    echo "      that web site.  "
    echo "      Abort.   Please contact tarpn@groups.io"
    echo
    echo "##### Aborting"
    exit 1;
fi
rm -f get_tnc_version.py


echo
echo "#####"
echo "#####"
echo "#####"
echo "##### Download NinoTNC Hex Files #######"
echo "#####"
echo "#####"
echo "#####"
###################### Create the /usr/tarpn/etc/ninotnc/versions directory and download current version files
sudo mkdir /usr/tarpn/etc/ninotnc
sudo mkdir /usr/tarpn/etc/ninotnc/versions


############## Get the latest NinoTNC firmware
rm -f latest_ninotnc.*
tarpnget latest_ninotnc.zip
if [ -f latest_ninotnc.zip ];
then
    mkdir temp_latest_ninotnc
    cd temp_latest_ninotnc
    unzip -q /home/pi/latest_ninotnc.zip
    rm -rf *MACOSX
    echo -ne "downloaded NinoTNC program file(s): "
    ls -1
    sudo mv * /usr/tarpn/etc/ninotnc/versions
    rm -f latest_ninotnc.zip
    cd ..
    rmdir temp_latest_ninotnc
    ls -lrats /usr/tarpn/etc/ninotnc/versions
else
    echo ""
    echo "ERROR-No NinoTNC code versions available.  Something is wrong.   "
    echo "      I had access to the proper web site but could not acquire "
    echo "      latest_ninotnc.zip from that web site. "
    echo "      Abort.   Please contact tarpn@groups.io"
    echo
    echo "##### Aborting"
    exit 1;
fi
cd ~
rm -f latest_ninotnc.*



####### NC4FG TARPN HOME #######################################################################################
####### NC4FG TARPN HOME #######################################################################################
####### NC4FG TARPN HOME #######################################################################################


sleep 1
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### NC4FG TARPN HOME installation"
echo "#####"
echo "#####"
sleep 1
### create TARPN HOME LOGFILE
echo -ne $(date) "" > /home/pi/tarpn_home.log
echo " tarpn-start1dl.sh installing TARPN HOME" >> /home/pi/tarpn_home.log
sudo chmod 666 /home/pi/tarpn_home.log
sudo mv /home/pi/tarpn_home.log $HOME_LOGFILE


echo -e "\n\n\n"
cd /home/pi
mkdir temporary_home_web_app
cd temporary_home_web_app
tarpnget_path_and_filename https://tarpn.net/f/bookworm TARPN_Home_Latest.zip
if [ -f /home/pi/temporary_home_web_app/TARPN_Home_Latest.zip ];
then
   echo "TARPN-HOME has been downloaded"
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-start1dl.sh  -- latest tarpn-home downloaded" >> $HOME_LOGFILE
else
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-start1dl.sh  -- FAIL -- unable to download TARPN-HOME!" >> $HOME_LOGFILE
   echo "TARPN-HOME download failed.  Abort install!"
   exit 1
fi
unzip TARPN_Home_Latest.zip
echo -ne "pwd="
pwd
ls -lrat
echo -ne "pwd="
pwd
if [ -f tarpn_home.pyc ];
then
    echo "UNZIP succeeded. "
else
    echo "##### ERROR: UNZIP failed.  ."
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo " tarpn-start1dl.sh  -- FAIL -- UNZIP error!" >> $HOME_LOGFILE
    exit 1;
fi

echo -ne $(date) "" >> $HOME_LOGFILE
echo " tarpn-home-update.sh  -- download and unzip OK. " >> $HOME_LOGFILE


sleep 1

######

cd /usr/tarpn/sbin
sudo mkdir home_web_app
sudo chmod 777 home_web_app
cd /usr/tarpn/sbin/home_web_app


date > /home/pi/dateinstalled.txt
sudo mv /home/pi/dateinstalled.txt .

if [ -f /usr/tarpn/sbin/home_web_app/dateinstalled.txt ];
then
  echo "TARPN-HOME folder is created in /usr/tarpn/sbin"
else
  echo "TARPN-HOME folder create failed.  Abort install!"
  exit 1
fi

sudo mv /home/pi/temporary_home_web_app/* .
sudo chown root *
sudo chmod +r *
echo -ne "pwd="
pwd
ls -lrat
echo -ne "pwd="
pwd
cd /usr/tarpn/sbin
sudo chmod 755 home_web_app
cd /home/pi
echo -ne "pwd="
pwd

sudo rm -rf /home/pi/temporary_home_web_app

#########


cd /home/pi
date > dateinstalled.txt

cd /usr/tarpn/sbin/home_web_app
sudo mv ~/dateinstalled.txt .

if [ -f /usr/tarpn/sbin/home_web_app/dateinstalled.txt ];
then
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " TARPN-HOME folder is created in /usr/tarpn/sbin" >> $HOME_LOGFILE
   echo "TARPN-HOME folder is created in /usr/tarpn/sbin"
else
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " TARPN-HOME folder create failed.  Abort install!" >> $HOME_LOGFILE
   echo -e "\n\n\n\n"
   echo "          TARPN-HOME folder create failed.  Abort install!"
   echo -e "\n\n\n\n"
   exit 1
fi

sudo rm -f /home/pi/tarpn-home-colors.json
sudo rm -f /home/pi/TARPN_Home.ini


echo -e "\n\n\n\n\n\n"
echo "#####"
echo "#####"
echo "#####"
echo "##### Install Python-dev, pyserial, and python-serial"
echo -e "\n\n"


uptime

echo -e "\n\n#####"
echo "##### APT-GET install of python3-iniparse"
echo "#####"
sudo apt-get install -y python3-iniparse

uptime
echo -e "\n\n#####"
echo "##### APT-GET install of python3-serial"
echo "#####"
sudo apt-get install -y python3-serial


echo -e "\n\n#####"
echo "##### APT-GET install of python3-tornado"
echo "#####"
sudo apt-get install -y python3-tornado


echo -e "\n\n#####"
echo "#####"
echo "#####"
echo -e "\n\n\n\n\n\n"
uptime
echo -e "\n\n\n\n\n\n"
echo "##### Install the OS service for TARPN-HOME"
cd /home/pi

echo "######"

cd ~

if [ -f /etc/systemd/system/home.service ];
then
   echo "ERROR!  home SERVICE file already existed in /etc/system.d/system."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "ERROR: Aborting"
   exit 1;
fi


if [ -f ~/home.service ];
then
   echo "ERROR!"
   echo "ERROR!  Premature existence of home.service file in home directory"
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io "
   echo "ERROR: Aborting"
   exit 1;
fi


tarpnget home_background.sh
tarpnget home-service.txt
##### now home_background.sh should exist in the home directory
if [ -f ~/home_background.sh ];
then
   ls -l home_background.sh
else
   echo "ERROR!  Failed to obtain home_background.sh from the web page."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR: Aborting"
   exit 1
fi
##### now home-service.txt should exist in the home directory
if [ -f ~/home-service.txt ];
then
   ls -l home-service.txt
else
   echo "ERROR!  Failed to obtain home-service.txt from the web page."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR: Aborting"
   exit 1
fi
sudo chown root home-service.txt
sudo chgrp root home-service.txt
sudo mv home-service.txt home.service
sudo mv ~/home.service /etc/systemd/system/home.service
if [ -f /etc/systemd/system/home.service ];
then
### Download files related to automatic operation
   chmod +x home_background.sh
   sudo mv home_background.sh /usr/tarpn/sbin

### Start HOME service from the OS
   echo "##### NC4FG's TARPN-HOME SERVICE file installed"
   sudo systemctl daemon-reload
   sudo systemctl enable home.service
   sudo systemctl start home.service
   echo "##### starting home service  pause 10 seconds"
   sleep_with_count_10
   ##sudo systemctl status home.service
   echo "###########################################################"
   sleep 1
else
   echo "ERROR!  HOME SERVICE file failed to copy to /etc/system.d/system."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "ERROR: Aborting"
   exit 1;
fi
rm -f home.service*
rm -f home_background.sh*

####### END OF NC4FG TARPN HOME #######################################################################################
####### END OF NC4FG TARPN HOME #######################################################################################
####### END OF NC4FG TARPN HOME #######################################################################################



######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION service ###################################################################
echo -e "\n\n\n\n\n\n"
sleep 1
uptime
echo -e "\n\n\n\n\n\n"
echo "##### service script for NEIGHBOR-PORT-ASSOCIATION"
cd /home/pi

echo "######"
tarpnget npa.sh
if [ -f ~/npa.sh ];
then
   ls -l npa.sh*
else
   echo "ERROR!  Failed to obtain npa.sh from the web page."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR: Aborting"
   exit 1
fi

######### INSTALL NEIGHBOR-PORT-ASSOCIATION app  ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION app  ###################################################################
######### INSTALL NEIGHBOR-PORT-ASSOCIATION app  ###################################################################
cd /home/pi

echo "##### INSTALL NEIGHBOR-PORT-ASSOCIATON APP #########"

tarpnget npa.zip
##### now neighbor_port_association-service.app should exist in the home directory
if [ -f /home/pi/npa.zip ];
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
   echo "ERROR4.993!  Failed to obtain npa.zip from the web server."
   echo "            please send a missive about this to tarpn@groups.io"
   echo "            Include the terminal output from this update."
   echo "ERROR4.993: Aborting"
   exit 1
fi

unzip npa.zip

if [ -f /home/pi/neighbor_port_association.app ];
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
   echo "ERROR4.992!  Error in unzipping npa.zip."
   echo "        please send a missive about this to tarpn@groups.io"
   echo "        Include the terminal output from this update."
   echo "ERROR4.992: Aborting"
   exit 1
fi

chmod +x neighbor_port_association.app
sudo mv neighbor_port_association.app /usr/tarpn/sbin
rm npa.zip

if [ -x /usr/tarpn/sbin/neighbor_port_association.app ];
then
   echo "##### Neighbor-Port-Assocation APP installed"
else
   echo "ERROR4.991!  Neighbor-Port-Assocation APP file failed to install."
   echo "            Please send a missive about this to tarpn@groups.io"
   echo "            Include the terminal output from this update."
   echo "ERROR4.991: Aborting"
   exit 1;
fi

############################3
echo "##### INSTALL NEIGHBOR-PORT-ASSOCIATON SERVICE #########"

if [ -f /etc/systemd/system/neighbor_port_association.service ];
then
   echo "ERROR!  neighbor_port_association SERVICE file already existed in /etc/system.d/system."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "ERROR: Aborting"
   exit 1;
fi

tarpnget neighbor_port_association-service.txt

##### now neighbor_port_association-service.txt should exist in the home directory
if [ -f ~/neighbor_port_association-service.txt ];
then
   ls -l neighbor_port_association-service.txt*
else
   echo "ERROR!  Failed to obtain neighbor_port_association-service.txt from the web page."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "   Note: Outputting debug information to be relayed to he who debugs."
   ls -lrat
   pwd
   echo "url"
   echo $_source_url
   echo "ERROR: Aborting"
   exit 1
fi

sudo chown root neighbor_port_association-service.txt
sudo chgrp root neighbor_port_association-service.txt
sudo mv neighbor_port_association-service.txt neighbor_port_association.service
sudo mv ~/neighbor_port_association.service /etc/systemd/system/neighbor_port_association.service

if [ -f /etc/systemd/system/neighbor_port_association.service ];
then
### Process the neighbor port association app and script file and put them into sbin
   chmod +x npa.sh
   sudo mv npa.sh /usr/tarpn/sbin
else
   echo "ERROR!  Neighbor-Port-Assocation SERVICE file failed to copy to /etc/system.d/system."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "ERROR: Aborting"
   exit 1;
fi

echo "##### NEIGHBOR-PORT-ASSOCIATON SERVICE installed #########"


if [ -x /usr/tarpn/sbin/npa.sh ];
then
   echo "##### Neighbor-Port-Assocation script installed"
else
   echo "ERROR!  Neighbor-Port-Assocation script file failed to install."
   echo "        If you got this message during a clean install, then"
   echo "        please send a missive about this to tarpn@groups.io"
   echo "ERROR: Aborting"
   exit 1;
fi


### Start NPA service from the OS
echo "##### Neighbor-Port-Assocation SERVICE file installed"
sudo systemctl daemon-reload
sudo systemctl enable neighbor_port_association.service
sudo systemctl start neighbor_port_association.service
echo "##### Neighbor-Port-Assocation SERVICE  pause 10 seconds"
sleep_with_count_10
##sudo systemctl status home.service
echo "###########################################################"
sleep 1

### put a token in the etc directory indicating that this version of npa was installed.
echo date >> npa_installed.001
sudo mv npa_installed.001 /usr/tarpn/etc

######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################
######### Done with NEIGHBOR-PORT-ASSOCIATION service ###################################################################




####### Install BPQ command extensions ##################################################################################
####### Install BPQ command extensions ##################################################################################
####### Install BPQ command extensions ##################################################################################
####### Install BPQ command extensions ##################################################################################

rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*


echo "### Install XINETD."
sudo apt-get -y install xinetd
sudo touch /usr/tarpn/etc/xinetd.005
echo "### XINETD installed."

echo " "
echo "Install CUSTOM-BPQ-COMMANDS.003."
if grep -q "63000" /etc/services; then
   echo "### ERROR541.7: "
   echo "### fail in CUSTOM-BPQ-COMMANDS.  Note: port 63000 already present in /etc/services"
   echo "### Contact tarpn@groups.io - this is a bug."
   exit 1;
fi
tarpnget custom-bpq-commands-services.003
if [ -f custom-bpq-commands-services.003 ];
then
   cp /etc/services /home/pi/services-copy                                            ## copy the services OS file to our local folder
   sudo cat /home/pi/custom-bpq-commands-services.003 >> /home/pi/services-copy       ## add the /etc/services info for BPQ command extension
   sudo chown root /home/pi/services-copy                                             ## make our copy of services look like the original root ownership
   sudo chgrp root /home/pi/services-copy                                             ## make our copy of services look like the original root group
   sudo mv /home/pi/services-copy /etc/services                                       ## put the new version of services back to the /etc directory where it lives
   sudo touch /usr/tarpn/etc/custom-bpq-commands-services.003       ## add the flag-file to tell us not to install this again
   echo "### version 003 BPQ custom commands SERVICES now newly installed"
   echo " "
else
   echo "### ERROR541.8: Fail in CUSTOM-BPQ-COMMANDS in retrieving the /etc/services details from tarpn.com"
   echo "###        Contact tarpn@groups.io  -- this is a bug."
   exit 1;
fi


echo " "
echo "Install version 005 BPQ custom commands INETD."
tarpnget custom-bpq-commands-inetd.005
if [ -f custom-bpq-commands-inetd.005 ];
then
   sudo mv /home/pi/custom-bpq-commands-inetd.005 /home/pi/inetdconf-copy       ## add the /etc/inetd.conf reconfig info for BPQ command extension
   sudo chown root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root ownership
   sudo chgrp root /home/pi/inetdconf-copy                          ## make our copy of services look like the original root group
   sudo mv /home/pi/inetdconf-copy /etc/inetd.conf                  ## put the new version of inetd.conf back to the /etc directory where it lives
   sudo touch /usr/tarpn/etc/custom-bpq-commands-inetd.005          ## add the flag-file to tell us not to install this again
   sudo /etc/init.d/xinetd restart                                  ## kick the xinetd service so it uses our new stuff
   echo "### version 005 BPQ custom commands INETD now installed"
   echo " "
else
   echo "### ERROR541.9: Fail in version 005 BPQ custom commands INETD in retrieving the /etc/inetd details from tarpn.com"
   echo "###             Contact tarpn@groups.io  -- this is a bug."
   exit 1;
fi


rm -f ~/custom-bpq-commands-services.*
rm -f ~/custom-bpq-commands-inetd*
rm -f ~/services*
rm -f ~/inetd*

echo " "
echo " "
echo " "
echo " "
echo " "


######### Install the Linux script
rm -f /home/pi/linux.sh
   tarpnget linux.sh
   chmod +x linux.sh
   sudo chown root linux.sh
   sudo mv /home/pi/linux.sh /usr/tarpn/sbin/linux.sh
   sudo touch /usr/tarpn/etc/linux-sh-call.003
   echo "### Installed linux.sh"
rm -f /home/pi/linux.sh

mkdir /home/pi/bpq-extensions
tarpnget sample.sh
chmod +x sample.sh
mv sample.sh /home/pi/bpq-extensions


echo " "
echo " "
echo " "

######### Install the TINFO script
rm -f /home/pi/tinfo.sh
   tarpnget tinfo.sh
   chmod +x /home/pi/tinfo.sh
   sudo chown root /home/pi/tinfo.sh
   sudo mv /home/pi/tinfo.sh /usr/tarpn/sbin/tinfo.sh
   sudo touch /usr/tarpn/etc/tinfo-sh-call.001
   echo "### Installed tinfo.sh"
rm -f /home/pi/tinfo.sh


echo " "
echo " "
echo " "
######### Install the LATLON script
rm -f /home/pi/latlon.sh
   tarpnget latlon.sh
   chmod +x /home/pi/latlon.sh
   sudo chown root /home/pi/latlon.sh
   sudo mv /home/pi/latlon.sh /usr/tarpn/sbin/latlon.sh
   sudo touch /usr/tarpn/etc/latlon-sh-call.001
   echo "### Installed latlon.sh"
rm -f /home/pi/latlon.sh


echo " "
echo " "
echo " "

######### Install the NODE-CALLS-LINKTEST application
sudo rm -f node_calls_linktest.sh*

tarpnget node_calls_linktest.sh

if [ -f node_calls_linktest.sh ];
then
    chmod +x node_calls_linktest.sh
    sudo rm -f /usr/tarpn/sbin/node_calls_linktest.sh
    sudo mv node_calls_linktest.sh /usr/tarpn/sbin/node_calls_linktest.sh
    echo "##### NODE_CALLS_LINKTEST script has been installed."
else
    echo "ERROR3.003   Something is wrong.  I had access to TARPN server but could"
    echo "             not acquire the NODE_CALLS_LINKTEST script from TARPN server.  "
    echo "             Abort"
    echo -ne $(date) "" >> $TARPN_COMMAND_LOGFILE
    echo "ERROR. Cound not acquire NODE_CALLS_LINKTEST script from TARPN server"  >> $TARPN_COMMAND_LOGFILE
    echo
    echo "##### Aborting"
    exit 1;
fi






echo " "
echo " "
echo " "
echo "###### Installing WA2M TARPN-MON web app."
echo " "

########################### TARPN-MON ###########################################################################################################
########################### TARPN-MON ###########################################################################################################
########################### TARPN-MON ###########################################################################################################

echo " "
echo " "
echo " "
echo "###### Install WA2M TARPN-MON web app."
echo " "

PATH_TO_TARPN_APPS="/usr/tarpn/sbin"
TARPN_MON_SERVICE_PATH_AND_FILE="/etc/systemd/system/tarpn_mon.service";
TARPN_MON_SERVICE_DOWNLOAD_NAME="tarpn-mon-service.txt";
TARPN_MON_SCRIPT_NAME="tarpnmon-runner.sh"
TARPN_MON_SCRIPT_PATH_AND_NAME="$PATH_TO_TARPN_APPS/tarpnmon-runner.sh"
TARPN_MON_SERVICE_FILE="tarpn_mon.service";



#### download a current copy of the tarpnmon-runner script

cd /home/pi
sudo rm -rf download_temp_folder
mkdir download_temp_folder
cd download_temp_folder




#### download  tarpn-mon
sudo rm -rf __MACOSX
tarpnget tarpn-mon.linux-arm32.zip

if [ -f tarpn-mon.linux-arm32.zip ];
then
    unzip tarpn-mon.linux-arm32.zip
    sudo rm -rf __MACOSX
    rm -rf tarpn-mon-linux-arm32.zip
    mv tarpn-mon.linux-arm32 tarpn-mon
    chmod +x tarpn-mon
    sudo rm -f $PATH_TO_TARPN_APPS/tarpn-mon
    sudo mv tarpn-mon $PATH_TO_TARPN_APPS/tarpn-mon
else
    echo "ERROR4.098!  Outputting debug information to be relayed to he who debugs."
    ls -lrat
    pwd
    echo "url"
    echo $_source_url
    echo "ERROR4.092!  Failed to obtain WA2M tarpn-mon from the web server."
    echo "        please send a missive about this to tarpn@groups.io"
    echo "        Include the terminal output from this update."
    echo "ERROR4.092: Aborting"
    exit 1
fi


echo
echo "install the systemd SERVICE for WA2M's TARPN-MON."





echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
echo "TARPN INSTALL is installing tarpn-mon service" >> $TARPNMON_RUNNER_LOG
echo "installing tarpn-mon service"

tarpnget $TARPN_MON_SERVICE_DOWNLOAD_NAME

#### now tarpn-mon-service.txt should exist in the home directory
if [ -f $TARPN_MON_SERVICE_DOWNLOAD_NAME ];
then
    mv $TARPN_MON_SERVICE_DOWNLOAD_NAME $TARPN_MON_SERVICE_FILE
    sudo chown root $TARPN_MON_SERVICE_FILE
    sudo chgrp root $TARPN_MON_SERVICE_FILE
    sudo mv $TARPN_MON_SERVICE_FILE $TARPN_MON_SERVICE_PATH_AND_FILE
    echo " "
    ### Start TARPN-MON service from the OS
    sudo systemctl daemon-reload
    sudo systemctl enable $TARPN_MON_SERVICE_FILE
    sudo systemctl start $TARPN_MON_SERVICE_FILE

    echo -ne $(date) "" >> $TARPNMON_RUNNER_LOG
    echo "tarpn-mon-service is enabled - waiting for start."  >> $TARPNMON_RUNNER_LOG
else
    echo "ERROR4.098!  Outputting debug information to be relayed to he who debugs."
    ls -lrat
    pwd
    echo "url"
    echo $_source_url
    echo "ERROR4.098!  Failed to obtain tarpn-mon-service.txt from the web server."
    echo "        please send a missive about this to tarpn@groups.io"
    echo "        Include the terminal output from this update."
    echo "ERROR4.098: Aborting"
    exit 1
fi


echo "Get runner script for tarpn-mon and install it."
tarpnget $TARPN_MON_SCRIPT_NAME
if [ -f $TARPN_MON_SCRIPT_NAME ];
then
    sudo chmod +x $TARPN_MON_SCRIPT_NAME
    sudo mv $TARPN_MON_SCRIPT_NAME $TARPN_MON_SCRIPT_PATH_AND_NAME
    echo "##### TARPN-MON-RUNNER file installed"
    sleep 1
else
    echo "ERROR4.099! TARPN-MON SERVICE file failed"
    echo "              to copy to /etc/system.d/system."
    echo "              Please send a missive about this to tarpn@groups.io"
    echo "              Include the terminal output from this update."
    echo "ERROR4.099: Aborting"
    exit 1;
fi



cd /home/pi
sudo rm -rf /home/pi/download_temp_folder

######### Done with TARPN-MON service ###################################################################
######### Done with TARPN-MON service ###################################################################
######### Done with TARPN-MON service ###################################################################



####### Done with installing BPQ command extensions ##################################################################################
####### Done with installing BPQ command extensions ##################################################################################
####### Done with installing BPQ command extensions ##################################################################################
####### Done with installing BPQ command extensions ##################################################################################




echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### APT-GET-UPDATE"
echo "#####"
echo "#####"
cd ~
sleep 1
sudo apt-get -y update

sleep 1
echo -e "\n\n\n\n"
uptime
echo "#####"
echo "#####"
echo "##### APT-GET DIST-UPGRADE"
echo "#####"
echo "#####"
sleep 1
sudo apt-get -y dist-upgrade
uptime


######## Write a flag to tell  TARPN-START 2 that we finished TARPN-START-1.
######## This keeps somebody from running them out of order or running them at the same time.
sudo touch /usr/tarpn/sbin/tarpn_start1_finished.flag



sleep 1;
echo -e "\n\n\n\n\n\n"
echo "######"
echo "######"
echo "######"
echo "######"
echo "######      Raspberry PI will now reboot.  All is going well so far."
echo "######      When we come back up, reconnect and do the command   tarpn"
echo "######      as per the   Initialize Raspberry PI for TARPN Node    web page"
sleep 1;
echo "######"

sleep 1;
###### Touching /FORCEFSCK will cause File System Check to run the next time Linux boots
sudo touch /forcefsck
echo "######"

sleep 1;

uptime

###### Shutdown with automatic restart
echo "tarpn-start-installer" > tarpn_startstop.log
sudo mv tarpn_startstop.log $START_STOP_LOGFILE
sudo chmod 666 $START_STOP_LOGFILE
sudo chown root $START_STOP_LOGFILE
echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### tarpn_start1dl do reboot at end"  >> $START_STOP_LOGFILE
sleep 1
sudo shutdown -r now;
exit 0
