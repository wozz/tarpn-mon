#!/bin/bash
##### make_local_bpq.sh
##### SCRIPT to use local configuration and import boilerplate global config to generate bpq32.cfg
##### See tarpn.net and http://www.cantab.net/users/john.wiseman/Documents
##### Created by Tadd Torborg KA2DEW  Feb 15, 2014
#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC



###### Sleep If Background Enabled -- This function is called after failure when we're going to reboot.
sleepIfBackgroundEnabled() {
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
      echo "make_local_bpq.sh: background is on -- sleeping pending reboot"    >> $TARPNCOMMANDLOGFILE
      echo "make_local_bpq.sh: background is on -- sleeping pending reboot"
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      sleep 30
   fi
}


exitForFailure() {
echo "make_local_bpq.sh:  Bad exit from node.ini analysis"
if [ $(whoami) == "root" ];
then
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh:  Root exec: Bad exit from node.ini analysis"  >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh:  Root exec: Sleeping for 1800 seconds before exit or reboot"
   echo "make_local_bpq.sh:  Root exec: Sleeping for 1800 seconds before exit or reboot"  >> $TARPNCOMMANDLOGFILE
   sleepIfBackgroundEnabled
   sleepIfBackgroundEnabled
   sleepIfBackgroundEnabled
   sleepIfBackgroundEnabled
   sleepIfBackgroundEnabled
   echo "make_local_bpq.sh:  Awake. -- now EXIT."
   if grep --text -q "BACKGROUND:ON" /usr/tarpn/etc/background.ini; then
      echo "make_local_bpq.sh: Root exec: failure during background node start"
      echo "make_local_bpq.sh: trigger a Raspberry PI Reboot"
      echo "make_local_bpq.sh: trigger a Raspberry PI Reboot"
      echo "make_local_bpq.sh: trigger a Raspberry PI Reboot"
      echo "make_local_bpq.sh:  Node background start failure.  Going to REBOOT"  >> $TARPNCOMMANDLOGFILE
      echo -ne $(date) "" >> $START_STOP_LOGFILE
      echo " ### MAKE-LOCAL-BPQ.SH  EXIT FOR FAILURE!  DOING OS REBOOT!"  >> $START_STOP_LOGFILE
      sleep 1
      sudo touch /forcefsck
      sleep 1
      uptime
      sudo shutdown -r now;
   fi
   echo "make_local_bpq.sh:  Awake.  Background exec now disabled?"  >> $TARPNCOMMANDLOGFILE
fi
exit 1;
}



#### VERIFY NEIGHBOR TOKEN
#### Make sure the syntax is correct in the node.ini file for the specified "key:" value.
#### $1 will have the neighbor letter, i.e. "A".
#### the key token is "neighborA" if $1 is "A".
#### the "value" associated with the key will be "NOT_SET", "not_set" or will have a dash number, i.e.  K1QRM-2
#### if neighborA: has a callsign with an SSID, then the frackA: figure must also have a number.
verifyNeighborToken() {
#echo "verify neighbor token for $1"
if grep --text -q -e "neighbor$1:" $templocalfile;
then
   #echo "got neighbor$1: in node.ini"
   grep --text neighbor$1: $templocalfile > $tempgrepfile
   if grep --text -q "neighbor$1:NOT_SET" $tempgrepfile;
   then
      echo -n; # echo "make_local: neighbor$1 is disabled"
   else
      #echo "did not find neighbor$1:NOT_SET in node.ini -- check for lower case not-set"
      if grep --text -q "neighbor$1:not_set" $tempgrepfile;
      then
         echo "make_local: neighbor$1 is disabled"
      else
         #echo "did not found neighbor$1:not_set in node.ini -- check of there is a - for an ssid"
         if grep --text -q "-" $tempgrepfile;
         then
            echo -n; #echo -n; #echo -n "make_local: neighbor$1 spec is "
            echo -n; #grep neighbor$1 $templocalfile;
            if grep --text -q -e frack$1: $templocalfile;
            then
               #echo "we found a - for ssid in neighbor$1: in node.ini -- check for frack$1:0"
               if grep --text -q "frack$1:0" $filetoread;
               then
                  echo "make_local: ERROR  frack$1 is 0 when neighbor$1 is defined!"
                  echo "make_local: ERROR  frack$1 is 0 when neighbor$1 is defined!"  >> $TARPNCOMMANDLOGFILE
                  echo "make_local: ERROR  frack$1 is 0 when neighbor$1 is defined!"  > /home/pi/bpq/makelocalfail.txt
                  exitForFailure
               else
                  echo -n; #echo -n "make_local: frack$1 spec is "
                  echo -n; #grep frack$1 $templocalfile;
               fi
            else
               echo "ERROR: node.ini has no, or malformed, frack$1 Frame Acknowledge spec!"
               echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
               echo "make_local_bpq.sh: frack$1 Frame Acknoledge spec missing in node.ini file." >> $TARPNCOMMANDLOGFILE
               echo "frack$1 Frame Acknoledge spec missing in node.ini file" > /home/pi/bpq/makelocalfail.txt
               exitForFailure
            fi
         else
            echo "make_local: ERROR: neighbor$1     callsign spec syntax error.  Needs SSID?"
            echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
            echo "make_local_bpq.sh: neighbor$1 callsign spec syntax error in node.ini file." >> $TARPNCOMMANDLOGFILE
            echo "neighbor$1 callsign spec syntax error in node.ini file" > /home/pi/bpq/makelocalfail.txt
            exitForFailure
         fi
      fi
   fi
else
   echo "ERROR: node.ini has no, or malformed, neighbor$1 callsign spec!"
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: neighbor$1 callsign spec missing in node.ini file." >> $TARPNCOMMANDLOGFILE
   echo "neighbor$1 callsign spec missing in node.ini file" > /home/pi/bpq/makelocalfail.txt
   exitForFailure
fi
}

