#!/bin/bash

### This version of runbpq.sh is compatable with the     >>>>>>> make_local_bpq.sh <<<<<<<<

#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was
##### and send a copy to tadd@mac.com.
##### Thanks. - Tadd Raleigh NC>

##### This script is run from the command "tarpn test" or from the OS as an init service called by root.
##### This script depends on a source_url.txt file specifying where on the Internet
##### the boilerplate and scripts are found.  source_url.txt must exist even though
##### the Internet might be broken. If the Internet doesn't work, then we use
##### the bpq32.cfg file created last time this script run.

##### If there is Internet, and source_url.txt is found, and node.ini is found, then
##### this script will attempt to download make_local_bpq.sh and boilderplate.cfg files
##### from the URL specified in source_url.txt.
##### If that fails, then just use the bpq32.cfg created previously.
##### If it successeds, then copy node.ini to the ~/bpq directory, and run the new make_local_bpq.sh
##### to create bpq32.cfg.



##### CHECK PROCESS
##### This looks to see if the specified process is running.
##### returns 0 if not running.  Returns 1 if running
check_process()
{
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

tarpnsleep() {
yy=1
while [ $yy -le $1 ]
do
   yy=$(( $yy + 1 ))

   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];                     #### Does UPDATE.SH want this stopped?
   then
      echo -ne $(date) "" >> $RUNBPQLOG
      echo "Exit from sleep $1 for stop-service-semaphore" >> $RUNBPQLOG
      exit 0;                                                              #### Wants us stopped.   Exit immediately
   fi
   sleep 1
done

}

HOME_LOGFILE="/var/log/tarpn_home.log"
RUNBPQLOG="/var/log/tarpn_runbpq.log";

STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"



if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];                     #### Does UPDATE.SH want us not to start??
then
   exit 0;                                                              #### Wants us stopped.   Exit immediately
fi




### TARPN HOME shouldn't be running right now.  Stop it right now.
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    sudo rm -rf /usr/local/sbin/home_web_app/remove_me_to_stop_server.txt   ## stop a TARPN-HOME v2.02 or earlier
    if [ -d /tmp/tarpn ]; then                                             ### stop a TARPN-HOME v2.10 or later
       if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
         echo -ne $(date) "" >> $HOME_LOGFILE
         echo "runbpq.sh at start: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
         sudo rm -rf /tmp/tarpn/tarpn_home_go.flag      ### added log write
       fi
    fi
    tarpnsleep 5
fi


check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    sudo killall python
    tarpnsleep 5
fi



if [ -e $RUNBPQLOG ];
then
   sudo chmod 666 $RUNBPQLOG
   sudo chown pi $RUNBPQLOG
else
   echo " " > tarpn_runbpq.log
   chmod 666 tarpn_runbpq.log
   sudo chown pi tarpn_runbpq.log
   sudo mv tarpn_runbpq.log $RUNBPQLOG
fi

echo -ne $(date) " " >> $RUNBPQLOG
echo "runbpq.sh: called by " $(whoami)  >> $RUNBPQLOG
sudo chmod 666 $RUNBPQLOG
sudo chown pi $RUNBPQLOG

############## Make sure the execution is from pi or root
if [ $(whoami) == "pi" ];
then
   echo "runbpq.sh:  hello user >>pi<<"
else
   if [ $(whoami) != "root" ];
   then
      echo "Hello user " $(whoami);
      echo "This script can only be run by user pi or by background automation called by root."
      exit 1
   fi
fi


cd /home/pi/bpq;
echo "------"                 >> $RUNBPQLOG;
echo -ne $(date) " " >> $RUNBPQLOG
echo "start of runbpq script" >> $RUNBPQLOG;


sudo chown pi $RUNBPQLOG
sudo chmod 666 $RUNBPQLOG



START_STOP_LOGFILE="/var/log/tarpn_startstop.log"




echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### RUNBPQ starting"  >> $START_STOP_LOGFILE

