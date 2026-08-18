#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014, 2015, 2016. 2017, 2018, 2019, 2020, 2021
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}

update_tarpn_home()
{


HOME_LOGFILE="/var/log/tarpn_home.log"

########## V001 -- 2017-02-13 Create from updateapps.sh.
########## V002 -- 2017-02-14 Minor pretty printing updates.
########## V006 -- 2019-01-10 update for version 2.0
########## V007 -- 2019-02-17 improvements to stop procedure.
########## V008 -- 2019-02-17 add echo output to show if stop procedure did not work smoothly.
########## V009 -- 2019-02-18 stop deleting the home ini file.  Only delete delete-me file early if it exists, then wait 10seconds.
########## V010 -- 2021-06-08 change the name from nc4fg.sh to tarpn-home-update.sh    use go.flag instead of delete-me
########## V011 -- 2021-06-08 bug fixing
########## V012 -- 2021-06-08 TARPN_Home_Latest
########## V013 -- 2021-06-19 improve logging and make progress prints more accurate.
########## V014 -- 2021-06-19 make this update function into a function called after this module is "sourced"
########## V015 -- 2021-06-21 Fix a couple of text mistakes
########## V016 -- 2021-06-30 Use test_internet.sh to verify Internet access instead of doing it locally
########## Vbullseye001 -- 2021-11-13 Fix trailing null in source-url
########## Vbullseye002 -- 2023-08-28 use https://tarpn.net  when pulling down the latest tarpn home zip
########## Vbookworm001 -- 2024-02-15 Use tarpnget-path-and-filename and grab tarpn home latest from tarpn.net/f/bookworm
########## Vbookworm002 -- 2024-02-15 fix bug where a cd was done twice because of my cut and past from the tarpn-install.
########## Vbookworm003 -- 2024-07-26 fix bug tarpnget.sh was not sourced before using it to fetch tarpn home..
########## Bookworm004 -- 2026-02-04 Mod the version string to match the other scripts


echo -ne $(date) "" >> $HOME_LOGFILE
echo "#####  tarpn-home-update.sh      Bookworm004"   >> $HOME_LOGFILE
echo "##### =TARPN-HOME-UPDATE.SH      Bookworm004="; #  --VERSION--#########

echo -ne $(date) "" >> $HOME_LOGFILE
echo " tarpn-home-update.sh started" >> $HOME_LOGFILE

if [ -d /tmp/tarpn ]; then                                        ### stop a TARPN-HOME v2.10 or later
   echo -n ""
else
   echo "/tmp/tarpn does not seem to exist"
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo "FAIL tarpn-home-update can't access /tmp/tarpn" >> $HOME_LOGFILE
   exit 1
fi

source test_internet.sh
getTestFile
if [ $? -lt 1 ];       ## if no errors, move on
then
   echo "We have access to the TARPN repository"
else
   echo "TARPN-HOME-UPDATE FAIL.  No Internet access??"
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo " tarpn-home-update.sh failed to read files from Internet - QUIT" >> $HOME_LOGFILE
    exit 1;
fi

### Establish a source URL for acquiring updated materials
cd ~
if [ -f /usr/tarpn/etc/source_url.txt ];
then
    echo -n;
else
   echo "ERROR0: source URL file not found."

   echo "ERROR0:"
   echo "ERROR0: Aborting"
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-home-update.sh failed  -- no source URL file -- quitting" >> $HOME_LOGFILE
   exit 1
fi
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);

echo -e "\n\n\n"
cd /home/pi
sudo rm -rf temporary_home_web_app
mkdir temporary_home_web_app
cd temporary_home_web_app
source tarpnget.sh
tarpnget_path_and_filename https://tarpn.net/f/bookworm TARPN_Home_Latest.zip
if [ -f /home/pi/temporary_home_web_app/TARPN_Home_Latest.zip ];
then
   echo "TARPN-HOME has been downloaded"
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-home-update.sh  -- latest tarpn-home downloaded" >> $HOME_LOGFILE
else
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-home-update.sh  -- FAIL -- unable to download latest!" >> $HOME_LOGFILE
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
    echo "UNZIP succeeded.  Going ahead with deletion of previous version"
else
    echo "##### ERROR: UNZIP failed.  Leaving old copy installed. ."
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo " tarpn-home-update.sh  -- FAIL -- UNZIP error!" >> $HOME_LOGFILE
    exit 1;
fi

echo "##### Instruct TARPN HOME service to stop launching Home"
echo -ne $(date) "" >> $HOME_LOGFILE
echo " tarpn-home-update.sh  -- download and unzip OK.  Stopping HOME service and HOME app!" >> $HOME_LOGFILE