### Enable ports In Config File    -- $1 is the PORTS name like q~ninotnc_port02~q    $2 is the ports number, like 02   $3 is either "USB" or "ACM"
enablePortsInConfigFile() {
if [ $__numberOfPorts -gt "0" ];
then
   #echo " "
   #echo "enablePortsInConfigFile $1 $2"
   #echo "Find an existing /dev/ttyACM#"
   #echo "/dev/ttyACM Number Counter = " $__deviceNumberCounter
   __booleanGotOnePortDefined=0;
   while (( $__booleanGotOnePortDefined == 0 ));
   do
      #echo "----top of while"
      if [ -e /dev/tty$3$__deviceNumberCounter ];
      then
         #echo -n "ttyACM of $__deviceNumberCounter was found   ";
         #ls -l /dev/ttyACM$__deviceNumberCounter
         __booleanGotOnePortDefined=1;
         sed -i "s=$1==" $temp_outwork1file              ## uncomment the entire section for this port
         sed -i "s=q~portdev$2~q=tty$3$__deviceNumberCounter=" $temp_outwork1file
         __deviceNumberCounter=$(($__deviceNumberCounter+1))
         #echo "/dev/ttyACM Number Counter incremented to " $__deviceNumberCounter
         __numberOfPorts=$((__numberOfPorts-1))
      else
         #echo "ttyACM of $__deviceNumberCounter NOT found "
         __deviceNumberCounter=$(($__deviceNumberCounter+1))
         #echo "/dev/ttyACM Number Counter incremented to " $__deviceNumberCounter
      fi
      #echo "     bottom of while"
   done
else
    #echo "no more ports.  Disable $1"
    #disable this PORTS name
    sed -i "s=$1=;disabled;=" $temp_outwork1file              ## disable and comment out this entire section, since we aren't using it.
fi
}


#### version 38 -- changed number of tokens from 53 to 60 to allow for multiple infomessage lines.
#### version 39 -- started working on making single quotes a non-problem.
#### version 40 -- got rid of extra blank lines in INFO text.
#### version 41 -- Add support for tokens related to mobile node and mobile ports
#### version 42 -- remove mobile node features
#### version 43 -- fix bug with processing of TNC-PI 5
#### version 44 -- CROWD is applied to ka2dew-2 instead of to tadd
#### version 45 -- CROWD is applied to ab4oz-2 as well
#### version 46 -- Fix bug where more than one single quote in a line would cause failure.
#### version 47 -- CROWD is applied to W4DNA, KA2DEW and W4VU.  Remove AB4OZ
#### version 48 -- CROWD is applied to kc3ibn-1
#### version 49 -- Allow open and close parenthsis in the info text etc..
#### version 50 -- add support for BBS
#### version 51 -- add support for BBS # of tokens
#### version 52 -- Set BBS=1 or BBS=0 as appropriate
#### version 53a -- CROWD node moved from ka2dew-1 to ka2dew-5
#### version 53b -- if linmail.cfg exists, take action to set the # of streams to 10 and the application number to 3.
#### version 54 -- fix some more default values for the linmail.cfg file.
#### version 55 -- fix some more default values for the linmail.cfg file.
#### version 56 -- CROWD node is on kc3ibn-7.
#### version 57 -- Minor fixes to BBS prompts
#### version 58c -- fix bug where NewUserPrompt was renamed by accident.
#### version 59 -- CROWD node is on wb2lhp-7
#### version 60 -- CROWD node is on nc4fg-12
#### version 61 -- fix error where diagnostic prints were using wrong port numbers for ports 7 through 12.
#### version 62 -- add support for crowd switch in node.ini
#### version 63b -- debugging crowd switch
#### version 64 -- now require that the chat callsign be set.  Change name from crowd to chat.
#### version 65 -- create a copy of the bpq32.cfg file, sans passwords, and put it in the Files folder
#### version 66 -- July 26 2018 -- make an attempt to fix the ChatCall spec in case it was "crowdcall"
#### version 68 -- July 27 2018 -- create a custom zdew02 type node name for everybody
#### version 69 -- October 14, 2018 --   get rid of the debug file foo.foo.  Just commented out.
#### version 70 -- November 22, 2018 --  Change Welcome message and ExpertWelcomeMsg to have "unread=%X   " in support of the bbsstatus check
#### version 71 -- November 23, 2018 -- welcome messages are unread=%x
#### version 72 -- January 10, 2019 -- fix unread notification in Expert sign-in with TARPN-HOME specific text.
#### version 75 -- January 10, 2019 -- debugging linmail.cfg sed edits.
#### version 77 -- January 11, 2019 -- use "new-msgs" for bbs checker in the welcome message,
#### version 78 -- January 25, 2019 -- change the Expert welcome to use unread>>>> instead of unread--->
#### version 79 -- October 13, 2019 -- change the rights for /bpq/Files
#### version 80 -- April 19, 2020 -- modify node.ini to support 4 TNC-PI and 6 NinoTNC
#### version 81 -- April 19, 2020 -- Change # of tokens to 65 from 63
#### version 82 -- April 19, 2020 -- fix early detect of tncpi-port05 enable to ninotnc_port05
#### version 83 -- April 19, 2020 -- fix late detect of tncpi-port05 enable to ninotnc_port05
#### version 84 -- April 20, 2020 -- put the names of port05 and port06 back to tncpi-port05 and tncpi-port06 to fix TARPN-HOME dependency
#### version 85 -- April 20, 2020 -- error in one tncpi-port06 equation.
#### version 86 -- May 24, 2020 -- now 67 tokens in node.ini
#### version 87 -- May 24, 2020 -- make ports 5 and 6 ninotnc ports.
#### version 87 -- May 24, 2020 -- more work on ninotnc ports 5 and 6.
#### version 88 -- May 25, 2020 -- more work on ninotnc ports 5 and 6.
#### version 89 -- May 25, 2020 -- allow a node.ini length of 65 or 67 bytes. .
#### version 90 -- May 25, 2020 -- allow a node.ini length of 65 or 67 bytes. .
#### version 91 -- May 25, 2020 -- allow a node.ini length of 65 or 67 bytes. .
#### version 92 -- May 25, 2020 -- more debugging..
#### version 93 -- May 27, 2020 -- Fix error where "KeepForTARPNHOME" wasn't a valid value for the tncpi-port05 or 06 key.
#### version 94 -- Oct 26, 2020 -- Fix error where "KeepForTARPNHOME" was getting in the way of BPQ.
#### version 95 -- Oct 31, 2020 -- Improve log files.  Start working on using KAUP8R instead of device in the portdev field.
#### version 96 -- Nov 03, 2020 -- Change the name of this script from make_local_bpq.sh to make_local_bpq.sh.
#### version 97 -- Nov 03, 2020 -- Get rid of a few spurious prints to STDOUT
#### version 98 -- Nov 03, 2020 -- Clean up more prints to STDOUT
#### version 99 -- Nov 03, 2020 -- Add a trap for extra : in a line
#### version 100 - Nov 03, 2020 -- add a function for handling bad-exits, sleep for 1800 if root.
#### version 101 - Nov 04, 2020 -- now make the sleep for 1800 work.
#### version 102 - Feb 06, 2021 -- add a 6 lines of error messages for missing KAUP8R file
#### version 103 - Mar 03, 2021 -- temporarily stop using assignTtyDeviceInBpqCfg
#### version 104 - May 18, 2021 -- If we get a bad-exit while in background service, after 1800 second sleep, do a reboot
#### version 105 - May 18, 2021 -- Improve error messages for background exec - failure mode
#### version 106 - May 19, 2021 -- new TARPN HOME run/don't-run semaphore
#### version 107 - May 23, 2021 -- move Kauper and Usb files from /usr/tarpn/etc/ to /tmp/tarpn

