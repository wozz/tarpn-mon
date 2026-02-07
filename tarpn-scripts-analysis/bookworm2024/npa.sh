#!/bin/bash

######## NEIGHBOR-PORT-ASSOCIATION script NPA.SH -- See VERSION # below.
## This script is called from neighbor_port_association.service, which is a service control file.
## neighbor_port_association.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/tarpn/sbin and is redeployed by "tarpn update".
##
## This script logs to /var/log/tarpn_neighbor_port_association.log
##
## This script checks /usr/tarpn/etc/background.ini for a token.
## The token can either be BACKGROUND:OFF  or  BACKGROUND:ON
## If off, wait a while, then repeat the test.
## If on, then check of linbpq is actually running, and if so, check my own status file to see if I think I'm done.
## If not done, then process the node.ini file and a set of up to 12 port-association files in the /tmp/taprn directory
## to determine of any of the ports and neighbors are not associated.
## if the node is not running, then clear out my status file and the port association files.

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

###   waste_time_if_not_running() {
###   if grep -q "BACKGROUND:OFF" /usr/tarpn/etc/background.ini;
###   then
###      #echo "  " >> $NPA_LOGFILE
###      #echo "waste-time-if-not-running()" >> $NPA_LOGFILE
###
###      check_process "tarpn_home.pyc"
###      if [ $? -ge 1 ];
###      then
###         echo -ne $(date) " " >> $NPA_LOGFILE
###         echo "tarpn-home.pyc is running" >> $NPA_LOGFILE
###         echo "Removing remove-me-to-stop file" >> $NPA_LOGFILE
###         sudo rm -rf /usr/tarpn/sbin/home_web_app/remove_me_to_stop_server.txt    #added tarpn-home-go
###         if [ -d /tmp/tarpn ];
###         then
###            if [ -e /tmp/tarpn/tarpn_home_go.flag ];
###            then
###              sudo rm -rf /tmp/tarpn/tarpn_home_go.flag
###              echo -ne $(date) " " >> $NPA_LOGFILE
###              echo "go-flag exists.  deleting it" >> $NPA_LOGFILE
###              echo "go-flag exists.  deleting it"
###            fi
###         fi
###         #else
###            #echo "stage1: some other pyton service?" >> $NPA_LOGFILE
###      fi
###      sleep 5
###   fi
###   }
###


NPA_NAME="NPA Neighbor Port Association Background"
NPA_LOGFILE="/var/log/tarpn_neighbor_port_association.log"
RX_TARPNSTAT_LOGFILE="/var/log/tarpn_rxtarpnstat_service.log"
NPA_APP="/usr/tarpn/sbin/neighbor_port_association.app"
NODE_INIT="/home/pi/node.ini"
OURDIR="/tmp/tarpn/tnpa"
STATUSDATA="$OURDIR/neighbor_port_association_status.dat"
PORTSTATUS="$OURDIR/npa_port_"
NEIGHBORSTATUS="$OURDIR/npa_neighbor_"
######################################################################################## VERSION INFO ####################################################################################################
#### 05-30-2021 b001   I'm working on discovering the neighbors using the M command from the node
#### 05-30-2021 b002   be more meticulous about creating the TNPA files directory
#### 06-04-2021 b003   Add KILLALL RX-TARPNSTATAPP when a new route is discovered
#### 06-04-2021 b004   Sleep for shorter duration (10 seconds) after first 10 runs.  Then sleep for 3 minutes for later runs
#### 06-07-2021 b005   Fix bug in shorter duration sleep.  -- this version appears to have a segfault?
#### 06-07-2021 b006   improve log file output.
#### 06-10-2021 b007   attempt to clean up around npa_wants_rx_tarpnstat_restarted.flg
#### 06-11-2021 b008   changed name of this file to npa.sh from neighbor_port_association.sh
#### 06-11-2021 b009   work on log output
#### 06-11-2021 b010   If LINBPQ is not running, or if our directory TNPA is missing when npa app returns, exit this script
#### 10-22-2021 b011   Fix NPA version string so it shows in tarpn sysinfo
#### 12-03-2021 bullseye012   Get rid of some noisy prints to stdout
####  5-09-2025 Bookworm013   Change the name of the rx tarpnstat servce logfile to tarpn_rxtarpnstat_service.log

echo -ne $(date) " " >> $TARPN_COMMAND_LOGFILE
echo -ne "#### =NPA.SH                    Bookworm013=" >> $NPA_LOGFILE;  #  --VERSION--#########
echo "  start:" >> $NPA_LOGFILE;
uptime >> $NPA_LOGFILE