#### Version 42   -- add killall piminicom at start
#### Version 43   -- 2014-11-29  up until now, this script copied pilinbpq to linbpq and
####                 did the chmod+x and then ran linbpq.  Stop doing that.  Install should
####                 have taken care of all of that.
#### Version 44   -- 2015-02-26 Add comments to designate when the boilerplate processing takes place.
#### Version 45   -- 2015-04-22 Fix error message which mentions node.ini to also mention tarpn config
#### Version 46   -- 2015-05-27 Remove call for linbpq chat kludge for tadd node.
#### Version J001 -- 2015-10-15 fix search for node.ini file
#### Version J002 -- 2015-10-15 fix where wget was deleting the script run logfile.
#### Version J003 -- 2016-01-16 Add an error message to the screen if couldn't construct bpq32.cfg.  Also move script log to home directory from bpq directory.
#### Version J004 -  2019-01-13 Stop TARPN-HOME on entry, just to make sure.
#### Version J005 -- 2019-02-11 Don't delete the tarpn-home delete-me file if it is already deleted
###  Version S006 -- 2019-05-31 Force /home/pi/bpq/Files folder to be 777 permissions.  This gets rid of a write access error from Root during node service running the node in background
###  Version B007 -- 2019-11-10 Set linbpq to executable just before attempting to launch it.
###  Version B008 -- 2019-11-10 make killall piminicom be "quiet"
###  Version B009 -- 2020-08-30 add more data to the log file.
#### Version B010 -- 2020-09-27 Rewrite check-process to detect tarpn_home.pyc instead of python
###  Version B011 -- 2020-10-14 Delete stray /home/pi/temp_latest_ninotnc directory
###  Version B012 -- 2020-10-29 working on read/write KAUP8R
###  Version B013 -- 2020-10-29 working on read/write KAUP8R
###  Version B014 -- 2020-11-02 Fix some logging destination specifications.
###  Version B015 -- 2020-11-02 Add write to node-start-time.
###  Version B016 -- 2020-11-03 use make_local_bpq.sh instead of make_local_cfg.sh.    The new make local users the kaup8r redirection.
###  Version B017 -- 2020-11-03 Fix bug where start-time file was not accessible from tarpn-test
###  Version B018 -- 2020-11-03 Fix bug where make_local_bpq.sh was not erased before the new one was installed. resulting in old versions being run
###  Version B019 -- 2020-11-04 get rid of the lsof call
###  Version B020 -- 2020-11-30 pass "get" to get-or-set-kaup8r.  Get rid of the local getSetKaup8rFor()
###  Version B021 -- 2020-11-31 Use the "source" command correctly.
###  Version B022 -- 2021-01-26 remove a debugging line in "check process" which resulted in extra 0s showing up in STDOUT
#### Version B023 -- 2021-04-02 attempt to fix the permissions or existance of Files folder
#### Version B024 -- 2021-05-19 new tarpn-home run/don't-run process
#### Version B025 -- 2021-05-23 refine Check-Process() to use pgrep -rf instead of pgrep -r
#### Version B026 -- 2021-05-23 new temp file for get_or_set_runbpq_ninotnc_kaup8r.dat in /tmp/tarpn
#### Version B027 -- 2021-05-24 more file addresses needed changing to /tmp/tarpn
#### Version B040 -- 2021-05-28 begin rewrite for dynamically assigned ports.
#### Version B041 -- 2021-06-07 Write to TARPN START/STOP log.
#### Version B042 -- 2021-06-30 Use test_internet.sh instead of checking for TARPN server access locally.
#### Version B043 -- 2021-06-30 meticulously set the directory to /home/pi/bpq before messing with files in that directory
#### Version B044 -- 2021-06-30 more work on getting the right directory
#### Version Bullseye001 -- 2021-11-13 fix trailing null in Source-URL
#### Version Bullseye002 -- 2021-11-30 stop trying to remove /home/pi/bpq/temp*
#### Version Bullseye003 -- 2021-12-15 Improve the creation of tarpn_runbpq.log
#### Version Bullseye004 -- 2023-03-19 fix a rm -f command that was potentially trying to remove a directory instead of a wildcard of temp files.
#### Version Bullseye005 -- 2025-01-25 launch tarpnmon-runner and kill off tarpn-mon around running linbpq
#### Version Bullseye006 -- 2025-03-01 erase and create WP.cfg every time we launch linbpq.
#### Version Bullseye007 -- 2025-05-07  be sure to delete NODE_START_TIME files for creating a new one
#### Version Bullseye008 -- 2025-05-08  no longer call tarpn runner from here.
#### Version Bullseye009 -- 2025-11-23  respect STOP-SERVICE-SEMAPHORE