### version 130 - May 29, 2021 -- get rid of KAUP8R altogether.  Rewrite node.ini file.  Now not specifying TNC with port#, only callsign and FRACK.  Get rid of TNC-PI.
### version 131 - Jun 03, 2021 -- make a copy of the node.ini for TARPN-HOME consumption.
### version 132 - Jun 07, 2021 -- Log to TARPN START/STOP
### version 133 - Jun 07, 2021 -- Expected # of Tokens was wrong #.  should be 61.   forgot chat neighbor callsigns.
### version 134 - Jun 09, 2021 -- remove some debugging print noise from the startup
### version 135 - Jun 10, 2021 -- more debugging print noise reductions
### version 136 - Jun 20, 2021 -- improve stdout prints around # of ACM ports.
### version 137 - Jun 30, 2021 -- use fully qualified path for node.ini when checking count of A3 and A4 NinoTNCs
### version 138 - Jun 30, 2021 -- all scripted accesses to node.ini, except echos and comments, use $filetoread
### version 139 - Oct 22, 2021 -- If ttyACM is used in port11 or port12, throw an error
### version bullseye001 - Nov 13, 2021 -- use --text in grep commands
### version bullseye002 - Nov 20, 2021 -- use --text in ALL grep commands
### version bullseye003 - Nov 30, 2021 -- move taddquotetest to /tmp folder
### version bullseye004 - Jan 03, 2022 -- add a sudo to chmod of Files folder
### version bullseye005 - Jan 03, 2022 -- turn ampersands into + characters
### version bullseye006 - Sept 13, 2022 -- When doing a reboot-PI-for-error, write to start-stop logfile.
### version bullseye007 - Aug 19, 2023 -- start adding KISSPARAM enable/disable for ports 11 and 12.
### version bookworm010 - Jan 29, 2024 -- only 50 Tokens instead of 63 in node.ini.  This because I removed all the neighbor chat callsigns.
### version bookworm011 - Jan 31, 2024 -- work on making this work with ttyUSB as well as ttyACM

echo
echo "--------------------------------"
echo "#### =MAKE_LOCAL_BPQ.SH         Bookworm011" #  --VERSION--#########
echo "--------------------------------"

TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
START_STOP_LOGFILE="/var/log/tarpn_startstop.log"

sudo rm -f /home/pi/bpq/makelocalfail.txt
sleep 1

bpqdirectory="/home/pi/bpq"
mailConfigFile="/home/pi/bpq/linmail.cfg"
filesFolderForBbs="/home/pi/bpq/Files"
bpqConfigForFilesFolder="bpq32.txt"
bpqConfigImageInFilesFolder=$filesFolderForBbs/$bpqConfigForFilesFolder



########### Now get ready to read and process the node.ini file and boilerplate.cfg into bpq32.cfg
filetoread="/home/pi/node.ini"
boilerplatefile="/home/pi/bpq/boilerplate.cfg"
outputfile="bpq32.cfg"
tempgrepfile="/tmp/tarpn/temp/grepinprogress.txt"
templocalfile="/tmp/tarpn/temp/temp___local_node_ini"
portcallrelatefileprefix="/tmp/tarpn/portcallrelate"
sudo rm -rf $portcallrelatefileprefix*
sudo rm -rf $tempgrepfile
sudo rm -rf $templocalfile

##### If the BBS has created a config file, then set the Streams and BBS-Appl-Num correctly.
if [ -f $mailConfigFile ];
then
   sudo sed -i 's/ExpertPrompt = ".*"/ExpertPrompt = "$x unread--->"/g' $mailConfigFile
   sudo sed -i 's/ExpertWelcomeMsg = ".*";/ExpertWelcomeMsg = "$x unread>>>>  new-msgs=$x   Hello Boss\\r\\n";/g' $mailConfigFile
   if grep --text -q "Streams = 0;" $mailConfigFile;
   then
      sudo sed -i 's/Streams = 0;/Streams = 10;/g' $mailConfigFile
      sudo sed -i 's/BBSApplNum = 0;/BBSApplNum = 3;/g' $mailConfigFile
      sudo sed -i 's/WelcomeMsg = .*$Z/WelcomeMsg = "unread=$x     Greetings/g' $mailConfigFile
      sudo sed -i 's/NewUserWelcomeMsg = .*$Z/NewUserWelcomeMsg = "$x unread messages for $U, Latest $L, Last listed is $Z/g' $mailConfigFile
      sudo sed -i 's/ Prompt = "de .*>\\r\\n";/ Prompt = "$x unread  $N msgs >\\r\\n";/g' $mailConfigFile
      sudo sed -i 's/NewUserPrompt = "de .*>\\r\\n";/NewUserPrompt = "$x unread  $N msgs >\\r\\n";/g' $mailConfigFile
      sudo sed -i 's/DontHoldNewUsers = 0;/DontHoldNewUsers = 1;/g' $mailConfigFile
      sudo sed -i 's/DontNeedHomeBBS = 0;/DontNeedHomeBBS = 1;/g' $mailConfigFile
   fi
   sudo sed -i 's/SMTPGatewayEnabled = .*;/SMTPGatewayEnabled = 0;/g' $mailConfigFile