sudo chmod 666 $NPA_LOGFILE

###### Make sure we have a node.ini config file.  If not, wait 18 minutes and then exit
if [ -f $NODE_INIT ];
then
   echo -n;
else
   sleep 180
   if [ -f $NODE_INIT ];
   then
      echo -n;
   else
      sleep 180
      if [ -f $NODE_INIT ];
      then
         echo -n;
      else
         sleep 180
         if [ -f $NODE_INIT ];
         then
            echo -n;
         else
            sleep 180
            if [ -f $NODE_INIT ];
            then
               echo -n;
            else
               sleep 180
               if [ -f $NODE_INIT ];
               then
                  echo -n;
               else
                  sleep 180
               fi
            fi
         fi
      fi
   fi
fi


if [ -f $NODE_INIT ];
then
   echo -n;
else
   echo "ERROR: NODE INIT file not found." >> $NPA_LOGFILE
   date >> $NPA_LOGFILE
   echo "$NPA_NAME exit"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "exit"  >> $NPA_LOGFILE
   exit 1
fi


if [ -d /tmp/tarpn ];
then
   echo "/tmp/tarpn exists" >> $NPA_LOGFILE
   echo "/tmp/tarpn exists"
else
   echo "/tmp/tarpn does not exist -- sleep for 10 seconds and then quit" >> $NPA_LOGFILE
   echo "/tmp/tarpn does not exist -- sleep for 10 seconds and then quit"
   sleep 10;
   echo "$NPA_NAME exit"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "exit"  >> $NPA_LOGFILE
   exit 0;
fi

#### Check if our directory exists.  delete it.  We'll recreated it once linbpq starts
if [ -d $OURDIR ];
then
   echo "$OURDIR existed on start.  Delete it." >> $NPA_LOGFILE
   sudo rm -rf $OURDIR
fi



if [ -d $OURDIR ];
then
   echo "Error deleting existing $OURDIR - sleep for 180 seconds and then quit"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "Error deleting existing $OURDIR - sleep for 180 seconds and then quit" >> $NPA_LOGFILE
   sleep 180
   echo "$NPA_NAME exit"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "exit"  >> $NPA_LOGFILE
   exit 1;
fi

check_process "linbpq"
if [ $? -lt 1 ];                ## LINBPQ is not running yet.  Sleep for a bit in case it comes back soon
then
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "LINBPQ not running at start.  Sleep for a bit and check again in case it starts"  >> $NPA_LOGFILE
   sleep 10
   check_process "linbpq"
   if [ $? -lt 1 ];                ## LINBPQ is not running yet.  Sleep for a bit in case it comes back soon
   then
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "LINBPQ not running at start.  Sleep for a bit and check again in case it starts"  >> $NPA_LOGFILE
      sleep 10
      check_process "linbpq"
      if [ $? -lt 1 ];                ## LINBPQ is not running yet.  Sleep for a bit in case it comes back soon
      then
         echo -ne $(date) " " >> $NPA_LOGFILE
         echo "LINBPQ not running at start.  Sleep for a bit and check again in case it starts"  >> $NPA_LOGFILE
         sleep 10
         check_process "linbpq"
         if [ $? -lt 1 ];                ## LINBPQ is not running yet.  Sleep for a bit in case it comes back soon
         then
            echo -ne $(date) " " >> $NPA_LOGFILE
            echo "LINBPQ not running at start.  Sleep for a bit and check again in case it starts"  >> $NPA_LOGFILE
            sleep 10
            check_process "linbpq"
            if [ $? -lt 1 ];                ## LINBPQ is not running yet.  Sleep for a bit in case it comes back soon
            then
               echo -ne $(date) " " >> $NPA_LOGFILE
               echo "LINBPQ not running at start.  Sleep for a bit and check again in case it starts"  >> $NPA_LOGFILE
               echo "$NPA_NAME exit for lack of LINBPQ"
               echo -ne $(date) " " >> $NPA_LOGFILE
               echo " exit for lack of LINBPQ"  >> $NPA_LOGFILE
               exit 1;
            fi
         fi
      fi
   fi
fi
echo -ne $(date) " " >> $NPA_LOGFILE
echo "linbpq is running -- set up directories for $NPA_NAME"  >> $NPA_LOGFILE
echo "$NPA_NAME Starting -- attempting to create $OURDIR"
cd /tmp/tarpn

