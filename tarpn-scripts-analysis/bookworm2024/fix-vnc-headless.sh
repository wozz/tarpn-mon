#!/bin/bash

### fix-vnc-headless.sh

## There is a problem.  If the Raspberry PI Bullseye is put in command-line mode,
## and then back to Desktop mode, it may lose the headless behavior that is desired.
## This script writes a headless screen-resolution to [what we think is] the appropriate file.

## this is what it does:

## Add a line to the cmdline.txt file to define a default video resolution for headless operation.  This may be required for VNC operation.

## This script-file looks at the OS version and if bullseye or bookworm, it proceeds to check the cmdline.txt file.
## if the cmdline.txt file has a "video=" line, then we exit.
## if the cmdline.txt file does NOT have a "video=" line, then we add "video=HDMI-A-1:1280x720@60D" to a temp
##     copy of the cmdline.txt file, and finally we put the cmdline.txt file where it belongs.


###########    6-07-2025 vBullseye001 -- First version of fix-vnc-headless.sh
###########    2-05-2026 Bookworm002  -- Add a version line that  tarpn sysinfo can display.

             VERSIONSTRING="Bookworm002"
### =FIX-VNC-HEADLESS.SH       Bookworm002=   --VERSION--
echo "fix-vnc-headless.sh   $VERSIONSTRING"

## define the log files we're write to
START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"

echo -ne $(date) "" >> $START_STOP_LOGFILE
echo "FIX-VNC-HEADLESS $VERSIONSTRING: script-start"  >> $START_STOP_LOGFILE
echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
echo "FIX-VNC-HEADLESS $VERSIONSTRING: script-start -- see start-stop log file for details"  >> $TARPNCOMMANDLOGFILE


### delete some temp files we'll be using during this script

cd ~
sudo rm -f cmdline-temp1.txt
sudo rm -f cmdline-temp2.txt
TEMP_PARSING_FILE="/home/pi/temp.txt"
sudo rm -f $TEMP_PARSING_FILE

### Decide which Linux we're using and set the alias for cmd-line-file to match the path for the specific Linux version

cat /etc/*-release | grep "VERSION" | grep "11 (bullseye)" > $TEMP_PARSING_FILE
if grep -q "VERSION" $TEMP_PARSING_FILE;
then
    CMDLINE_FILE="/boot/cmdline.txt"
    echo -n "Linux ok: "
    cat $TEMP_PARSING_FILE
else
    sudo rm -f $TEMP_PARSING_FILE
    cat /etc/*-release | grep "VERSION" | grep "12 (bookworm)" > $TEMP_PARSING_FILE
    if grep -q "VERSION" $TEMP_PARSING_FILE;
    then
        CMDLINE_FILE="/boot/firmware/cmdline.txt"
        echo -n "Linux ok: "
        cat $TEMP_PARSING_FILE
    else
        echo "The Linux version is not one this script is prepared for.  Quitting the script."
        echo -ne $(date) "" >> $START_STOP_LOGFILE
        echo "FIX-VNC-HEADLESS: abort - wrong Linux"  >> $START_STOP_LOGFILE
        exit 1
   fi
fi
sudo rm -f $TEMP_PARSING_FILE

echo " "
echo " "

### Verify the presence of the cmd line file

if [ -f $CMDLINE_FILE ];
then
    echo "$CMDLINE_FILE file is present"
else
    echo "$CMDLINE_FILE not found.  exit"
    echo -ne $(date) "" >> $START_STOP_LOGFILE
    echo "FIX-VNC-HEADLESS: abort - cmdline file missing"  >> $START_STOP_LOGFILE
    exit 0;
fi
echo " "
echo " "



### Decide if the cmdline file already has the VIDEO line

if grep -q "video=" $CMDLINE_FILE;
then
    echo "$CMDLINE_FILE already has the 'video=' line. "
    echo "This is $CMDLINE_FILE:"
    echo "--------------"
    cat $CMDLINE_FILE
    echo "--------------"
    echo " "
    echo -ne $(date) "" >> $START_STOP_LOGFILE
    echo "FIX-VNC-HEADLESS: abort - video line already present"  >> $START_STOP_LOGFILE
    exit 0
else
    echo "$CMDLINE_FILE does not have the 'video=' line."
    echo "This is $CMDLINE_FILE:"
    echo "--------------"
    cat $CMDLINE_FILE
    echo "--------------"
    echo " "
fi
echo " "
echo " "



### Add the VIDEO line

# Add line feed to existing content and append new line
echo -e "$(cat "$CMDLINE_FILE")\nvideo=HDMI-A-1:1280x720@60D" > cmdline-temp2.txt

echo "I have modified the cmdline file in the home directory."
echo "This is the new contents:"
echo "--------------"
cat cmdline-temp2.txt
echo "--------------"


### Set the permissions for the new cmdline file

sudo chgrp root cmdline-temp2.txt
sudo chown root cmdline-temp2.txt

echo " "
echo " "

echo "putting the modified cmdline file back at $CMDLINE_FILE"

echo " "
echo " "


### Put the modified cmdline file back where it belongs

sudo mv cmdline-temp2.txt $CMDLINE_FILE

echo "cmdline file has been updated. This is the directory entry for the file:"
echo
ls -lrats $CMDLINE_FILE

sudo rm -f cmdline-temp1.txt
sudo rm -f cmdline-temp2.txt
sudo rm -f $TEMP_PARSING_FILE

echo -ne $(date) "" >> $START_STOP_LOGFILE
echo "FIX-VNC-HEADLESS: complete - CMDLINE.TXT file was modified"  >> $START_STOP_LOGFILE

echo
echo


exit 0
