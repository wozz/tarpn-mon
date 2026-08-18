#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2025.  All rights reserved.



startget() {
if [ -f $1 ];
then
   echo $1 "already exists -- deleting it"
   rm $1
fi

wget -o /dev/null $SOURCE_URL/$1
if [ -f $1 ];
then
   echo $1 "ok"
else
   wget -o /dev/null $SOURCE_URL/$1
   if [ -f $1 ];
   then
      echo $1 "downlaoded on 2nd try by startget"
   else
      wget -o /dev/null $SOURCE_URL/$1
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


###### This is the Internet URL for the web repository where all the TARPN scripts live.
###### This address is particular to the script major version this TARPN node will be running.
###### This URL gets saved in a secure location on the Raspberry PI's filesystem and is used
###### later during run-time to fetch updates.
SOURCE_URL="https://tarpn.net/bookworm2024";


##### Please leave the copyright notice and this message in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

##### TARPN START 1 --  This script file is downloaded by the W-script and run automatically to start the
#####                   TARPN install on a brand new Raspberry PI Linux installation.
#####                   This script checks the environment and if everything is good
#####                   it will download the next script, which is large, TARPN START 1dL


#### 2015-02-24  029  Add support for processor Revision a21041  for Raspberry PI 2 B.   Point URL to /feb directory on server.
#### 2015-04-15  030  Add support for a01041 Raspberry PI 2 B v1.1
#### 2015-06-33  031   -- add support for 0013 Raspberry PI B+
#### 2015-10-14  JESSIE 001   -- change the source URL from http://www.torborg.com/feb to http://tarpn.net/2015oct
#### 2015-10-15  JESSIE 002   -- fix debug message when testing Linux version.
#### 2015-10-18  JESSIE 003   -- set the source URL at the top of the file, save it to filesystem, then read it back.
#### 2016-01-10  JESSIE 004   -- add Raspberry PI ZERO support
#### 2016-03-04  JESSIE 005   -- add Raspberry PI 3 B support
#### 2016-03-04  JESSIE 006   -- add Raspberry PI 0 B+ Chinese RED support
#### 2016-03-24  JESSIE 007   -- add support for yet another Raspberry PI 3 B  -- install IPUTILS-PING
#### 2017-08-22  STRETCH 001  -- change the source URL from http://tarpn.net/2015oct  to http://tarpn.net/2017aug
#### 2017-08-22  STRETCH 002  -- Add a verify feature to check for missing items needed for the script.
#### 2017-09-11  STRETCH 003  -- Add a couple of more Raspberry PI models.
#### 2017-10-03  STRETCH 004  -- remove verification of the web-page contents.  Save some time
#### 2018-07-08  STRETCH 005  -- improve error message if attempting install on a fully installed system
#### 2018-07-15  STRETCH 006  -- fix bug where a "fi" was left out -- caused by the error message addition in v005
#### 2018-07-21  STRETCH 007  -- Add support for Raspberry PI B+  _value12
#### 2019-05-26  BUSTER 001   -- change the name of the OS we're looking for.
#### 2019-07-01  BUSTER 002   -- change the source URL from http://tarpn.net/2017aug  to http://tarpn.net/2019jun
#### 2019-07-03  BUSTER 003   -- add new PI board:  _valueB="a03111"   #### Raspberry PI 4B 1GBram from PiHUT July 2019
#### 2019-07-12  BUSTER 004   -- add new PI board:  _value4B2="b03111"   #### Raspberry PI 4B 2GBram July 2019     a03111 is now _value4B1
#### 2020-01-25  BUSTER 005   -- add new PI board for PI 4B 4GB
#### 2020-01-26  BUSTER 006   -- fix missing $ in PI 4B 4GB support
#### 2020-02-06  BUSTER 007   -- fix incorrect error message
#### 2020-05-24  BUSTER 008   -- NinoTNC support URL is now apr2020  That's our "URL" now
#### 2020-05-27  BUSTER 009   -- Add support for Raspberry PI 4B v1.2
#### 2020-09-03  BUSTER 010   -- Echo the source URL before downloading tarpn_start1dl.sh
#### 2020-10-06  BUSTER 011   -- add support for a v1.4 Raspberry PI
#### 2021-02-11  BUSTER 012   -- URL is now nov2020test
#### 2021-07=3-  BUSTER 013   -- URL is now jun2021test
#### 2021-10-03  BUSTER 014   -- add a new version of Raspberry PI 2B  _value4BA="c03114"
#### 2021-10-18  BUSTER 015   -- URL is now oct2021
#### 2021-11-09  BULLSEYE 001-- URL is now bullseye2021
#### 2021-11-09  BULLSEYE 002-- I forgot about the "SOURCE_URL" setting in this file
#### 2021-11-13  BULLSEYE 003-- fix trailing null in source-url
#### 2022-01-25  BULLSEYE 004-- fix error in checking for PI 4B rev 1.4
#### 2022-02-05  BULLSEYE 005-- improve some dialog messages
#### 2022-03-05  BULLSEYE 006-- add new version of PI 4B rev 1.5
#### 2022-03-27  BULLSEYE 007-- add new version of PI 4B rev 1.5    a03115
#### 2022-04-18  BULLSEYE 008-- Check and insist that the log in name is 'pi'.
#### 2022-04-18  BULLSEYE 009-- Check and insist on having sudo access.
#### 2022-04-18  BULLSEYE 010-- bug fix in sudo test code
#### 2022-04-20  BULLSEYE 011-- "d03114"   #### Raspberry Pi 4 Model B Rev 1.5 2GB
#### 2022-04-20  BULLSEYE 012-- Move check for SUDOers to after checking for 1dl start
#### 2022-05-11  BULLSEYE 013-- Add PI 400 revcode="c03130"  from John Hysell on the TARPN group
#### 2022-05-12  BULLSEYE 014-- Add PI Zero 2W 512K from John Hysell on the TARPN groups.io
#### 2022-11-30  BULLSEYE 015-- Add Raspberry PI 3B made at "Stadium" "a52052"
#### 2022-12-01  BULLSEYE 016-- Error..   Raspberry PI 3B made at "Stadium" should be "a52082"
#### 2023-05-05  BULLSEYE 017-- bypass known-hardware and specific OS test if there is a file /usr-local/etc/bypass-platform-checks.txt
#### 2023-05-05  BULLSEYE 018-- Use https in the source url
#### 2023-05-06  BULLSEYE 019-- use tarpnget and tarpnget_path_and_filename - create startget() and use it before we download tarpnget.sh
#### 2023-05-19  BULLSEYE 020-- add support for "c03115"   #### Raspberry Pi 4 Model B Rev 1.5 4GB    Keith Nolan  Jun 19, 2023
#### 2023-05-25  BULLSEYE 021-- add support for "d03115"   #### Raspberry Pi 4 Model B Rev 1.5 8GB    Larry K4BLX,
#### 2023-05-25  BULLSEYE 022-- add support for Raspberry PI 3A+  -- Tadd
#### 2024-01-28  BOOKWORM 001 - start modding bullseye scripts for Bookworm
#### 2024-02-03  BOOKWORM 002 - Remove a redundant copy of d03114 Raspberry PI number.
#### 2024-02-15  BOOKWORM 003 - _value5B4g="c04170"  #### Raspberry PI 5 Model B 4GB
#### 2024-02-15  BOOKWORM 004 - work on platform recognition
#### 2025-02-17  BOOKWORM 005 - fix bug in sudoers test where it was assuming /usr/tarpn already existed.  Must use /usr/local.
#### 2025-05-09  BOOKWORM 006 - Erase sudoers test result after passing.
#### 2025-12-18  BOOKWORM 007 - add in PI 3B+ 120d4 new in 2025

echo "######"
echo "######"
echo "###### tarpn start 1 Version BOOKWORM 007"
echo "######"
echo "######"
echo "######"

temp_parsing_file="/home/pi/temp_for_tarpn_start.txt";
uptime


########### Verify that the user-name is 'pi'.  If not, abort with an error message
if [ $(whoami) != "pi" ]; then
   echo "ERROR:  Hello user " $(whoami);
   echo "ERROR:  The TARPN start, and a couple of the run-time and command scripts,"
   echo "ERROR:  will fail if the user name is not 'pi'.  Please use Raspberry PI Imager"
   echo "ERROR:  to set up 'pi' as the user name, and automatically log in to desktop."
   echo "ERROR:   Aborting now."
   exit 1
fi





######## CHECK TO MAKE SURE WE'RE REALLY RUNNING THE SCRIPT THIS CODE WAS WRITTEN FOR
######## AND ALSO THAT WE'RE BEING RUN IN THE DIRECTORY WHERE THE SCRIPT WAS DOWNLOADED TO.
cd /home/pi
if [ -f tarpn_start1.sh ];
then
   echo
else
   echo "ERROR:  Help.  I don't know where I am.  Is this tarpn_start1.sh?  "
   echo "ERROR:  Please start from the /home/pi directory.  Aborting"
   exit 1;
fi

################################################################
################################################################
#### Check if we have SUDO access

uptime > /home/pi/sudoerstest.txt
date >> /home/pi/sudoerstest.txt
sudo mv /home/pi/sudoerstest.txt /usr/local/etc
### This is using usr local etc because usr tarpn etc does not exist yet.
if [ -f /usr/local/etc/sudoerstest.txt ];
then
    ## we do have sudo access.  ok.  delete the test file.
    sudo rm -rf /usr/local/etc/sudoerstest.txt
else
    echo "ERROR:  The user named 'pi' is supposed to have sudo access by default. "
    echo "ERROR:  The script's test for access has returned a failure."
    echo "ERROR:  Please use Raspberry PI Imager to re-image the SDcard."
    echo "ERROR:  Make sure to set up 'pi' as the user name in the PI startup prompts."
    echo "ERROR:"
    echo "ERROR:  If this error is unexpected, please send a note"
    echo "ERROR:  to tarpn@groups.io and include this error message"
    echo "ERROR:  as well as the following block of data:"
    echo "ERROR:  LS of etc"
    ls -lrats /usr/local/etc
    echo "ERROR:  LS of PI"
    ls -lrats
    echo "ERROR:   Aborting now."
    exit 1
fi









if [  -d /usr/tarpn ];then
    echo "ERROR  This script can only be run on a brand-new OS installation"
    exit 1
fi

cd /usr
sudo mkdir tarpn
cd tarpn
sudo mkdir etc
sudo mkdir sbin
cd ~

################# Determine if this Raspberry PI is a supported version

echo "##### Start platform check #####"

sudo rm -f $temp_parsing_file;
cat /proc/cpuinfo | grep Revision > $temp_parsing_file
_counta=$( cat $temp_parsing_file );
_countb=${_counta:11}
echo "_countb=" $_countb

_value0="000d"     #### Red B+ Chinese
_value1="000e"
_value2="000f"
_value3="0010"
_value4="a21041"   ### Raspberry PI 2 B
_value5="a01041"   ### also Raspberry PI 2 B ??  v1.1
_value6="0013"     ### Raspberry PI B + v2
_value7="900092"   #### Raspberry PI Zero
_value8="a02082"   #### Raspberry PI 3 B

_value9="a22082"   #### Bob's Raspberry PI 3 B
_valueA="a22032"  #### Dylan's Raspberry PI 2B
_value10="a22042"  #### 2 Model B (with BCM2837)
_value11="a32082"   #### 3 Model B  Sony Japan
_value12="a020d3"   #### 3 Model B+ England 3-19-2018
_value120d4="a020d4"  #### 3 Model B+ new in 2025?
_valuea52082="a52082" #### Model 3B Stadium
_value4B1="a03111"   #### Raspberry PI 4B 1GB from PiHUT July 2019
_value4B2="b03111"   #### Raspberry PI 4B 2GB July 2019
_value4B4="c03111"   #### Raspberry PI 4B 4GB July 2019
_value4B5="a03112"   #### Raspberry Pi 4 Model B Rev 1.2 1GB
_value4B6="b03112"   #### Raspberry Pi 4 Model B Rev 1.2 2GB
_value4B7="c03112"   #### Raspberry Pi 4 Model B Rev 1.2 4GB
_value4B8="d03114"   #### Raspberry Pi 4 Model B Rev 1.4 8GB
_value4B9="b03114"   #### Raspberry Pi 4 Model B Rev 1.4 2GB
_value4BA="c03114"   #### Raspberry Pi 4 Model B Rev 1.4 2GB    hmm... this one came from K7EK on Oct2, 2021
_value4BB="b03115"   #### Raspberry Pi 4 Model B Rev 1.5 2GB
_value4BC="a03115"   #### Raspberry Pi 4 Model B Rev 1.5 1GB
_value400A="c03130"   #### PI 400 Rev 1.0 with ARM v7 rev 3 processor 4GB from John Hysell on the TARPN group
_valueZ2W="902120"    #### Raspberry Pi Zero 2W v1.0 512MB  Sony UK
_value4BE="c03115"   #### Raspberry Pi 4 Model B Rev 1.5 4GB    Keith Nolan  Jun 19, 2023
_value4BF="d03115"   #### Raspberry Pi 4 Model B Rev 1.5 8GB    Larry K4BLX
_value3APLUS1="9020e0"  #### Raspberry PI 3A+   Tadd June 25, 2023
_value5B4g="c04170"  #### Raspberry PI 5 Model B 4GB
echo "_value5B4g = "_value5B4g
_version_ok=0
if [ $_value5B4g == $_countb ]; then
   echo "_value5B4g did = _countb";
    _version_ok=1
   fi
if [ $_value3APLUS1 == $_countb ]; then
    _version_ok=1
   fi
if [ $_valueZ2W == $_countb ]; then
    _version_ok=1
   fi
if [ $_valuea52082 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value400A == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4BE == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4BF == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4BC == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4BB == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4BA == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B9 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B8 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B5 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B6 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B7 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B1 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B2 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value4B4 == $_countb ]; then
    _version_ok=1
   fi

if [ $_value0 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value1 == $_countb ]; then
    _version_ok=1
   fi
if [ $_value2 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value3 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value4 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value5 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value6 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value8 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value9 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value10 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value11 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value12 == $_countb ]; then
    _version_ok=1
        fi
if [ $_value120d4 == $_countb ]; then
    _version_ok=1
        fi



if [ -f /usr/tarpn/etc/bypass-platform-checks.txt ];
then
   echo "Platform checks are bypassed"
   _version_ok=1
fi



_good_result=1
if [ $_version_ok -ne $_good_result ]; then
    echo "----------------------------------------------"
        echo "PROC CPUINFO:"
    cat /proc/cpuinfo
    echo "----------------------------------------------"
    sleep 1
    echo "You have an unexpected version of Raspberry PI."
    echo "TARPN is not supported on this version, so far."
    echo "Please contact me, KA2DEW --see QRZ for email addr--,"
    echo "and send me the contents of your"
    echo "/proc/cpuinfo  file printed above."
    echo
    echo
    exit 0
fi

################ CHECK Operating system Version

if [ -f /usr/tarpn/etc/bypass-platform-checks.txt ];
then
   echo "OS Version check is bypassed"
else
   sudo rm -f $temp_parsing_file
   cat /etc/*-release | grep "VERSION" | grep "12 (bookworm)" > $temp_parsing_file
   if grep -q "VERSION" $temp_parsing_file;
   then
      echo -n "Linux ok: "
      cat $temp_parsing_file
   else
      echo -e "\n\nERROR!  This script does not support the Linux version reported in /etc"
      echo -e "ERROR!  Quitting now\n\n"
      sleep 1
      cat /etc/*-release
      rm -f $temp_parsing_file
      exit 1
   fi
fi
rm -f $temp_parsing_file

echo -e "Your Raspberry PI is running the expected Linux version\n\n\n\n"

###############################################################
#### See if we have already started installing on this box
if [ -f /usr/tarpn/etc/tarpn_start1dl.flag ];
then
    if [ -f /usr/tarpn/etc/tarpn_start2.flag ];
    then
        echo "##### Error XX55KK"
        echo "#####  Incomplete installation.  Please start installation again by"
        echo "#####  using a freshly formatted SDCARD using the Raspberry PI utility."
        echo "#####  Please see the:"
        echo "#####  ==Set Up raspberry PI to be a TARPN Node--Make SDCARD=="
        echo "#####  instructions on the builders page of tarpn.net."
        echo "#####  If this has already failed, please send an email"
        echo "#####  to the TARPN groups.io.  It is likely that either the"
        echo "#####  script author made a mistake, or the software involved"
        echo "#####  has changed in some way to make the scripts fail.  Thanks."
        echo " "
        echo "          Ending install now!"
        echo " "
        exit 1
    else
        echo "ERROR!"
        sleep 1
        echo "ERROR!"
        sleep 1
        echo "ERROR!"
        sleep 1
        echo "ERROR!"
        sleep 1
        echo "##### Error XX55CC"
        echo "#####  Incomplete installation.  Please start installation again by"
        echo "#####  using a freshly formatted SDCARD using the Raspberry PI utility."
        echo "#####  Please see the:"
        echo "#####  ==Set Up raspberry PI to be a TARPN Node--Make SDCARD=="
        echo "#####  instructions on the builders page of tarpn.net."
        echo "#####  If this has already failed, please send an email"
        echo "#####  to the TARPN groups.io.  It is likely that either the"
        echo "#####  script author made a mistake, or the software involved"
        echo "#####  has changed in some way to make the scripts fail.  Thanks."
        sleep 1
        echo "ERROR!"
        sleep 1
        echo "ERROR!"
        sleep 1
        echo "ERROR!"
        exit 1;
     fi
fi


################################################################
##### Save the SOURCE_URL by writing the data set at the top
##### of this script to the designated delete protected file-system location
_success=0


rm -f /home/pi/source_url.txt
echo $SOURCE_URL > /home/pi/source_url.txt
sudo mv /home/pi/source_url.txt /usr/tarpn/etc/source_url.txt

#### Read back the source URL from the filesystem into a local variable
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);




echo "###### Install IPUTILS-PING if it is not already here"
sudo apt-get install --reinstall iputils-ping

#############################################################################################################################################
### Check to see if the source-URL has some necessary items

###verify tarpn_start2.sh
###verify runbpq.sh
###verify configure_node_ini.sh
###verify tarpn
###verify piminicom.zip
###verify minicom.scr
###verify params.zip
###verify linbpq_6_0_10_16_April_2015.zip
###verify piTermTCP.zip
###verify ringnoises.zip
###verify nc4fg_home1_1.zip
###verify home_background.sh
###verify home.service
###verify home_background.sh
###verify home.service
### verify home.sh

#############################################################################################################################################

echo "###### Proceeding with installation"
echo

echo -ne "using a source URL of: "
echo $_source_url
echo


echo "###### Download TARPNGET"
startget tarpnget.sh
if [ -f tarpnget.sh ];
then
   echo "##### tarpnget downloaded successfully"
   chmod +x tarpnget.sh;
   sudo mv tarpnget.sh /usr/tarpn/sbin/tarpnget.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving tarpnget.  Something is wrong"
   echo -e "ERROR: Aborting\n\n\n\n\n"
   exit 1;
fi

echo
echo "###### Download SLEEP-WITH-COUNT"
startget sleep_with_count.sh
if [ -f sleep_with_count.sh ];
then
   echo "##### tarpnget downloaded successfully"
   chmod +x sleep_with_count.sh;
   sudo mv sleep_with_count.sh /usr/tarpn/sbin/sleep_with_count.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving sleep_with_count.  Something is wrong"
   echo -e "ERROR: Aborting\n\n\n\n\n"
   exit 1;
fi

echo "###### Download TARPN INSTALL 1dL"
sleep 1
echo



rm -f tarpn_start1dl.sh
startget tarpn_start1dl.sh
if [ -f tarpn_start1dl.sh ];
then
   echo "##### script 1dL downloaded successfully"
   chmod +x tarpn_start1dl.sh;
   echo "##### Transfer control from TARPN START 1 to TARPN START 1dL"
   ./tarpn_start1dl.sh
else
   echo -e "\n\n\n\n\nERROR:  Failure retrieving script1dl.  Something is wrong"
   echo -e "ERROR: Aborting\n\n\n\n\n"
   exit 1;
fi
exit 0