fi

sudo rm -f /home/pi/bpq/tadd-debug-file5.txt
sudo rm -f /home/pi/bpq/tadd-debug-file5b.txt
sudo rm -f /home/pi/bpq/tadd-debug-file5c.txt


#### Check that the filetoread has at least the proper number of lines.
sudo rm -f $templocalfile;
cat $filetoread | grep --text ":" | wc -l  > $templocalfile;
_count=$( cat $templocalfile );

## if there is no configmode: figure in the node.ini file, create it in the templocalfile
_value=51
if [ $_value -ne $_count ];
then
    echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
    echo "make_local_bpq.sh: unable to match the required length of node.ini file." >> $TARPNCOMMANDLOGFILE
    echo "node.ini failure" > /home/pi/bpq/makelocalfail.txt

    echo "ERROR: Make_Local:"
    echo "       node.ini is wrong length.  Run tarpn update and tarpn config"
    echo "       to update your configuration."
    echo "# of tokens found in node.ini = "$_count;
    echo "Expected # of tokens = " $_value
    exitForFailure
fi


#### Verify that the LOCAL config file and the Boilerplate are present.
#### Verify that the LOCAL config file and the Boilerplate are present.
cd /home/pi
if find "/home/pi/node.ini" >> /dev/null;
then
   echo -n
else
   echo "ERROR: node.ini not found";
   echo " It should be in the /home/pi directory.";
   echo "Please use cat > node.ini to create this file as per the documentation.";
   sleep 1
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: node.ini missing." >> $TARPNCOMMANDLOGFILE
   echo "node.ini missing" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
fi


if find "$boilerplatefile">> /dev/null;
then
   echo -n;
else
   echo "ERROR: boilerplate not found";
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: boilerplate missing." >> $TARPNCOMMANDLOGFILE
   echo "boilerplate missing" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
fi

temp_outwork1file="/tmp/tarpn/temp/tt_out1file.tmp"
sudo rm -f $temp_outwork1file
#temp_out2file="tt_out2file.tmp";
templocalfile="/tmp/tarpn/temp/tt_local.tmp";
sudo rm -f $templocalfile
#temptemplocalfile="tt_localtemp.tmp"


### Find out if : is included in any line after the key's :

__one=2
_wcoutput=20

filename='/home/pi/node.ini'
n=1

while read line; do
# reading each line
#echo
#echo

res="${line//[^:]}";
#echo -ne "dollar res = ";
#echo "$res";

_wcoutput=$(echo $res | wc -c)
#echo -ne "res="
#echo "${#res}"
#echo -ne "_wcoutput = "
#echo $_wcoutput
if [ $_wcoutput -gt $__one ];
then
   echo "#######"
   echo "####### node.ini Line No. $n = $line"
   echo "####### node.ini Line No. $n = $line"  >> $TARPNCOMMANDLOGFILE
   echo "#######"
   echo "####### node.ini line" $n "had extra :"
   echo "####### node.ini line" $n "had extra :" >> $TARPNCOMMANDLOGFILE
   echo "####### line" $n "had extra :"  > /home/pi/bpq/makelocalfail.txt
   echo "#######"
   echo "node.ini missing" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
fi
n=$((n+1))
done < $filename




##### Make sure there are no token-like figures in the local config file
if grep --text -q "~q" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the ~q figure from the local.cfg file"
        grep --text "~q" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi
if grep --text -q "q~" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the q~ figure from the local.cfg file"
        grep --text "q~" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved q~ characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi
if grep --text -q "~SP~" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the ~SP~ figure from the local.cfg file"
        grep --text "~SP~" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved ~SP~ characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi
if grep --text -q "~SINGLEQUOTE~" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the ~SINGLEQUOTE~ figure from the local.cfg file"
        grep --text "~SINGLEQUOTE~" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi
if grep --text -q "~OPENPAREN~" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the ~OPENPAREN~ figure from the local.cfg file"
        grep --text "~OPENPAREN~" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi
if grep --text -q "~CLOSEPAREN~" $filetoread; then
        echo "ERROR: Reserved char sequence(s) found in input file."
        echo "       Please remove the ~CLOSEPAREN~ figure from the local.cfg file"
        grep --text "~CLOSEPAREN~" $filetoread;
        echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
        echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
        echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
        fi



cd $bpqdirectory
### Start converting the boilerplate file into the output result.
cp $boilerplatefile $temp_outwork1file

#### The process of reading through the local config file is destructive.  Use a temp copy
cp $filetoread $templocalfile



## delete any blank lines
sed -i '/^$/d' $templocalfile
#sed 's=~$=qq~~qq:qq~~qq=' < $templocalfile > $temptemplocalfile
#mv $temptemplocalfile $templocalfile






## Hide any spaces in the local data by converting them to SPACE tokens.
sed -i 's= =~SP~=g' $templocalfile


sed -i 's/~SP~$//g'  $templocalfile
sed -i 's/~SP~$//g'  $templocalfile
#sed -i 's/~SP~$//g'  $templocalfile

sed -i 's=(=~OPENPAREN~=g' $templocalfile
sed -i 's=)=~CLOSEPAREN~=g' $templocalfile
sed -i 's=(=~OPENPAREN~=g' $templocalfile
sed -i 's=)=~CLOSEPAREN~=g' $templocalfile
sed -i 's=(=~OPENPAREN~=g' $templocalfile
sed -i 's=)=~CLOSEPAREN~=g' $templocalfile

