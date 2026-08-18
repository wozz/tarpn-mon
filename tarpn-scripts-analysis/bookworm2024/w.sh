#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024
##### Leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

##### W --  This script file is downloaded by the human and run to start the
#####       TARPN install on a brand new Raspberry PI Linux installation.
#####       This script does a minor amount of environment checking, and then
#####       goes and gets the next script from the appropriate repository.


###### This is the Internet URL for the web repository where all the TARPN scripts live.
###### This address is particular to the script major version this TARPN node will be running.
###### This URL gets saved in a secure location on the Raspberry PI's filesystem and is used
###### later during run-time to fetch updates.
SOURCE_URL=https://tarpn.net/bookworm2024;


#### 2022-05-12  BULLSEYE 000--
#### 2023-01-08  BULLSEYE 002--   Fix an error message where it said tarpn_start1 instead of 'w'
#### 2023-07-01  BULLSEYE 003--   Add a check to make sure we're using a 32 bit OS
#### 2024-01-28  BOOKWORM 001--   Start working on Bookworm compatability
#### 2024-01-30  BOOKWORM 002--   Turn off 32 bit check
#### 2024-01-33  BOOKWORM 003--   Turn 32 bit check back on.  It turns out G8BPQ LINBPQ won't run on the 64bit OS, so far

echo "######"
echo "######"
echo "###### W (install starter) Version BOOKWORM 003"
echo "######"
echo "######"
echo "######"

uptime


########### Verify that the user-name is 'pi'.  If not, abort with an error message
if [ $(whoami) != "pi" ]; then
   echo "ERROR:  Hello user " $(whoami);
   echo "ERROR:  The TARPN start and a couple of the run-time and command scripts "
   echo "ERROR:  will fail if the user name is not 'pi'.  Please use Raspberry PI Imager"
   echo "ERROR:  to set up 'pi' as the user name, and automatically log in to desktop."
   echo "ERROR:   Aborting now."
   exit 1
fi





######## CHECK TO MAKE SURE WE'RE REALLY RUNNING THE SCRIPT THIS CODE WAS WRITTEN FOR
######## AND ALSO THAT WE'RE BEING RUN IN THE DIRECTORY WHERE THE SCRIPT WAS DOWNLOADED TO.
cd /home/pi
if [ -f w ];
then
   echo
else
   echo "ERROR:  Help.  I don't know where I am.  Is this w?  "
   echo "ERROR:  Please start from the /home/pi directory.  Aborting"
   exit 1;
fi

if [  -d /usr/tarpn ];then
    echo "ERROR  This script can only be run on a brand-new OS installation"
    exit 1
fi


####### Verify that we are on a 32-bit OS
###usr/bin/ls: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, BuildID[sha1]=81004d065160807541b79235b23eea0e00a2d44e, for GNU/Linux 3.2.0, stripped
var=$(file /usr/bin/ls | grep 32-bit | wc -l)
good=1
if [ $var -ne $good ]; then
   echo "##### ERROR 1.1   32-bit not found in OS description"
   echo "#####     The G8BPQ node executable, used by the TARPN installation, requires a 32-bit OS"
   echo "####  abort"
   exit 1
fi



rm -f tarpn*
wget $SOURCE_URL/tarpn_start1.sh
if [ -f tarpn_start1.sh ];
then
   echo "##### tarpn-start-1 downloaded successfully"
   chmod +x tarpn_start1.sh;
   uptime
   echo "##### Transfer control from W to TARPN START 1"
   ./tarpn_start1.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving tarpn_start1.sh  Something is wrong."
   echo -e "ERROR:  Check your Internet connection?  Dunno. If you can't figure it out,"
   echo -e "ERROR:  send an email to tarpn@groups.io with a copy of the last page or"
   echo -e "ERROR:  four of the execution of this script.  Thanks!"
   echo -e "ERROR:  Aborting\n\n\n\n\n"
   exit 1;
fi
exit 0


