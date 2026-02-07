#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC




##### CHECK PROCESS
##### This looks to see if the specified process is running.
##### returns 0 if not running.  Returns 1 if running
check_process()
{
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

###### NO CONFIG WITH NODE RUNNING
###### Outputs a text warning and then exits
noConfigWithNodeRunning()
{
   echo "######"
   echo "######"
   echo "######"
   echo "Config is disabled while node is auto-loading or running."
   echo "                     You should do"
   echo "tarpn service stop       then do"
   echo "tarpn                over and over until it says the node is not running"
   echo "                     When the node is no longer running, do"
   echo "tarpn config     then"
   echo "tarpn test       and then if all is well and when you are done testing"
   echo "tarpn service start"
   exit 1
}

#######  READ FIGURE FROM NODE.INI FILE.
####### Called with the name of a KEY.  This function finds the KEY and reads its matching VALUE into $value.
####### Returns 0 if KEY was found.  Returns 1 if KEY was NOT found.
### NODEWORK points to a temp-file which contains the ini file before this config session.
### TEMPFILE points to a temp-file which is deleted and created in this function.
### the TEMPFILE file is never used outside of this function
ReadFigureFromNodeIniFile()
{
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      echo "newValueFor()   tarpn update appears to be in progress.  Come back after it is done"
      exit 0;
   fi
   #echo "readfigure(" $1 ")"
   if grep -q -e "$1" $NODEWORK;
   then
       IFS=:
       rm -f $TEMPFILE
       grep "$1" $NODEWORK > $TEMPFILE
       read key value < $TEMPFILE
       #echo "key " $key
       #echo "value " $value
       return 0;
   else
       return 1;
   fi
}

######## NEW VALUE FOR
######## This prompts the user to keep or replace a value.  This then reads in the value if any.
######## Returns the new value if any, or the old value if no new value was entered.
newValueFor()
{
   if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
   then
      echo "newValueFor()   tarpn update appears to be in progress.  Come back after it is done"
      exit 0;
   fi
   TEMP_FILE="/home/pi/newvaluetempfile.tmp"
   value=$2;
   echo -n "$1 = $2 -->"
   read newvalue
   if [ -n "$newvalue" ];
   then
      value=$newvalue;
          rm -f $TEMP_FILE
          echo $newvalue | cut -b1 > $TEMP_FILE;
          if grep -q -e "\." $TEMP_FILE;
          then
            value="not_set"
            echo "First char was period -- Making value = not_set";
          fi
          rm -f $TEMP_FILE
   fi
   echo
   sleep 0.1
}



######### GET YES NO
######### This uses 'newValueFor( )' to read in the text YES or NO for a boolean.
######### If the response is "yes", returns _boolean=1
######### If response is "no" returns _boolean=0

getYesNo()
{
  _success=0;
  while [ $_success -eq 0 ];
  do
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo "getYesNo()   tarpn update appears to be in progress.  Come back after it is done"
       exit 0;
    fi
    newValueFor "$1 yes or no" $2;      __block_text=$value;
        _upper_block_text=${__block_text^^}

    if [ $_upper_block_text == "YES" ];
    then
      _success=1;
      _boolean=1;
     #echo "setting _block_enable to 1.  _block_enabled=" $_block_enabled
    else
      if [ $_upper_block_text == "NO" ];
      then
        _success=1;
        _boolean=0;
        #echo "setting _block_enable to 0.  _block_enabled=" $_block_enabled
      else
        echo "Enter   yes   or enter   no"
      fi
    fi
  done
  #echo "getBlockEnable() return _block_enabled=" $_block_enabled
}

######### GET BLOCK ENABLE
######### This uses 'newValueFor( )' to read in the text ENABLE or DISABLE for a PORT number.
######### If the response is "enable", returns _block_enabled=1
######### If response is "disable" returns _block_enabled=0

getBlockEnable()
{
  _success=0;
  while [ $_success -eq 0 ];
  do
    if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
    then
       echo "getBlockEnable()   tarpn update appears to be in progress.  Come back after it is done"
       exit 0;
    fi
    newValueFor "$1 enable or disable" $2;      __block_text=$value;
        _upper_block_text=${__block_text^^}

    if [ $_upper_block_text == "ENABLE" ];
    then
      _success=1;
      _block_enabled=1;
     #echo "setting _block_enable to 1.  _block_enabled=" $_block_enabled
    else
      if [ $_upper_block_text == "DISABLE" ];
      then
        _success=1;
        _block_enabled=0;
        #echo "setting _block_enable to 0.  _block_enabled=" $_block_enabled
      else
        echo "Enter   enable   or enter   disable"
      fi
    fi
  done
  #echo "getBlockEnable() return _block_enabled=" $_block_enabled
}

STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE="/tmp/stop_service_scripts.txt"

if [ -f $STOP_SERVICE_SCRIPT_EXECUTION_SEMAPHORE ];
then
   echo "tarpn update appears to be in progress.  Come back after it is done"
   exit 0;
fi


## Version 24 -- support blank lines and single quotes in INFO text.
## Version 25 11/12/2014    Added echo comments about DECIMAL i2c addresses
## Version 26 12/14/2014    add getYesNo( )   start asking if Mobile Node
## Version 27 12/14/2014    Create config for each port for facing mobile node.
## Version 28  2/21/2015    Grab yes/no code from mobile-node project.
## Version 29  2/21/2015    Remove mobile node code.
## Version 30  6/24/2015    Tune the text around INFO text.
## Version 31  6/30/2015    Fix missing quote
## Version 32  8/10/2017    Remove the check for INITTAB.  It isn't needed anymore
## Version 33  9/25/2017    Add support for BBSCALL and BBSNODE
## Version 34  9/28/2017    Fix prompt text.  BBS Callsign   BBS Nodename
## Version 35 10/03/2017    Fix prompt text.  BBS Nodename is 6 characters, not 4
## Version 36 10/12/2017    Fix the node-is-running error message
## Version 37  5/12/2018    Add Chat Node option
## Version 38  7/03/2018    stop prompting for BBS node name
## Version 39  7/26/2018    Chat Callsign is required.
## Version 40  8/17/2018    Change prompt for neighbor node to specific that it is a callsign we want.
## Version 41 10/07/2018    Prompt for lat/lon or grid-square, instead of just grid-square.
## Versopm 42 10/20/2018    Add notes about quotes and ampersands.  Stop mentioning grid-square.
## Version 43  2/11/2018    Add elements for multiple Raspberry PIs per node site
## Version 44  4/19/2020    modify node.ini to support 4 TNC-PI and 6 NinoTNC
## Version 46  4/19/2020    debugging ninotnc support
## Version 46  4/19/2020    fix broken frack07 symbol
## Version 47  4/19/2020    add ls and grep for ttyACM and ttyUSB
## Version 48  4/19/2020    fix broken portdev output
## version 49  4/19/2020    list USB devices just before asking what to do with port 5
## version 50  4/20/2020    put the names of port05 and port06 back to tncpi-port05 and tncpi-port06 to fix TARPN-HOME dependency
## version 51  5/24/2020    slow down the display of the /dev devices with sleep instructions
## version 52  5/24/2020    kludge port05 and 06 so we get ninotnc_port and tncpi-port
## version 53  5/25/2020    improve the text before showing port 5
## version 54  5/26/2020    minor text/comment improvements
## version 55 10/31/2020    start adding USB ID/KAUP8R
## version 56  2/21/2021    fix some prompts
## version 57  3/03/2021    if we run into a 1111 answer for a get-kauper, then close out the configuration immediately.
## version 58  5/16/2021    Upper case the neighbor callsigns before writing them to the node.ini file.
## version 59  5/23/2021    Improve the description in location prompt.
## version 60  5/23/2021    Fix check_process()
## version 70  6/03/2021    Start rework for NPA Node Port Assignment
## version 71  6/07/2021    chat callsigns are "automatic"
## version 72  6/07/2021    Make sure to read the old chat neighbor calls if NODE.INI exists.
## version 73  6/13/2021    Fix the case on callsigns port 11 and 12.
## version 74  6/23/2021    Fix prompt for port 11.
## version 75  7/24/2021    Make the prompt for ports 11 and 12 mention "fully qualified directory path".
## version 76 10/17/2021    Fix typo in the NODENAME description.  Add detail in the FRACK description.
## version 77 10/19/2021    Improve prompting around the preloaded ssid/callsign data.   Restore check-process to working order
## version 78 10/20/2021    Minor prompt change before ports 11 and 12 about using for NinoTNC
## version 79 10/22/2021    Improve the prompting for ports 11 and 12.
## bullseye001  11/13/2021  Fix trailing null in source-url
## bullseye002  4/3/2022    Fix a spelling error.
## bullseye003  8/19/2023   Add kissparam settings for port 11 and 12
## bullseye004  1-13-2025   fix spelling error KM9G found.   Clean up language around the description of ports 11 and 12
## bullseye005  6-06-2025   Use the same define for TARPNCOMMANDLOG in every script file that refers to that log file.
## bullseye006 11-24-2025   Revise the Version Number output for grepping by update and tarpn scripts   -- add exit traps for STOP SCRIPT SEMAPHORE

##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
echo "####"                                                             ######
echo "####"                                                             ######
echo "#### --VERSION--CONFIGURE_NODE.SH         Bullseye006- START"     ######
echo "####"                                                             ######
echo "####"                                                             ######
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################

TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"
echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
echo "CONFIGURE NODE"  >> $TARPNCOMMANDLOGFILE

sleep 1

NODEINI="/home/pi/node.ini"
TEMPFILE="/tmp/tarpn/temp/configure-node-work-file2.tmp"
NODEWORK="/tmp/tarpn/temp/configure-node-work-file.tmp"
NODEINI_INPROG="/tmp/tarpn/temp/node-ini-inprog.tmp"
rm -f $TEMPFILE
rm -f $NODEWORK
rm -f $NODEINI_INPROG

######### Refuse to operate if we can't write and read-back in the /home/pi directory.

cd /home/pi
rm -f /home/pi/testfile.txt             ## this is to prove we can access home/pi
if [ -f /home/pi/testfile.txt ];
then
    echo "##### ERROR1: unable to write to /home/pi.  This needs to be run as user pi."
    exit 1;
else
    #### There is no testfile.txt in the pi home directory.  This is good.  Now see if we can create one.
    echo "test" > /home/pi/testfile.txt
    if [ -f /home/pi/testfile.txt ];
    then
       ### there wasn't a testfile.  There is now.  This is good.  Delete it and move on
       rm -f /home/pi/testfile.txt
    else
       #### There wasn't a testfile.  There still isn't.  This is a problem.
       echo "##### ERROR2: Unable to write to /home/pi.  This needs to be run as user PI."
       exit 1
    fi
fi

### Don't run if the source_url.txt file is not set.
if [ -f /usr/local/sbin/source_url.txt ];
then
    echo -n;
else
   echo "ERROR0: source URL file not found."

   echo "ERROR0:"
   echo "ERROR0: Aborting"
   exit 1
fi
_source_url=$(tr -d '\0' </usr/local/sbin/source_url.txt);

check_process "linbpq"
if [ $? -ge 1 ]; then
   echo "#####  BPQ node is running."
   noConfigWithNodeRunning;
fi

if [ -d /tmp/tarpn ]; then
   echo -n
else
   echo "The TARPN environment is supposed to have set up some temporary file space"
   echo "which appears to not have been set up.  Please complain on tarpn@groups.io"
   echo "about this.   You are in TARPN CONFIG - about TMP space not set up.  Thanks!"
   echo "-- ka2dew"
   exit 1
fi

####### Refuse to run if the tarpn.service is not loaded and running.
####### This is the OS service.  That doesn't mean that G8BPQ is running.
sudo systemctl status tarpn.service > $TEMPFILE
if grep -q "Active: active (running) since" $TEMPFILE
then
  rm -f $TEMPFILE
  echo
else
  rm -f $TEMPFILE
  echo "The required OS-process, called tarpn, is not running."
  echo "Please do a tarpn update  to fix this."
  exit 1
fi





###### Set up default values for a node.ini file

manual_chat_config="no"
chat_cA="automatic"
chat_cB="automatic"
chat_cC="automatic"
chat_cD="automatic"
chat_cE="automatic"
chat_cF="automatic"
chat_cG="automatic"
chat_cH="automatic"
chat_cI="automatic"
chat_cJ="automatic"
chat_c11="automatic"
chat_c12="automatic"
nodecall="callsn-2"
nodename="6letters"
bbscall="callsn-1"
chatcall="callsn-9"
latlon='10.0000, -10.0000'
infomessage1="not_set"
infomessage2="not_set"
infomessage3="not_set"
infomessage4="not_set"
infomessage5="not_set"
infomessage6="not_set"
infomessage7="not_set"
infomessage8="not_set"
ctext="not_set"
local_op_callsign="none"
sysop_password="not_set"

neighborA="NOT_SET"
neighborB="NOT_SET"
neighborC="NOT_SET"
neighborD="NOT_SET"
neighborE="NOT_SET"
neighborF="NOT_SET"
neighborG="NOT_SET"
neighborH="NOT_SET"
neighborI="NOT_SET"
neighborJ="NOT_SET"
frackA=9000
frackB=9000
frackC=9000
frackD=9000
frackE=9000
frackF=9000
frackG=9000
frackH=9000
frackI=9000
frackJ=9000

usb_port11="DISABLE"
speed11=57600
txdelay11=1000
portdev11=/dev/ttyUSB0
frack11=9000
kissoptions11="enable"
neighbor11="not_set"

usb_port12="DISABLE"
speed12=57600
txdelay12=1000
portdev12=/dev/ttyUSB1
frack12=9000
kissoptions12="enable"
neighbor12="not_set"


########### If there is already a node.ini file, read it in, overwriting the default values

if [ -f $NODEINI ];
then
   echo
   echo "NOTE:  You can control-C out of this process at any time if you"
   echo "       decide you don't really want to change your config or if you"
   echo "       see that you have made a mistake and want to make it go away."
   echo
   cp $NODEINI $NODEWORK    ##/home/pi/node.ini -> /tmp/tarpn/temp/configure-node-work-file.tmp

   ReadFigureFromNodeIniFile "manual_chat_config"; if [ $? -eq 0 ]; then manual_chat_config=$value; fi
   ReadFigureFromNodeIniFile "nodecall";           if [ $? -eq 0 ]; then nodecall=$value; fi
   ReadFigureFromNodeIniFile "nodename";           if [ $? -eq 0 ]; then nodename=$value; fi
   ReadFigureFromNodeIniFile "bbscall";            if [ $? -eq 0 ]; then bbscall=$value; fi
   ReadFigureFromNodeIniFile "chatcall";           if [ $? -eq 0 ]; then chatcall=$value; fi
   ReadFigureFromNodeIniFile "latlon";             if [ $? -eq 0 ]; then latlon=$value; fi
   ReadFigureFromNodeIniFile "infomessage1";       if [ $? -eq 0 ]; then infomessage1=$value; fi
   ReadFigureFromNodeIniFile "infomessage2";       if [ $? -eq 0 ]; then infomessage2=$value; fi
   ReadFigureFromNodeIniFile "infomessage3";       if [ $? -eq 0 ]; then infomessage3=$value; fi
   ReadFigureFromNodeIniFile "infomessage4";       if [ $? -eq 0 ]; then infomessage4=$value; fi
   ReadFigureFromNodeIniFile "infomessage5";       if [ $? -eq 0 ]; then infomessage5=$value; fi
   ReadFigureFromNodeIniFile "infomessage6";       if [ $? -eq 0 ]; then infomessage6=$value; fi
   ReadFigureFromNodeIniFile "infomessage7";       if [ $? -eq 0 ]; then infomessage7=$value; fi
   ReadFigureFromNodeIniFile "infomessage8";       if [ $? -eq 0 ]; then infomessage8=$value; fi
   ReadFigureFromNodeIniFile "ctext";              if [ $? -eq 0 ]; then ctext=$value; fi
   ReadFigureFromNodeIniFile "local-op-callsign";  if [ $? -eq 0 ]; then local_op_callsign=$value; fi
   ReadFigureFromNodeIniFile "sysop-password";     if [ $? -eq 0 ]; then sysop_password=$value; fi

   ReadFigureFromNodeIniFile "Chat Neighbor Call A";             if [ $? -eq 0 ]; then chat_cA=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call B";             if [ $? -eq 0 ]; then chat_cB=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call C";             if [ $? -eq 0 ]; then chat_cC=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call D";             if [ $? -eq 0 ]; then chat_cD=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call E";             if [ $? -eq 0 ]; then chat_cE=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call F";             if [ $? -eq 0 ]; then chat_cF=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call G";             if [ $? -eq 0 ]; then chat_cG=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call H";             if [ $? -eq 0 ]; then chat_cH=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call I";             if [ $? -eq 0 ]; then chat_cI=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call J";             if [ $? -eq 0 ]; then chat_cJ=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call 11";            if [ $? -eq 0 ]; then chat_c11=$value; fi
   ReadFigureFromNodeIniFile "Chat Neighbor Call 12";            if [ $? -eq 0 ]; then chat_c12=$value; fi


   ReadFigureFromNodeIniFile "frackA";             if [ $? -eq 0 ]; then frackA=$value; fi
   ReadFigureFromNodeIniFile "frackB";             if [ $? -eq 0 ]; then frackB=$value; fi
   ReadFigureFromNodeIniFile "frackC";             if [ $? -eq 0 ]; then frackC=$value; fi
   ReadFigureFromNodeIniFile "frackD";             if [ $? -eq 0 ]; then frackD=$value; fi
   ReadFigureFromNodeIniFile "frackE";             if [ $? -eq 0 ]; then frackE=$value; fi
   ReadFigureFromNodeIniFile "frackF";             if [ $? -eq 0 ]; then frackF=$value; fi
   ReadFigureFromNodeIniFile "frackG";             if [ $? -eq 0 ]; then frackG=$value; fi
   ReadFigureFromNodeIniFile "frackH";             if [ $? -eq 0 ]; then frackH=$value; fi
   ReadFigureFromNodeIniFile "frackI";             if [ $? -eq 0 ]; then frackI=$value; fi
   ReadFigureFromNodeIniFile "frackJ";             if [ $? -eq 0 ]; then frackJ=$value; fi
   ReadFigureFromNodeIniFile "neighborA";          if [ $? -eq 0 ]; then neighborA=$value; fi
   ReadFigureFromNodeIniFile "neighborB";          if [ $? -eq 0 ]; then neighborB=$value; fi
   ReadFigureFromNodeIniFile "neighborC";          if [ $? -eq 0 ]; then neighborC=$value; fi
   ReadFigureFromNodeIniFile "neighborD";          if [ $? -eq 0 ]; then neighborD=$value; fi
   ReadFigureFromNodeIniFile "neighborE";          if [ $? -eq 0 ]; then neighborE=$value; fi
   ReadFigureFromNodeIniFile "neighborF";          if [ $? -eq 0 ]; then neighborF=$value; fi
   ReadFigureFromNodeIniFile "neighborG";          if [ $? -eq 0 ]; then neighborG=$value; fi
   ReadFigureFromNodeIniFile "neighborH";          if [ $? -eq 0 ]; then neighborH=$value; fi
   ReadFigureFromNodeIniFile "neighborI";          if [ $? -eq 0 ]; then neighborI=$value; fi
   ReadFigureFromNodeIniFile "neighborJ";          if [ $? -eq 0 ]; then neighborJ=$value; fi

   ReadFigureFromNodeIniFile "usb-port11";         if [ $? -eq 0 ]; then usb_port11=$value; fi
   ReadFigureFromNodeIniFile "speed11";            if [ $? -eq 0 ]; then speed11=$value; fi
   ReadFigureFromNodeIniFile "txdelay11";          if [ $? -eq 0 ]; then txdelay11=$value; fi
   ReadFigureFromNodeIniFile "portdev11";          if [ $? -eq 0 ]; then portdev11=$value; fi
   ReadFigureFromNodeIniFile "frack11";            if [ $? -eq 0 ]; then frack11=$value; fi
   ReadFigureFromNodeIniFile "kissoptions11";      if [ $? -eq 0 ]; then kissoptions11=$value; fi
   ReadFigureFromNodeIniFile "neighbor11";         if [ $? -eq 0 ]; then neighbor11=$value; fi

   ReadFigureFromNodeIniFile "usb-port12";         if [ $? -eq 0 ]; then usb_port12=$value; fi
   ReadFigureFromNodeIniFile "speed12";            if [ $? -eq 0 ]; then speed12=$value; fi
   ReadFigureFromNodeIniFile "txdelay12";          if [ $? -eq 0 ]; then txdelay12=$value; fi
   ReadFigureFromNodeIniFile "portdev12";          if [ $? -eq 0 ]; then portdev12=$value; fi
   ReadFigureFromNodeIniFile "frack12";            if [ $? -eq 0 ]; then frack12=$value; fi
   ReadFigureFromNodeIniFile "kissoptions12";      if [ $? -eq 0 ]; then kissoptions12=$value; fi
   ReadFigureFromNodeIniFile "neighbor12";         if [ $? -eq 0 ]; then neighbor12=$value; fi

else
   #### This looks like the first time this program was run.  Let's work with the ops callsign then.

   echo
   echo "This is the first time you've run this configurator."
   echo
   newValueFor "local_op_callsign" $local_op_callsign;   local_op_callsign=$value;
   echo
   sleep 1
   echo
   echo "        I'm going to use your callsign to auto-fill some of the identification"
   echo "        and then put you into the configurator in the verbose mode but with"
   echo "        some of the answers filled in. "
   echo


   nodecall="$local_op_callsign-2"
   bbscall="$local_op_callsign-1"
   chatcall="$local_op_callsign-9"
   echo
   echo "I've set up some of the required identification callsigns based on $local_op_callsign."
   echo "node callsign=$nodecall"
   echo "BBS callsign =$bbscall"
   echo "CHAT callsign=$chatcall"
   echo "                                   These callsigns and -SSID numbers"
   echo "                                   will be what the other nodes expect."
   echo "                                   You will be prompted for these same"
   echo "                                   values shortly.  You can <RETURN>"
   echo "                                   to accept the prepared answers."
   echo
   echo "                                   Hit <RETURN> to continue"
   sleep 1
   read newvalue
   echo
   echo "Entering normal full-comments TARPN CONFIG..."
   echo
   sleep 1
   echo
fi


#########  PROMPT the user to make changes to any figure.


echo "############################################################################"
echo
echo "This program prompts for configuration values"
echo "you will see a description/name of each config item, and then"
echo "you will see the current value of that config item.  If you like"
echo "the current value, just hit ENTER/RETURN on your keyboard."
echo "To change the setting, type a new value and then hit ENTER/RETURN".
echo
echo "Your changes are saved when you reach the end of this program."
echo "Use Control-C on your keyboard to exit without saving changes."
sleep 0.1
echo
sleep 0.1
echo
echo "local op callsign is used by the node when an operator controls the"
echo "node locally.  This is used for CHAT, for sending and receiving"
echo "packets and messages when the local operator is involved."
echo "This should be set to your legal callsign, with no -SSID,"
echo "or to the word 'none'."
echo "If this is set to none, then console access is disabled.  "
echo "You can use the same local op callsign on more than one node."
echo
sleep 0.5
echo
newValueFor "local_op_callsign" $local_op_callsign;   local_op_callsign=$value;
echo
echo "NODE CALLSIGN"
echo "The node callsign is probably your callsign dash 2, for instance: w1aw-2"
echo "The software limitations are that it can be -0 through -15 but convention"
echo "has it that you not use -0 or -15.  -2 is sort of a standard around here."
echo

newValueFor "Node Callsign" $nodecall;                                    nodecall=$value;
echo
echo "NODENAME.  This is 6 characters, allupper case, and is usually your"
echo "first name, last name, or some abbreviation of your first name."
echo "Choose something the other node operators can remember for you."
echo
newValueFor "Node Name, max 6 chars, no spaces or punctuation" $nodename; nodename=$value;
echo
echo "SYSOP password is for answering the PASSWORD challenge."
echo "See http://www.cantab.net/users/john.wiseman/Documents/Node%20SYSOP.html"
echo "You should probably leave set this to the group password or discuss it"
echo "with who-ever is managing the L3 and L4 parameters for your node."
echo "Note: No double quotes, no single quotes and no ampersands."
echo
newValueFor "SYSOP password" $sysop_password;      sysop_password=$value;

echo
echo
echo "BBS Callsign"
echo "Leave set to not_set unless you want to operate a BBS on this Raspberry PI"
echo "You can change this later."
echo "Set bbscall to be your callsign -1  "
echo "To switch off the BBS function, set the BBS Callsign to a period ."
echo
newValueFor "BBS Callsign" $bbscall;                                    bbscall=$value;

echo
echo
echo "CHAT callsign"
echo "Every G8BPQ node in the network has a CHAT service.  Each nees a unique callsign"
echo "which cannot be the same as any BBS or node in the network."
echo "We recommend using the owner operator callsign with a -9."
echo
newValueFor "CHAT callsign" $chatcall;                                    chatcall=$value;


echo
echo "LOCATION: "
echo "Lattitude and Longitude.  This information is used to automatically"
echo "create network maps which will be public and published at high"
echo "resolution.  The information is needed to allow the maps to show"
echo "relative positions of the various nodes.  It should be precise BUT"
echo "it does not need to be accurate!  I recommend putting it in the next"
echo "neighborhood or something obscure.  Just try to make it indicative"
echo "both of what town your node is in and where you are relative to the"
echo "other nearby nodes in your local network."
echo
echo "Enter latitude, longitude for your node representation on maps."
echo "Use Google Earth or GPS receiver to appropriate values.  "
echo "Lat/Lon format in the US should be something like 33.4515, -83.7773"
echo "4 decimal places on each should be good enough. "
echo "###"
echo
newValueFor "node location, lat, lon" $latlon;              latlon=$value;

check_process "linbpq"
if [ $? -ge 1 ]; then
   echo
   echo "##### ERROR!"
   echo "#####        BPQ node is running."
   echo "#####        ... it must have started since you entered config".
   noConfigWithNodeRunning;
fi


echo
sleep 0.1
echo "INFO TEXT"
echo "This next value is the INFO message text.  This is what the user gets if"
echo "they use the I or INFO command.  This text can be several lines long."
echo "Each line is in a separate field.  infomessage1 is the 1st line."
echo "infomessage8 is the last line.  not_set lines are removed from the INFO response."
echo
echo "This is the current output for the INFO text:"
echo "--------------------------------------------------------------------------------"
echo $infomessage1;
echo $infomessage2;
echo $infomessage3;
echo $infomessage4;
echo $infomessage5;
echo $infomessage6;
echo $infomessage7;
echo $infomessage8;
echo "--------------------------------------------------------------------------------"
echo "Now you can change any lines.  I recommend you copy and paste from a text"
echo "file as you go through this so you can get the result you want."
echo
echo "Any line that is not to be used should be left as    not_set  or may be set to"
echo "have just a period.  Lines with a period in the first character will be replaced"
echo "with not_set and not_set lines will not be included in the INFO response."
echo "Note: No double quotes, no single quotes, no colons, and no ampersands."
echo
newValueFor "INFO line 1" $infomessage1;         infomessage1=$value;
newValueFor "INFO line 2" $infomessage2;         infomessage2=$value;
newValueFor "INFO line 3" $infomessage3;         infomessage3=$value;
newValueFor "INFO line 4" $infomessage4;         infomessage4=$value;
newValueFor "INFO line 5" $infomessage5;         infomessage5=$value;
newValueFor "INFO line 6" $infomessage6;         infomessage6=$value;
newValueFor "INFO line 7" $infomessage7;         infomessage7=$value;
newValueFor "INFO line 8" $infomessage8;         infomessage8=$value;

echo "--------------------------------------------------------------------------------"
echo
echo "The Connect-Text is sent to a station that connects to the node."
echo "keep it short and sweet.  Town name, or neighborhood and town."
echo "Note: No double quotes, no single quotes, no colons, and no ampersands."
echo
newValueFor "Connect-Text" $ctext;               ctext=$value;

check_process "linbpq"
if [ $? -ge 1 ]; then
   echo "#####  ERROR!"
   echo "#####         BPQ node is running."
   echo "#####         ... it must have started since you entered config".
   noConfigWithNodeRunning;
fi


echo "--------------------------------------------------------------------------------"
echo "The next part enables and configures up to ten NinoTNC A3 and A4 neighbors."
echo "There is a separate place later in the process to describe generic USB"
echo "TNCs and NinoTNC A2 units.  There is room for 2 of these".

echo "The neighbor is described as a callsign with SSID (usually -2)"
echo "and a frame-acknowledge-delay, or FRACK.  The FRACK is the number"
echo "of milliseconds it takes for your NinoTNC to transmit a full length"
echo "packet message, PLUS two times how long it takes for your neighbor to"
echo "send you a full length packet message.  This time includes the TX-RX-TX"
echo "switchover times.  A too-short FRACK is devastating because perfectly"
echo "good packets will be tossed out some of the time.  A too long FRACK"
echo "wastes time but only if the link is already getting packet errors."
echo "Recommended starter values are 9000 for 1200 baud and 3000 for 9600 baud."
echo "1200 baud -> FRACK of 9000"
echo "2400 baud -> FRACK of 6000"
echo "4800 baud -> FRACK of 5000"
echo "9600 baud -> FRACK of 3000"
echo "Note that some of the data radios are very fast at switching and can"
echo "have a lower FRACK.  Alinco DR135 and relatives are very slow and will"
echo "have a higher FRACK.  You'll have to test your link with your neighbor"
echo "and see what you can get away with.  Watch the retry rate shown in"
echo "the R R response in QT-Term."
echo "Leave neighbor callsign as NOT_SET if you don't need to add another"
echo "The order of neighbors is unimportant.  The program will figure out"
echo "which NinoTNC each neighbor connects to.  The FRACK is associated"
echo "with the NinoTNC that the matching neighbor comes in on."
echo
echo "Neighbor callsign should be something like k1qrm-2"
echo

newValueFor "Callsign for a neighbor node 'A'" $neighborA;    neighborA=$value;
if [ $neighborA != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
   newValueFor "FRACK for first neighbor 'A'"       $frackA;        frackA=$value;
   newValueFor "Callsign for a neighbor node 'B'" $neighborB;    neighborB=$value;
   if [ $neighborB != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
   then
      newValueFor "FRACK for first neighbor 'B'"       $frackB;       frackB=$value;
      newValueFor "Callsign for a neighbor node 'C'" $neighborC;    neighborC=$value;
      if [ $neighborC != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
      then
         newValueFor "FRACK for first neighbor 'C'"       $frackC;       frackC=$value;
         newValueFor "Callsign for a neighbor node 'D'" $neighborD;    neighborD=$value;
         if [ $neighborD != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
         then
            newValueFor "FRACK for first neighbor 'D'"       $frackD;       frackD=$value;
            newValueFor "Callsign for a neighbor node 'E'" $neighborE;    neighborE=$value;
            if [ $neighborE != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
            then
               newValueFor "FRACK for first neighbor 'E'"       $frackE;       frackE=$value;
               newValueFor "Callsign for a neighbor node 'F'" $neighborF;    neighborF=$value;
               if [ $neighborF != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
               then
                  newValueFor "FRACK for first neighbor 'F'"       $frackF;       frackF=$value;
                  newValueFor "Callsign for a neighbor node 'G'" $neighborG;    neighborG=$value;
                  if [ $neighborG != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
                  then
                     newValueFor "FRACK for first neighbor 'G'"       $frackG;       frackG=$value;
                     newValueFor "Callsign for a neighbor node 'H'" $neighborH;    neighborH=$value;
                     if [ $neighborH != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
                     then
                        newValueFor "FRACK for first neighbor 'H'"       $frackH;       frackH=$value;
                        newValueFor "Callsign for a neighbor node 'I'" $neighborI;    neighborI=$value;
                        if [ $neighborI != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
                        then
                           newValueFor "FRACK for first neighbor 'I'"       $frackI;       frackI=$value;
                           newValueFor "Callsign for a neighbor node 'J'" $neighborJ;    neighborJ=$value;
                           if [ $neighborJ != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
                           then
                              newValueFor "FRACK for first neighbor 'J'"       $frackJ;       frackJ=$value;
                           else
                              frackJ=9000;
                           fi
                        else
                              frackI=9000;
                           neighborJ="NOT_SET";
                              frackJ=9000;
                        fi
                     else
                           frackH=9000;
                        neighborI="NOT_SET";
                           frackI=9000;
                        neighborJ="NOT_SET";
                           frackJ=9000;
                     fi
                  else
                        frackG=9000;
                     neighborH="NOT_SET";
                        frackH=9000;
                     neighborI="NOT_SET";
                        frackI=9000;
                     neighborJ="NOT_SET";
                        frackJ=9000;
                  fi
               else
                     frackF=9000;
                  neighborG="NOT_SET";
                     frackG=9000;
                  neighborH="NOT_SET";
                     frackH=9000;
                  neighborI="NOT_SET";
                     frackI=9000;
                  neighborJ="NOT_SET";
                     frackJ=9000;
               fi
            else
                  frackE=9000;
               neighborF="NOT_SET";
                  frackF=9000;
               neighborG="NOT_SET";
                  frackG=9000;
               neighborH="NOT_SET";
                  frackH=9000;
               neighborI="NOT_SET";
                  frackI=9000;
               neighborJ="NOT_SET";
                  frackJ=9000;
            fi
         else
               frackD=9000;
            neighborE="NOT_SET";
               frackE=9000;
            neighborF="NOT_SET";
               frackF=9000;
            neighborG="NOT_SET";
               frackG=9000;
            neighborH="NOT_SET";
               frackH=9000;
            neighborI="NOT_SET";
               frackI=9000;
            neighborJ="NOT_SET";
               frackJ=9000;
         fi
      else
            frackC=9000;
         neighborD="NOT_SET";
            frackD=9000;
         neighborE="NOT_SET";
            frackE=9000;
         neighborF="NOT_SET";
            frackF=9000;
         neighborG="NOT_SET";
            frackG=9000;
         neighborH="NOT_SET";
            frackH=9000;
         neighborI="NOT_SET";
            frackI=9000;
         neighborJ="NOT_SET";
            frackJ=9000;
      fi
   else
         frackB=9000;
      neighborC="NOT_SET";
         frackC=9000;
      neighborD="NOT_SET";
         frackD=9000;
      neighborE="NOT_SET";
         frackE=9000;
      neighborF="NOT_SET";
         frackF=9000;
      neighborG="NOT_SET";
         frackG=9000;
      neighborH="NOT_SET";
         frackH=9000;
      neighborI="NOT_SET";
         frackI=9000;
      neighborJ="NOT_SET";
         frackJ=9000;
   fi
else
      frackA=9000;
   neighborB="NOT_SET";
      frackB=9000;
   neighborC="NOT_SET";
      frackC=9000;
   neighborD="NOT_SET";
      frackD=9000;
   neighborE="NOT_SET";
      frackE=9000;
   neighborF="NOT_SET";
      frackF=9000;
   neighborG="NOT_SET";
      frackG=9000;
   neighborH="NOT_SET";
      frackH=9000;
   neighborI="NOT_SET";
      frackI=9000;
   neighborJ="NOT_SET";
      frackJ=9000;
fi

echo
echo "Now configure the USB-serial KISS devices."
echo "DO NOT USE these for NinoTNC A3 and A4 TNCs."
echo "The newer NinoTNCs are handled by the Neighbor mechanism."
echo
echo "These USB TNC Port specifications have TxDelay parameters which"
echo "are passed to G8BPQ.  If your KISS device understands the"
echo "TXDELAY KISS value, it will be configured from this TXDELAY value."
echo
echo "Serial Baud value is used between the USB adapter and the TNC's CPU."
echo "The over-the-air TNC baud bit-rate must be set by the TNC itself."
echo
echo "Ports 11 and 12 are USB ports but are highly customizable in support of"
echo "non-traditional TNCs but may be used for older NinoTNCs."
echo
echo "The default values are appropriate for a NinoTNC.  NinoTNCs ignore"
echo "the TxDelay value, and require 57600 baud."
echo
getBlockEnable "USB TNC port 11  - user specified /dev port " $usb_port11;
if [ $_block_enabled -eq 1 ];
then
  usb_port11="ENABLE"
  echo "Provide a FULLY QUALIFIED DIRECTORY PATH for Port 11."
  echo "An example is /dev/ttyUSB0 and that is probably what you want."
  newValueFor "Device path for port 11 -- default is /dev/ttyUSB0" $portdev11;  portdev11=$value;
  newValueFor "Serial baud rate for TNC on port 11" $speed11;                   speed11=$value;
  newValueFor "TxDelay to be used by USB KISS TNC on port 11" $txdelay11;       txdelay11=$value;
  newValueFor "Frame Acknowledge Max-time in milliseconds" $frack11;               frack11=$value;
  newValueFor "Send KISS OPTIONS, enable or disable. Usually enable." $kissoptions11;            kissoptions11=$value;
  newValueFor "Callsign for neighbor node faced by port 11" $neighbor11;        neighbor11=$value;
  echo
else
  usb_port11="DISABLE"
fi
if [ $kissoptions11 == "disable" ];  #"disable" and "enable" are the only options available
then
   echo " "
else
   if [ $kissoptions11 == "enable" ];  #"disable" and "enable" are the only options available
   then
      echo " "
   else
      echo "ERROR - kissoptions11 had a bad value.  I will set to enable."
      kissoptions11="enable"
   fi
fi



getBlockEnable "USB TNC port 12 -- user specified /dev port " $usb_port12;
if [ $_block_enabled -eq 1 ];
then
  usb_port12="ENABLE"
  echo "Provide a FULLY QUALIFIED DIRECTORY PATH for Port 12."
  echo "An example is /dev/ttyUSB1 and that is probably what you want."
  newValueFor "Device path for port 12 -- default is /dev/ttyUSB1" $portdev12;     portdev12=$value;
  newValueFor "Serial baud rate for TNC on port 12" $speed12;                      speed12=$value;
  newValueFor "TxDelay to be used by USB KISS TNC on port 12" $txdelay12;          txdelay12=$value;
  newValueFor "Frame Acknowledge Max-time in milliseconds" $frack12;               frack12=$value;
  newValueFor "Send KISS OPTIONS, enable or disable. Usually enable." $kissoptions12;            kissoptions12=$value;
  newValueFor "Callsign for neighbor node faced by port 12" $neighbor12;           neighbor12=$value;
  echo
else
  usb_port12="DISABLE"
fi
if [ $kissoptions12 == "disable" ];  #"disable" and "enable" are the only options available
then
   echo " "
else
   if [ $kissoptions12 == "enable" ];  #"disable" and "enable" are the only options available
   then
      echo " "
   else
      echo "ERROR - kissoptions12 had a bad value.  I will set to enable."
      kissoptions12="enable"
   fi
fi



neighbortemp=${neighborA^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
   neighborA=$neighbortemp;
fi

neighbortemp=${neighborB^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborB=$neighbortemp;
fi

neighbortemp=${neighborC^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborC=$neighbortemp;
fi

neighbortemp=${neighborD^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborD=$neighbortemp;
fi

neighbortemp=${neighborE^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborE=$neighbortemp;
fi

neighbortemp=${neighborF^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborF=$neighbortemp;
fi

neighbortemp=${neighborG^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborG=$neighbortemp;
fi

neighbortemp=${neighborH^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighborH=$neighbortemp;
fi

neighbortemp=${neighbor09^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighbor09=$neighbortemp;
fi

neighbortemp=${neighbor10^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighbor10=$neighbortemp;
fi

neighbortemp=${neighbor11^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighbor11=$neighbortemp;
fi

neighbortemp=${neighbor12^^};
if [ neighbortemp != "NOT_SET" ];  ### Only write the uppercase neighbor callsign if it has been configured
then
  neighbor12=$neighbortemp;
fi


####################################### CHAT CONFIGURATION ############################3
echo "manual_chat_config:"$manual_chat_config          >> $NODEINI_INPROG
if [ $manual_chat_config == "YES" ];
then
  chatNeighborA=neighborA | cut -d- =f1;
fi


rm -f $NODEINI_INPROG
check_process "linbpq"
if [ $? -ge 1 ]; then
   echo "#####  ERROR!"
   echo "#####         BPQ node is running."
   echo "#####         ... it must have started since you entered config".
   noConfigWithNodeRunning;
fi

echo "-------------------------------------------------------------------"
echo "#### Done.  Now to overwrite the node.ini file with the new configuration."
sleep 1

###### Copy the internal variables to the node.ini file.

echo "manual_chat_config:"$manual_chat_config          >> $NODEINI_INPROG

_lowerCaseNodeCall=${chat_cA,,}
echo "chat_cA:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cB,,}
echo "chat_cB:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cC,,}
echo "chat_cC:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cD,,}
echo "chat_cD:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cE,,}
echo "chat_cE:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cF,,}
echo "chat_cF:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cG,,}
echo "chat_cG:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cH,,}
echo "chat_cH:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cI,,}
echo "chat_cI:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_cJ,,}
echo "chat_cJ:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_c11,,}
echo "chat_c11:"$_lowerCaseNodeCall          >> $NODEINI_INPROG
_lowerCaseNodeCall=${chat_c12,,}
echo "chat_c12:"$_lowerCaseNodeCall          >> $NODEINI_INPROG

_lowerCaseNodeCall=${nodecall,,}
echo "nodecall:"$_lowerCaseNodeCall          >> $NODEINI_INPROG

_lowerCaseNodeName=${nodename,,}
echo "nodename:"$_lowerCaseNodeName         >> $NODEINI_INPROG

_lowerCaseBbsCall=${bbscall,,}
echo "bbscall:"$_lowerCaseBbsCall           >> $NODEINI_INPROG

_lowerCaseChatCall=${chatcall,,}
echo "chatcall:"$_lowerCaseChatCall        >> $NODEINI_INPROG

echo "latlon:"$latlon >> $NODEINI_INPROG
echo "infomessage1:"$infomessage1           >> $NODEINI_INPROG
echo "infomessage2:"$infomessage2           >> $NODEINI_INPROG
echo "infomessage3:"$infomessage3           >> $NODEINI_INPROG
echo "infomessage4:"$infomessage4           >> $NODEINI_INPROG
echo "infomessage5:"$infomessage5           >> $NODEINI_INPROG
echo "infomessage6:"$infomessage6           >> $NODEINI_INPROG
echo "infomessage7:"$infomessage7           >> $NODEINI_INPROG
echo "infomessage8:"$infomessage8           >> $NODEINI_INPROG
echo "ctext:"$ctext                         >> $NODEINI_INPROG

_lowerCaseOpCallsign=${local_op_callsign,,}
echo "local-op-callsign:"$_lowerCaseOpCallsign >> $NODEINI_INPROG

echo "sysop-password:"$sysop_password        >> $NODEINI_INPROG
echo >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborA^^}
echo "neighborA:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackA:"$frackA                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborB^^}
echo "neighborB:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackB:"$frackB                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborC^^}
echo "neighborC:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackC:"$frackC                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborD^^}
echo "neighborD:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackD:"$frackD                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborE^^}
echo "neighborE:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackE:"$frackE                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborF^^}
echo "neighborF:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackF:"$frackF                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborG^^}
echo "neighborG:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackG:"$frackG                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborH^^}
echo "neighborH:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackH:"$frackH                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborI^^}
echo "neighborI:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackI:"$frackI                 >> $NODEINI_INPROG
_upperCaseNeighbor=${neighborJ^^}
echo "neighborJ:"$_upperCaseNeighbor      >> $NODEINI_INPROG
echo    "frackJ:"$frackJ                 >> $NODEINI_INPROG

echo >> $NODEINI_INPROG
echo "usb-port11:"$usb_port11                >> $NODEINI_INPROG
echo "portdev11:"$portdev11                  >> $NODEINI_INPROG
echo "speed11:"$speed11                      >> $NODEINI_INPROG
echo "txdelay11:"$txdelay11                  >> $NODEINI_INPROG
echo "frack11:"$frack11                      >> $NODEINI_INPROG
echo "kissoptions11:"$kissoptions11          >> $NODEINI_INPROG
_upperCaseNeighbor11=${neighbor11^^}
echo "neighbor11:"$_upperCaseNeighbor11      >> $NODEINI_INPROG
echo >> $NODEINI_INPROG
echo "usb-port12:"$usb_port12                >> $NODEINI_INPROG
echo "portdev12:"$portdev12                  >> $NODEINI_INPROG
echo "speed12:"$speed12                      >> $NODEINI_INPROG
echo "txdelay12:"$txdelay12                  >> $NODEINI_INPROG
echo "frack12:"$frack12                      >> $NODEINI_INPROG
echo "kissoptions12:"$kissoptions12          >> $NODEINI_INPROG
_upperCaseNeighbor12=${neighbor12^^}
echo "neighbor12:"$_upperCaseNeighbor12      >> $NODEINI_INPROG
echo >> $NODEINI_INPROG
echo >> $NODEINI_INPROG
echo >> $NODEINI_INPROG
echo >> $NODEINI_INPROG

rm -f $NODEINI
mv $NODEINI_INPROG $NODEINI

#### Clean up
rm -f $NODEWORK
rm -f $TEMPFILE


echo
echo "Make sure you use tarpn test to test the node before making it auto.  The new"
echo "configuration will be used the next time G8BPQ is loaded. "
echo

echo -ne $(date) " " >> $TARPNCOMMANDLOGFILE
echo "CONFIGURE COMPLETED"  >> $TARPNCOMMANDLOGFILE


exit 0;