if grep --text -q "(" $templocalfile; then
   echo "ERROR";
   echo "ERROR: node.ini  --  a ( appears in the node.ini file";
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
   echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
   fi

if grep --text -q ")" $templocalfile; then
   echo "ERROR";
   echo "ERROR: node.ini  --  a ) appears in the node.ini file";
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
   echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
   fi


## removing trailing spaces in the local config
#sed 's=([^ \t\r\n])[ \t]+$==g' < $templocalfile > $temptemplocalfile
#echo -n "5"
#sed -i 's/[ \t]*$//' $templocalfile
#echo -n "A"
#exit 0;
#echo -n "B"



#### Until I can figure out how to get rid of trailing spaces automatically,
#### Announce that there is a problem and tell the user about it.
if grep --text "~SP~$" $templocalfile; then
   echo "ERROR: trailing spaces in node.ini -- please delete trailing spaces";
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: trailing spaces sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
   echo "trailing spaces sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
   exitForFailure
fi


### get rid of any ampersand in the local data by turning them into + signs
sed -i "s=&=+=" $templocalfile
sed -i "s=&=+=" $templocalfile
sed -i "s=&=+=" $templocalfile
sed -i "s=&=+=" $templocalfile


### Hide any single quotes in the local data by converting them to ~SINGLEQUOTE~ tokens
sed -i "s='=~SINGLEQUOTE~=" $templocalfile
sed -i "s='=~SINGLEQUOTE~=" $templocalfile
sed -i "s='=~SINGLEQUOTE~=" $templocalfile
sed -i "s='=~SINGLEQUOTE~=" $templocalfile

if grep --text -q "'" $templocalfile; then
   echo "ERROR";
   echo "ERROR: node.ini  --  a ' appears in the node.ini file";
   echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
   echo "make_local_bpq.sh: Reserved characters sequence found in node.ini file." >> $TARPNCOMMANDLOGFILE
   echo "Reserved characters sequence found in node.ini file" > /home/pi/bpq/makelocalfail.txt
       exitForFailure
fi


##### Replace infomessage not-set occurrences with a specific not-set token for infomessage so we can find it later
sed -i "s=infomessage1:not_set=infomessage1:BLANKLINE=" $templocalfile
sed -i "s=infomessage2:not_set=infomessage2:BLANKLINE=" $templocalfile
sed -i "s=infomessage3:not_set=infomessage3:BLANKLINE=" $templocalfile
sed -i "s=infomessage4:not_set=infomessage4:BLANKLINE=" $templocalfile
sed -i "s=infomessage5:not_set=infomessage5:BLANKLINE=" $templocalfile
sed -i "s=infomessage6:not_set=infomessage6:BLANKLINE=" $templocalfile
sed -i "s=infomessage7:not_set=infomessage7:BLANKLINE=" $templocalfile
sed -i "s=infomessage8:not_set=infomessage8:BLANKLINE=" $templocalfile




##### Look through local file for port enables.
##### We should have 12.  If we do not, then there is a problem.
#echo "make-local: verify neighbor tokens"
verifyNeighborToken "A"
verifyNeighborToken "B"
verifyNeighborToken "C"
verifyNeighborToken "D"
verifyNeighborToken "E"
verifyNeighborToken "F"
verifyNeighborToken "G"
verifyNeighborToken "H"
verifyNeighborToken "I"
verifyNeighborToken "J"

if grep --text -e "usb-port11:ENABLE" -e "usb-port11:DISABLE" $templocalfile; then
      if grep --text -q -e "usb-port11:ENABLE" $templocalfile; then
          if grep --text -q -e "portdev11:/dev/ttyACM" $templocalfile; then
             echo "ERROR: usb-port11 is pointing to a reserved devicename, /dev/ttyACM"
             echo "       ttyACM devices are not supported by port 11 or 12."
             if [ $(whoami) == "root" ];
             then
                echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
                echo "make_local_bpq.sh:  bad config for usb-port11, set to ttyACM."  >> $TARPNCOMMANDLOGFILE
                echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
                echo "make_local_bpq.sh:  sleep 1200 seconds, then exit."  >> $TARPNCOMMANDLOGFILE
                sleep 1200
              fi
              exit 1
          fi
      fi
      echo -n; #echo "found port12 enable-disable spec OK";
   else
      echo "ERROR: node.ini has no, or malformed, port11 enable-disable spec!"
      echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
      echo "make_local_bpq.sh: tncpi-port11 enable-disable spec missing in node.ini file." >> $TARPNCOMMANDLOGFILE
      echo "port spec missing in node.ini file" > /home/pi/bpq/makelocalfail.txt
      exitForFailure
   fi



if grep --text -q -e "usb-port12:ENABLE" -e "usb-port12:DISABLE" $templocalfile; then
      if grep --text -q -e "usb-port12:ENABLE" $templocalfile; then
          if grep --text -q -e "portdev12:/dev/ttyACM" $templocalfile; then
             echo "ERROR: usb-port12 is pointing to a reserved devicename, /dev/ttyACM"
             echo "       ttyACM devices are not supported by port 11 or 12."
             if [ $(whoami) == "root" ];
             then
                echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
                echo "make_local_bpq.sh:  bad config for usb-port12, set to ttyACM."  >> $TARPNCOMMANDLOGFILE
                echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
                echo "make_local_bpq.sh:  sleep 1200 seconds, then exit."  >> $TARPNCOMMANDLOGFILE
                sleep 1200
             fi
             exit 1
          fi
      fi
      echo -n; #echo "found port12 enable-disable spec OK";
   else
      echo "ERROR: node.ini has no, or malformed, port12 enable-disable spec!"
      echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
      echo "make_local_bpq.sh: tncpi-port12 enable-disable spec missing in node.ini file." >> $TARPNCOMMANDLOGFILE
      echo "port spec missing in node.ini file" > /home/pi/bpq/makelocalfail.txt
      exitForFailure
   fi