#### VERSION NUMBER
echo "#### =runbpq                    Bullseye009 =" #  --VERSION--#########
echo                     "###  RUNBPQ Bullseye009"      >> $RUNBPQLOG;
uptime  >> $RUNBPQLOG;


### Grab the path saved in SOURCE URL for acquiring updated materials
if [ -f /usr/local/sbin/source_url.txt ];
then
    echo -n;
else
   echo "### ERROR0: source URL file not found."
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: ### ERROR0: source URL file not found." >> $RUNBPQLOG;

   echo "### ERROR0:"
   echo "### ERROR0: Aborting"
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: : exit from script" >> $RUNBPQLOG;
   echo -e "\n\n\n\n\n\n\n" >> $RUNBPQLOG;
   tarpnsleep 90;
   exit 1
fi

_source_url=$(tr -d '\0' </usr/local/sbin/source_url.txt);
echo -ne $(date) " " >> $RUNBPQLOG
echo "runbpq.sh: Source URL=" $_source_url >> $RUNBPQLOG;

tarpnsleep 2;
echo -ne $(date) " " >> $RUNBPQLOG
echo "runbpq.sh: hostname="$HOSTNAME     >> $RUNBPQLOG;

######## Check to see if we have a node.ini configuration file -- if not, then abort the entire process
if [ -f "/home/pi/node.ini" ];
then
    echo -n;
else
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: ### ERROR: node.ini not found in /home/pi.  Please do tarpn config"  >> $RUNBPQLOG;
   echo "### ERROR: node.ini not found in /home/pi.  Please do tarpn config"
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh:  pause 90"
   tarpnsleep 90;
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: exit from script"     >> $RUNBPQLOG;
   echo -e "\n\n\n\n\n\n\n"     >> $RUNBPQLOG;
   exit 1
fi;


######## Kill off any host session in progress.
sudo killall -q piminicom

#############
#############   Update boilerplate from Internet, and then process NODE.INI key-value-pairs to generate custom TARPN config
#############

TEMP_LOG_FILE="/home/pi/temp_log_xfer_file.txt";

#### Get all of the USB/serial devices and find out their KAUP8Rs.  Update the /usr/local/etc  kauper files.




cd /home/pi/bpq
sudo rm -f testfile.txt
rm -f $TEMP_LOG_FILE
sudo -u pi wget -o $TEMP_LOG_FILE $_source_url/testfile.txt;
cat $TEMP_LOG_FILE >> $RUNBPQLOG
if [ -d Files ];
then
    sudo chmod 777 Files                      ### make the /bpq/Files directory read/write/execute so the BBS can write and read it.
else
    mkdir Files
    sudo chmod 777 Files
fi