if grep -q "BACKGROUND:ON" /usr/tarpn/etc/home.ini; then
   echo "##### HOME is set to run in the background.  Turning off..."
   sudo sed -i "s=BACKGROUND:ON=BACKGROUND:OFF=" /usr/tarpn/etc/home.ini
   echo "##### HOME background has been told not to restart"
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo " tarpn-home-update.sh:  HOME Background set to OFF" >> $HOME_LOGFILE
fi

################ NC4FG -- HOME
echo -ne $(date) "" >> $HOME_LOGFILE
echo "Telling TARPN-HOME to quit by deleting the GO flag" >> $HOME_LOGFILE
echo "##### Telling TARPN-HOME to quit by deleting the GO flag"
if [ -d /tmp/tarpn ]; then                                        ### stop a TARPN-HOME v2.10 or later
   if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
      echo -ne $(date) "" >> $HOME_LOGFILE
      echo " tarpn-home-update.sh: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
      sudo rm -rf /tmp/tarpn/tarpn_home_go.flag          ## added log write
      sleep 2
   else
      echo -ne $(date) "" >> $HOME_LOGFILE
      echo "temp file directory present but GO flag not set - it would be set if background was running TARPN home" >> $HOME_LOGFILE
      echo "temp file directory present but GO flag not set - it would be set if background was running TARPN home"
   fi
else
   echo -ne $(date) "" >> $HOME_LOGFILE
   echo "temp file directory not present - it would be present if background was running TARPN home" >> $HOME_LOGFILE
   echo "temp file directory not present - it would be present if background was running TARPN home"
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "2 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running" >> $HOME_LOGFILE
    echo "##### 2 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running"
    sleep 5
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "7 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running" >> $HOME_LOGFILE
    echo "##### 7 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running"
    sleep 13
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "20 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running" >> $HOME_LOGFILE
    echo "##### 20 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running"
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "40 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running" >> $HOME_LOGFILE
    echo "##### 40 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running"
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo "60 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running" >> $HOME_LOGFILE
    echo "##### 60 seconds after deleting the tarpn_home_go.flag file, tarpn_home.pyc is still running"
    sleep 20
fi
check_process "tarpn_home.pyc"
if [ $? -ge 1 ]; then
    echo "#### FAIL FAIL FAIL in the process of stopping TARPN HOME"
    echo "#### please consult the local oracle. "
    echo -ne $(date) "" >> $HOME_LOGFILE
    echo " tarpn-home-update.sh:  FAIL - TARPN-HOME refuses to stop.  Consult tarpn@groups.io" >> $HOME_LOGFILE
    exit 1
fi
echo "##### TARPN-HOME has quit"
echo "##### Get new copy of TARPN-HOME, then delete the old, then move the new into place"
 echo -ne $(date) "" >> $HOME_LOGFILE
 echo " tarpn-home-update.sh:  TARPN-HOME has quit.  Moving forward with install" >> $HOME_LOGFILE


echo "##### Remove old copy of TARPN-HOME"
if [ -f /home/pi/tarpn-home-colors.json ];
then
    sudo rm -f /home/pi/tarpn-home-colors.json
fi

sleep 1
sudo rm -rf /usr/tarpn/sbin/home_web_app

cd /usr/tarpn/sbin
sudo rm -rf home_web_app
sudo mkdir home_web_app
sudo chmod 777 home_web_app


cd /usr/tarpn/sbin/home_web_app
sudo date > dateinstalled.txt
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


sleep 0.5
echo " "
sleep 0.5
echo -ne $(date) "" >> $HOME_LOGFILE
echo "The new version was installed" >> $HOME_LOGFILE
echo "That should do it.  The new version should be installed"
sleep 0.5
grep getElementById /usr/tarpn/sbin/home_web_app/index.html | grep About | cut -d\> -f4
sleep 0.5
echo "Now I will re-enable the program."
sleep 0.5
echo "You can do this command to monitor it starting up."
echo "tarpn home logs"
echo -ne $(date) "" >> $HOME_LOGFILE
echo " tarpn-home-update.sh:  TARPN HOME updated OK.  Starting TARPN HOME BACKGROUND!" >> $HOME_LOGFILE
echo -ne $(date) "" >> $HOME_LOGFILE
grep getElementById /usr/tarpn/sbin/home_web_app/index.html | grep About | cut -d\> -f4 >> $HOME_LOGFILE

sudo sed -i "s=BACKGROUND:OFF=BACKGROUND:ON=" /usr/tarpn/etc/home.ini

}