if grep --text -q -e "chatcall:"  $templocalfile;
   then
      echo -n; #echo "found chatcall spec OK";
   else
      #echo "ERROR: node.ini has no, or malformed, chatcall spec!"
       if grep --text -q -e "chatcall:"  $templocalfile;
       then
           echo -n; #echo "found chatcall spec OK on second look";
       else
           echo "ERROR: node.ini has no, or malformed, chatcall spec! -- run tarpn config"
           echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
           echo "make_local_bpq.sh: chatcall spec missing in node.ini file." >> $TARPNCOMMANDLOGFILE
           echo "chatcall missing or broken in node.ini file" > /home/pi/bpq/makelocalfail.txt
           exitForFailure
       fi
   fi




### Enable and disable the 12 ports.
### This code finds the string neighborA:not_set or neighborA:K1QRM-2 in the local config file.
### If the string is port1:ENABLE, it goes into the outputfile and s every string
### that is q~port1~q.
### if the string is port1:DISABLE, it goes into the outputfile and turns every q~port1~q into a comment.
### Finally, the port1:ENABLE or port1:DISABLE is deleted from the local config file and replaced
#### with synbol qq~~qq which means "blank line"
grep --text "ttyUSB_vs_ttyACM:" $templocalfile;
if grep --text -q -e "ttyUSB_vs_ttyACM:ttyACM" $templocalfile;
then
   echo "ttyACM found";
   __ttyACM="1";
else
   echo "ttyUSB found";
   __ttyACM="0";
fi


######### NOW do NinoTNC USB ports

##grep neighbor node.ini | grep ":" | grep "-" | wc -l > /tmp/tarpn/temp/numberofneigbors.txt
__numberOfNeighbors=$(grep --text neighbor $filetoread | grep ":" | grep "-" | wc -l)


__deviceNumberCounter=0;

## if [ $__numberOfPorts -gt "0" ];
## then
##   echo "there is at least 1 neighbor defined in node.ini"
## else
##    echo "There are no neighbors defined in node.ini"
## fi
if [ $__ttyACM -eq "1" ];
then
   __numberOfPorts=$(ls -l /dev/ttyACM* | wc -l)
   echo "Number of NinoTNC A3 and A4 units using ttyACM# device name = $__numberOfPorts"
   enablePortsInConfigFile "q~ninotnc_port01~q" "01"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port02~q" "02"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port03~q" "03"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port04~q" "04"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port05~q" "05"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port06~q" "06"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port07~q" "07"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port08~q" "08"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port09~q" "09"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port10~q" "10"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port11~q" "11"  "ACM" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
else
   __numberOfPorts=$(ls -l /dev/ttyUSB* | wc -l)
   echo "Number of NinoTNC A0,A1,A2,SMT units using ttyUSB# device name = $__numberOfPorts"
   enablePortsInConfigFile "q~ninotnc_port01~q" "01"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port02~q" "02"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port03~q" "03"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port04~q" "04"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port05~q" "05"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port06~q" "06"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port07~q" "07"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port08~q" "08"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port09~q" "09"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port10~q" "10"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
   enablePortsInConfigFile "q~ninotnc_port11~q" "11"  "USB" # pass in the PORTS name for G8BPQ's config file and the two numerical character string for the port number
fi
## delete the portdev variable for the remaining ports in boilerplate
#echo " "
#echo "Remove the remaining portdevs from the config file output"
__higherThanMaxPortDev=11
while [ $__deviceNumberCounter -lt 11 ];
do
#   echo "----top of while"
   __deviceTwoCharNumber="$__deviceNumberCounter";
   if [ $__deviceNumberCounter -lt 10 ];
   then
      __deviceTwoCharNumber="0$__deviceNumberCounter";
   fi
   #echo "/dev/ttyACM Number Counter is " $__deviceTwoCharNumber
   #echo "---port dev q~portdev$__deviceTwoCharNumber~q in config file "
   #grep "q~portdev$__deviceTwoCharNumber~q" $temp_outwork1file
   #echo "----"
   sed -i "s=q~portdev$__deviceTwoCharNumber~q=BZZZT$__deviceTwoCharNumber=" $temp_outwork1file
   __deviceNumberCounter=$(($__deviceNumberCounter+1))
   #echo "/dev/ttyACM Number Counter incremented to " $__deviceNumberCounter
   __numberOfPorts=$((__numberOfPorts-1))
   #echo "     bottom of while"
done




######### NOW do generic USB ports
if grep --text -q -e "usb-port11:ENABLE" $templocalfile; then
      echo  "port11 ENABLED";
      sed -i 's=q~usb-port11~q==' $temp_outwork1file
      sed -i 's=usb-port11:ENABLE=qq~~qq:qq~~qq=' $templocalfile
   else
      #echo  "port11 disabled";
      sed -i 's=q~usb-port11~q=;=' $temp_outwork1file
      sed -i 's=usb-port11:DISABLE=qq~~qq:qq~~qq=' $templocalfile
   fi
if grep --text -q -e "usb-port12:ENABLE" $templocalfile; then
      echo  "port12 ENABLED";
      sed -i 's=q~usb-port12~q==' $temp_outwork1file
      sed -i 's=usb-port12:ENABLE=qq~~qq:qq~~qq=' $templocalfile
   else
      #echo  "port12 disabled";
      sed -i 's=q~usb-port12~q=;=' $temp_outwork1file
      sed -i 's=usb-port12:DISABLE=qq~~qq:qq~~qq=' $templocalfile
   fi

echo " "
echo " "
##### CHAT CHAT CROWD CHAT CROWD CHAT CROWD CHAT CROWD CHAT CROWD #########
#echo "##### do CROWD node work"
if grep --text -q -e "chatcall:not_set" $templocalfile; then
      echo "CHAT callsign is missing"
      echo "ERROR: no, or malformed, CHAT callsign spec!"
      exitForFailure
else
      echo -n #echo "apply CHAT option to node";
fi