sudo mkdir tnpa
sudo chmod 777 tnpa
sudo chown pi tnpa
cd ~


if [ -e $OURDIR ];
then
   echo "Created $OURDIR" >> $NPA_LOGFILE
else
   echo "$NPA_NAME ERROR - could not create $OURDIR"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "could not create $OURDIR"  >> $NPA_LOGFILE
   echo ""  >> $NPA_LOGFILE
   echo ""  >> $NPA_LOGFILE
   ls -l /tmp >> $NPA_LOGFILE
   echo ""  >> $NPA_LOGFILE
   echo ""  >> $NPA_LOGFILE
   ls -l /tmp/tarpn >> $NPA_LOGFILE
   echo ""  >> $NPA_LOGFILE
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "Sleep and quit the script file"  >> $NPA_LOGFILE
   sleep 10
   exit 1;
fi

sudo chmod 777 $OURDIR


__loop_counter=0;

################# LOOP HERE FOREVER
#### Top of loop -- check if we should be calling linbpq or just waiting for a while.
while [ 1 ];
do
   check_process "linbpq"
   if [ $? -lt 1 ];
   then
      echo "$NPA_NAME -- LINBPQ is not running.  Exit"
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "$NPA_NAME -- LINBPQ is not running.  Exit"  >> $NPA_LOGFILE
      exit 0;
   fi

   if [ -x $NPA_APP ];
   then
      echo -n;
   else
      echo "$NPA_NAME -- $NPA_APP doesn't seem to be executable. wait 180 and then  Exit"
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "$NPA_APP doesn't seem to be executable. wait 180 and then  Exit"  >> $NPA_LOGFILE
      sleep 180
      echo "$NPA_NAME -- Exit for lack of $NPA_APP"
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "Exit for lack of $NPA_APP"  >> $NPA_LOGFILE
      exit 1;
   fi

   ### remove the flag NPA creates to tell us that a new route is discovered, and that rx-tarpnstat needs to pay attention to it.
   __loop_counter=$(($__loop_counter+1))
   #echo "$NPA_NAME:  call $NPA_APP"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "call $NPA_APP  counter=$__loop_counter"    >> $NPA_LOGFILE
   $NPA_APP
   #echo "$NPA_NAME:  back from $NPA_APP"
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "back from $NPA_APP"    >> $NPA_LOGFILE

   if [ -e $OURDIR ];
   then
      echo -n;
   else
      echo "$NPA_NAME $OURDIR missing after app return -- exit background"
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "$OURDIR missing after app return -- exit background"  >> $NPA_LOGFILE
      exit 1
   fi

   check_process "linbpq"
   if [ $? -lt 1 ];                ## LINBPQ is not running.  It must have quit.  Exit our script
   then
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "LINBPQ not running when we got back from $NPA_APP - restart npa process from the top."  >> $NPA_LOGFILE
      echo "$NPA_NAME: Need to restart NPA process from the top because LINBPQ is not running."
      exit 1
   fi

   if [ -f /tmp/tarpn/tnpa/npa_wants_rx_tarpnstat_restarted.flg ];
   then
      echo "$NPA_NAME: New route discovered - Need to restart rx-tarpnstat"
      echo -ne $(date) " " >> $RX_TARPNSTAT_LOGFILE
      echo "$NPA_NAME: New route discovered - Doing KILLALL RX-TARPNSTATAPP" >> $RX_TARPNSTAT_LOGFILE
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "New route discovered so need to restart rx-tarpnstat app KILLALL RX_TARPNSTATAPP"    >> $NPA_LOGFILE
      sudo killall rx_tarpnstatapp
      sudo rm -f /tmp/tarpn/tnpa/npa_wants_rx_tarpnstat_restarted.flg
   fi

   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "Sleep for a few minutes before re-running the script  "    >> $NPA_LOGFILE
   __testcount=10;
   if [ $__loop_counter -lt $__testcount ];
   then
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "First 10 runs, sleep 10 seconds after each run.  counter=$__loop_counter" >> $NPA_LOGFILE
      sleep 10
   else
      echo -ne $(date) " " >> $NPA_LOGFILE
      echo "After first 10, sleep 180 seconds after each run.  counter=$__loop_counter" >> $NPA_LOGFILE
      sleep 180
   fi
   echo -ne $(date) " " >> $NPA_LOGFILE
   echo "awake" >> $NPA_LOGFILE
done

exit 0