##### IF we have access to the Internet, then testfile.txt will have been received.
echo "#####  Going to fetch a test file from the web server"  >> $RUNBPQLOG;
source test_internet.sh
getTestFile
if [ $? -lt 1 ];       ## if no errors, move on
then
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: test-file retrieved from web server." >> $RUNBPQLOG;

   ######### Take node.ini from the home directory and COPY it to bpq.

   cd /home/pi/bpq
   sudo -u pi cp /home/pi/node.ini node.ini
   sudo rm -f boilerplate.c*;
   sudo rm -f make_local_bpq.s*;

   ##### Download current copies of boilerplate.cfg and make_local_bpq.sh -- get connect results and log it.
   rm -f $TEMP_LOG_FILE
   sudo -u pi wget -o $TEMP_LOG_FILE $_source_url/boilerplate.cfg;
   cat $TEMP_LOG_FILE >> $RUNBPQLOG
   rm -f $TEMP_LOG_FILE
   sudo -u pi wget -o $TEMP_LOG_FILE $_source_url/make_local_bpq.sh;
   cat $TEMP_LOG_FILE >> $RUNBPQLOG
   rm -f $TEMP_LOG_FILE

   ###### TEST to make sure we got boilerplate.cfg and make_local_bpq.sh
   if [ -f boilerplate.cfg ];
   then
     echo -ne $(date) " " >> $RUNBPQLOG
     echo "runbpq.sh: bpq config retrieved from webserver" >> $RUNBPQLOG;

     if [ -f make_local_bpq.sh ];
     then
       echo -ne $(date) " " >> $RUNBPQLOG
       echo "runbpq.sh: make_local_bpq.sh  retrieved from webserver" >> $RUNBPQLOG;
       sudo chmod +x make_local_bpq.sh;

       ######## make backup copies of bpq32.cfg
       sudo rm -f bpq32.o2;
       if [ -f bpq32.o1 ];
       then
          mv bpq32.o1 bpq32.o2;
       fi
       if [ -f bpq32.old ];
       then
          mv bpq32.old bpq32.o1;
       fi
       if [ -f bpq32.cfg ];
       then
          cp bpq32.cfg bpq32.old
       fi

       #### Run make_local_bpq.sh to create new bpq32.cfg
       if source make_local_bpq.sh;
       then
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: make_local_bpq returned with OK status"  >> $RUNBPQLOG;
       else
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: ERROR: make_local_bpq returned with FAIL status"  >> $RUNBPQLOG;
          exit 1
       fi
       if [ -e makelocalfail.txt ];
       then
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: make_local_bpq.sh  declared a failure." >> $RUNBPQLOG;
          echo "runbpq.sh: Failure decoding the node.ini file.  Run TARPN CONFIG to adjust."
          exit 1
       fi
     else
        echo -ne $(date) " " >> $RUNBPQLOG
        echo "runbpq.sh: ERROR: make_local_bpq.sh not found in /home/pi/bpq"  >> $RUNBPQLOG;
        exit 1
     fi
   else
     echo -ne $(date) " " >> $RUNBPQLOG
     echo "runbpq.sh: ERROR: boilerplate NOT retrieved from webserver" >> $RUNBPQLOG;
     exit 1
   fi
else
   echo "### testfile not found via Internet.  Run with local files only." >> $RUNBPQLOG;
   cd /home/pi/bpq
   if [ -f boilerplate.cfg ];
   then
     echo -ne $(date) " " >> $RUNBPQLOG
     echo "runbpq.sh: boilerplate config is available" >> $RUNBPQLOG;

     if [ -f make_local_bpq.sh ];
     then
       echo -ne $(date) " " >> $RUNBPQLOG
       echo "runbpq.sh: /home/pi/bpq/make_local_bpq.sh  is available" >> $RUNBPQLOG;
       sudo chmod +x make_local_bpq.sh;

       ######## make backup copies of bpq32.cfg
       sudo rm -f bpq32.o2;
       if [ -f bpq32.o1 ];
       then
          mv bpq32.o1 bpq32.o2;
       fi
       if [ -f bpq32.old ];
       then
          mv bpq32.old bpq32.o1;
       fi
       if [ -f bpq32.cfg ];
       then
          cp bpq32.cfg bpq32.old
       fi

       #### Run make_local_bpq.sh to create new bpq32.cfg
       echo -ne $(date) " " >> $RUNBPQLOG
       echo "runbpq.sh: Launching make_local_bpq.sh"  >> $RUNBPQLOG;
       if source make_local_bpq.sh;
       then
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: make_local_bpq completed ok"  >> $RUNBPQLOG;
       else
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: ERROR: make_local_bpq returned FAIL!"  >> $RUNBPQLOG;
          echo "### ERROR: Can't run.  See script-log"
          exit 1
       fi
       if [ -e makelocalfail.txt ];
       then
          echo -ne $(date) " " >> $RUNBPQLOG
          echo "runbpq.sh: make_local_bpq.sh  declared a failure." >> $RUNBPQLOG;
          echo "runbpq.sh: Failure decoding the node.ini file.  Run TARPN CONFIG to adjust."
          exit 1
       fi
     else
       echo -ne $(date) " " >> $RUNBPQLOG
       echo "runbpq.sh: ERROR: make_local.sh not found in /home/pi/bpq"  >> $RUNBPQLOG;
       echo "### ERROR: Can't run.  See script-log"
       exit 1
     fi
   else
     echo -ne $(date) " " >> $RUNBPQLOG
     echo "runbpq.sh: ERROR: boilerplate NOT found" >> $RUNBPQLOG;
     echo "### ERROR: Can't run.  See script-log"
     exit 1
   fi