######## BBS BBS BBS BBS BBS BBS BBS BBS BBS BBS BBS BBS BBS BBS #######
if grep --text -q -e "bbscall:not_set" $templocalfile; then
      echo "Disable BBS application";
      sed -i 's=q~bbs-enable~q=;;; BBS is Disabled because bbscall is not_set !=' $temp_outwork1file
      sed -i 's=q~bbs-support~q=0=' $temp_outwork1file
else
      echo "Enable BBS application";
      sed -i 's=q~bbs-enable~q==' $temp_outwork1file
      sed -i 's=q~bbs-support~q=1=' $temp_outwork1file
fi




###### Uppercase the node callsign and node name
#### The BOILERPLATE calls for both uppercase AND lowercase versions of the callsign.
#### The node.ini file has lower case callsigns and nodenames
if grep --text -q -e "nodecall:" $templocalfile;
then
      _node_callsign=$(grep --text "nodecall" $templocalfile)
      _upper_node_callsign=${_node_callsign^^}
         echo $_upper_node_callsign >> $templocalfile;
fi
if grep --text -q -e "nodename:" $templocalfile;
then
      _node_callsign=$(grep --text "nodename" $templocalfile)
      _upper_node_callsign=${_node_callsign^^}
         echo $_upper_node_callsign >> $templocalfile;
fi


##### DISABLE or ENABLE local HOST mode based on whether local op callsign is "none" or something else.
if grep --text -q -e "local-op-callsign:none" $templocalfile; then
      echo  "no local op callsign set -- disable HOST mode";
      sed -i 's=q~host-enable~q=;DISABLED -- callsign was none=' $temp_outwork1file
      sed -i 's=q~host-mode-echo~q=NO-HOST-MODE=' $temp_outwork1file
   else
      echo  "local-op-callsign is specified.  Enable HOST mode";
      sed -i 's=q~host-enable~q==' $temp_outwork1file
      sed -i 's=q~host-mode-echo~q=HOST-MODE-ENABLED=' $temp_outwork1file
   fi

####### Create a ChatNode name from the chatcall
TEMPFILE=/tmp/tarpn/tempfileforchatnode.tmp
#echo "readfigure(" $1 ")"
#cp $templocalfile /home/pi/foo.2
#echo "read from " $templocalfile
#rm /home/pi/test.tmp
#grep "chatcall" $templocalfile > /home/pi/test.tmp
#echo "grep chatcall ="
#cat /home/pi/test.tmp
#echo " "
####if grep --text -q -e "chatcall" $templocalfile;
if grep --text -e "chatcall" $templocalfile;
then
        IFS=:
        rm -f $TEMPFILE
        grep --text "chatcall" $templocalfile > $TEMPFILE
        read key chatcall < $TEMPFILE
        #echo "key " $key
        #echo "value " $chatcall
else
        echo "No chatcall found in node.ini file.  Abort!"
        exitForFailure
fi


nodecallandsuffix=$chatcall-
ssid=00$(echo "$nodecallandsuffix" | awk -F '-' '{print $(NF-1)}');
#echo "ssid" $ssid;
#echo "chatcall" $chatcall;


endcallvalue=$(echo "$chatcall" | awk -F '-' '{print $(NF-1)}');
lastthreeofcall=${endcallvalue: -3}
lasttwodigitsofssid=${ssid: -2}
chatnode="z"$lastthreeofcall$lasttwodigitsofssid;
echo "chatnode:"$chatnode >> $templocalfile
#echo "chatnode has been written to " $templocalfile
#grep chatnode $templocalfile

######## OK.  chatnode: has been written to
#debug ----->cp $templocalfile /home/pi/foo.foo


#echo " "
#echo " "
#echo " "
#echo " "
#echo "Now read the remainder of the tokens from " $templocalfile
#echo " "


#echo "##### Read through local copy of config file, create keyname value list"

#### Read through the LOCAL config file, creating a list of KEYNAMES and VALUES.
while IFS=: read key value; do
    declare -A hash[$key]=$value
done < $templocalfile

rm $templocalfile

## Diagnostic Output
#echo " "
#echo "This is a list of the KEYNAMES and the values for those names"
#for key in "${!hash[@]}"
#do
#  echo "'$key':'${hash[$key]}'"
#done

### Diagnostic Output
#echo " "
#echo "This is the BOILERPLATE lines where KEYNAMES were found:"
#for key in "${!hash[@]}"
#do
#  grep "q~$key~q" $boilerplatefile;
#done



####
#### This loop will go through each element of the LOCAL config file, pulling
#### out the KEYNAME (first item on each line) and searching for that KEYNAME
#### in the boilerplate file.  Wherever the KEYNAME is found, it is replaced
#### with the value specified in the LOCAL config file.
#### If any KEYNAME exists that is NOT in the boilerplate file, thi#!/bin/bash

##### Make sure there are no token-like figures in the local config file


if grep --text -q "~q" $filetoread; then
        echo "ERROR: Reserved character sequence(s) found in node.ini"
        echo "       Please remove the ~q figure from node.ini"
        grep --text "~q" $filetoread;
        exitForFailure
        fi

if grep --text -q "q~" $filetoread; then
        echo "ERROR: Reserved character sequence(s) found in node.ini"
        echo "       Please remove the q~ figure from the node.ini file"
        grep --text "q~" $filetoread;
        exitForFailure
        fi

if grep --text -q "~SP~" $filetoread; then
        echo "ERROR: Reserved character sequence(s) found in node.ini"
        echo "       Please remove the ~SP~ figure from the node.ini file"
        grep --text "~SP~" $filetoread;
        exitForFailure
        fi

#### back-up the node.ini file
cp $filetoread $templocalfile
#### Convert spaces in the node.ini file to tokens.
sed -i 's= =~SP~=g' $templocalfile

#### Remove trailing tokens
sed -i 's/~SP~$//g'  $templocalfile
sed -i 's/~SP~$//g'  $templocalfile

#### Verify that node.ini is created.


if grep --text -q -e "nodename:" $templocalfile; then
      echo -n;
   else
          echo -n "ERROR: Incorrect specification in "
          echo $filetoread
      echo "ERROR: Node nodename spec!"
      exitForFailure
   fi




#echo "##### Key list - convert Keys to values in work1file"


#### We believe we have a node.ini file
for key in "${!hash[@]}"
  do
    startstring="q~$key~q";
    #echo $startstring;
    if [ $startstring == "q~qq~~qq~q" ]; then
       echo -n
        else
       #echo "##### Looking for -->$startstring<-- to change it to -->${hash[$key]}<--";
       if grep --text -q "$startstring" $temp_outwork1file; then
         sed -i 's='$startstring'='${hash[$key]}'=g' $temp_outwork1file
         #cat $temp_outwork1file;
       else
         echo -n "ERROR: NO MATCH    "
         echo $key
         echo "ERROR: Unexpected token in node.ini file! -- not found in boilerplate"
         exitForFailure
       fi
    fi
 done
#echo "##### done with Key list.  Now replace special symbols"

### fix the KISSOPTIONS lines for ports 11 and 12
sed -i 's=XXenableXX=;KISSOPTIONS is default to on=g' $temp_outwork1file
sed -i 's~XXdisableXX~KISSOPTIONS=NOPARAMS~g' $temp_outwork1file


## Now translate the SPACE tokens for real spaces
#echo "translate SPACE tokens"
sed -i 's=~SP~= =g' $temp_outwork1file

## Now translate the SINGLEQUOTE tokens for real single quotes
#echo "translate SINGLEQUOTE tokens"
sed -i "s=~SINGLEQUOTE~='=g" $temp_outwork1file
sed -i "s=~OPENPAREN~=(=g" $temp_outwork1file
sed -i "s=~CLOSEPAREN~=)=g" $temp_outwork1file

## Remove infotext blanklines
sed -i ':a; /BLANKLINE$/ { N; s/BLANKLINE\n//; ba; }' $temp_outwork1file
##sed -i 's=BLANKLINE\n==' $temp_outwork1file

## Translate the <CR> symbols with carriage returns
#echo "translate CRLF tokens"
sed -i 's=CRLF=\n=g' $temp_outwork1file
#sed ':a;N;$!ba;s/\n/ /g'

#echo "verify that tokens are all d"
##### Now verify that all of the tokens have been replaced in the output file.
if grep --text -q "~q" $temp_outwork1file; then
        echo "ERROR: Unresolved token(s) for bpq config - look in node.ini?"
        echo "       Please add or fix the spelling of this (these) token in the node.ini file"
        grep --text "~q" $temp_outwork1file;
        exitForFailure
        fi
if grep --text -q "q~" $temp_outwork1file; then
        echo "ERROR: Unresolved token(s) for bpq config - look in node.ini?"
        echo "       Please add or fix the spelling of this (these) token in the node.ini file"
        grep --text "q~" $temp_outwork1file;
        exitForFailure
        fi

if grep --text -q -e "op is none" $templocalfile; then
      sed -i 's=op is none=see http://tarpn.net for info=' $temp_outwork1file
   fi

#get rid of spurious KeepForTarpnHome which needs to be in node.ini until TARPN-HOME is revised to v3.
#but it doesn't need to be in bpq32.cfg
if grep --text -q -e "KeepForTarpnHome" $templocalfile; then
      sed -i 's=KeepForTarpnHome=;Keep=' $templocalfile
fi

################################# Make a copy of the node.ini file for TARPN-HOME's consumption
NODEDEF="/tmp/tarpn/tarpn_home__node_defines.ini"
sudo rm -rf $NODEDEF
grep --text nodecall: $filetoread > $NODEDEF
grep --text nodename: $filetoread >> $NODEDEF
grep --text "local-op-callsign:" $filetoread >> $NODEDEF
grep --text "neighborA:" $filetoread >> $NODEDEF
grep --text "neighborB:" $filetoread >> $NODEDEF
grep --text "neighborC:" $filetoread >> $NODEDEF
grep --text "neighborD:" $filetoread >> $NODEDEF
grep --text "neighborE:" $filetoread >> $NODEDEF
grep --text "neighborF:" $filetoread >> $NODEDEF
grep --text "neighborG:" $filetoread >> $NODEDEF
grep --text "neighborH:" $filetoread >> $NODEDEF
grep --text "neighborI:" $filetoread >> $NODEDEF
grep --text "neighborJ:" $filetoread >> $NODEDEF
if grep --text -q "usb-port11:ENABLE" $filetoread; then
   grep --text neighbor11: $filetoread >> $NODEDEF
else
   echo "neighbor11:NOT_SET" >> $NODEDEF
fi
if grep --text -q "usb-port12:ENABLE" $filetoread; then
   grep --text neighbor12: $filetoread >> $NODEDEF
else
   echo "neighbor12:NOT_SET" >> $NODEDEF
fi

sed -i 's/neighborA/neighbor01/' $NODEDEF
sed -i 's/neighborB/neighbor02/' $NODEDEF
sed -i 's/neighborC/neighbor03/' $NODEDEF
sed -i 's/neighborD/neighbor04/' $NODEDEF
sed -i 's/neighborE/neighbor05/' $NODEDEF
sed -i 's/neighborF/neighbor06/' $NODEDEF
sed -i 's/neighborG/neighbor07/' $NODEDEF
sed -i 's/neighborH/neighbor08/' $NODEDEF
sed -i 's/neighborI/neighbor09/' $NODEDEF
sed -i 's/neighborJ/neighbor10/' $NODEDEF
###### End of "Make a copy of the node.ini file for TARPN-HOME's consumption"






### We are done!
mv $temp_outwork1file $outputfile

#### Create the Files folder if one does not exist
if [ ! -d $filesFolderForBbs ];
then
   mkdir $filesFolderForBbs
fi
sudo chmod 777 $filesFolderForBbs

grep --text -v "^PASSWORD=" $outputfile | grep --text -v "sysop password" | grep --text -o '^[^;]*' > $temp_outwork1file

awk 'sub("$", "\r")' $temp_outwork1file > $bpqConfigImageInFilesFolder
rm $temp_outwork1file
echo "SUCCESS..."