fi

#############
#############   End of Custom TARPN config generation.
#############

sudo rm -rf /home/pi/temp_latest_ninotnc
sudo rm -f /home/pi/bpq/node.ini;
sudo rm -f /home/pi/temporary_home_web_app
sudo rm -f /home/pi/temp_latest_ninotnc
sudo rm -f /home/pi/temp-node-start-time.txt
sudo rm -f /home/pi/temp_for_tarpn_start.txt
sudo rm -f /home/pi/bpq/tt*.tmp
sudo rm -f /home/pi/bpq/testfile.txt
sudo chmod 666 bpq32.cfg;
pwd >> $RUNBPQLOG;
ls -lrat >> $RUNBPQLOG;
sleep 1;


sudo rm -f WP.cfg
echo > WP.cfg



if [ -f bpq32.cfg ];
then
   ### Make a record of when we started the node
   NODE_START_TIME="/usr/local/etc/node_start_time.txt"
   if [ $(whoami) == "pi" ];
   then
      echo -ne $(date) " " >> $RUNBPQLOG
      echo "runbpq.sh:  Run from user ### PI ###"      >> $RUNBPQLOG;
      rm -f temp-node-start-time.txt
      echo -ne $(date) " TARPN TEST " > /home/pi/temp-node-start-time.txt
      sudo rm -f $NODE_START_TIME
      sudo mv /home/pi/temp-node-start-time.txt $NODE_START_TIME
      sudo chmod 666 $NODE_START_TIME
   else
      sudo rm -f $NODE_START_TIME
      echo -ne $(date) " " > $NODE_START_TIME
   fi

   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: launching bpq"      >> $RUNBPQLOG;

   chmod +x linbpq
   sudo setcap "CAP_NET_RAW=ep CAP_NET_BIND_SERVICE=ep" linbpq
   echo "### RUNBPQ.SH: "
   echo "### RUNBPQ.SH: Launching G8BPQ node software.  Note, this script does not end"
   echo "### RUNBPQ.SH: until the node is STOPPED/control-C etc.. "
   echo "### RUNBPQ.SH: "


   ###### run G8BPQ node -- this does not return until it is killed or quits
   ###### Run as user pi, even if we are called by the OS in the background
   sudo -u pi ./linbpq
   sudo rm -f $NODE_START_TIME
   echo "### RUNBPQ.SH: G8BPQ LINBPQ has stopped running.  Back to runbpq.sh"
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "### RUNBPQ.SH: G8BPQ LINBPQ has stopped running"      >> $RUNBPQLOG;
else
   echo "### RUNBPQ.SH: ERROR: Can't run.  See script-log"
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh: ERROR: Incomplete configuration.  Is this the first run?"    >> $RUNBPQLOG;
   echo -ne $(date) " " >> $RUNBPQLOG
   echo "runbpq.sh:        BPQ32.CFG does not exist.  It should by this time."   >> $RUNBPQLOG;
fi

### TARPN HOME shouldn't be running right now.  Stop it right now.
if [ -d /tmp/tarpn ]; then                                                     #v2.10 and later method
   if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
       echo -ne $(date) "" >> $HOME_LOGFILE
       echo "runbpq.sh after linbpq quits or didn't start: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
       sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
   fi
fi
tarpnsleep 2

echo -ne $(date) " " >> $RUNBPQLOG
echo  "runbpq.sh: exit from script"     >> $RUNBPQLOG;
echo -e "\n\n\n\n"     >> $RUNBPQLOG;
echo -ne $(date) "" >> $START_STOP_LOGFILE
echo " ### RUNBPQ exit-from-script"  >> $START_STOP_LOGFILE

