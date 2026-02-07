#!/bin/bash

###tarpnget
### Do WGET several times if necessry

### 2023-05-06 -- bullseye 001 -- create tarpnget().
### 2023-05-06 -- bullseye 002 -- create tarpnget_path_and_filename().
### 2023-08-28 -- bullseye 003 -- add a 4th and 5th try.  Create a local 10second delay and use it in many places
### 2023-10-19 -- bullseye 004 -- add a print on the 1st try
### 2025-05-07 -- bullseye 005 -- instead of "newfile ok" use "newfile downloaded ok"
### 2025-11-22 -- bullseye 006 -- Check for HTML file and declare error
### 2025-11-22 -- bullseye 007 -- check for HTML file on each wget attempt
### 2025-11-23 -- bullseye 008 -- comment out tarpnget_path_and_filename
### 2025-11-23 --  bullseye009 -- put back tarpnget_path_and_filename   tarpn_start1dl.sh needs it!

### "--VERSION--tarpnget                  Bullseye009-  START" >> $SERVICELOGFILE


local_sleep10() {
sleep 0.5
echo -n "9"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "8"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "7"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "6"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "5"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "4"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "3"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "2"
sleep 0.5
echo -n " "
sleep 0.5
echo -n "1"
sleep 0.5
echo -n " "
sleep 0.5
echo "0"
sleep 0.5
}


oneget() {
   _source_url=$(tr -d '\0' </usr/local/sbin/source_url.txt);
   ##echo "attempting to download " $_source_url/$1
   _result=0;         ### bad result
   rm -f $1
   wget --tries=1 -o /dev/null $_source_url/$1
   if [ -f $1 ];
   then
       ###echo "file $1 downloaded -- check if it is html"
       if grep -q "html xmlns=" $1;
       then
           echo "$1 is html -- delete it and report bad item"
           rm -f $1
           _result=0;         ### bad result
       else
           ##echo "file $1 downloaded ok"
           _result=1;
       fi
   else
           ##echo "$1 not downloaded"
       _result=0;       ## no file retrieved.
   fi
}


tarpnget() {
   ##echo "tarpnget 2025nov23 1227pm   asked to download" $1
   if [ -f /usr/local/sbin/source_url.txt ];
   then
       echo -n;
   else
      echo "##### TARPNGET ERROR101.1: source_URL file not found."
      echo
      echo "##### TARPNGET Aborting"
      exit 1
   fi

   if [ -f $1 ];
   then
      echo $1 "already exists -- deleting it"
      rm $1
   fi

   oneget $1
   if [ -f $1 ];
   then
      echo $1 "downloaded ok"
   else
      sleep 1
      echo "get $1 -- 2nd try"
      oneget $1
      if [ -f $1 ];
      then
         echo $1 "downlaoded on 2nd try by TARPNGET"
      else
         echo "retry $1 in 10 seconds"
         local_sleep10

         oneget $1
         if [ -f $1 ];
         then
            echo $1 "downlaoded on 3rd try by TARPNGET"
         else
            echo "retry $1 in 10 seconds"
            local_sleep10

            oneget $1
            if [ -f $1 ];
            then
               echo $1 "downlaoded on 4th try by TARPNGET"
            else
               echo "retry $1 in 10 seconds"
               local_sleep10

               oneget $1
               if [ -f $1 ];
               then
                  echo $1 "downlaoded on 5th try by TARPNGET"
               else
                  echo "TARPNGET    Failed to download" $1
                  echo "TARPNGET    Abort script"
                  exit 1
               fi
            fi
         fi
      fi
   fi
}

tarpnget_path_and_filename() {

   if [ -f $2 ];
   then
      echo $2 "already exists -- deleting it"
      rm $2
   fi

   wget -o /dev/null $1/$2
   if [ -f $2 ];
   then
      echo $2 "ok"
   else
      wget -o /dev/null $1/$2
      if [ -f $2 ];
      then
         echo $1 "downlaoded on 2nd try by TARPNGET"
      else
         local_sleep10
         wget -o /dev/null $1/$2
         if [ -f $2 ];
         then
            echo $2 "downlaoded on 3rd try by TARPNGET"
         else
            local_sleep10
            wget -o /dev/null $1/$2
            if [ -f $2 ];
            then
               echo $2 "downlaoded on 4th try by TARPNGET"
            else
               local_sleep10
               wget -o /dev/null $1/$2
               if [ -f $2 ];
               then
                  echo $2 "downlaoded on 5th try by TARPNGET"
               else
                  echo "TARPNGET    Failed to download" $1/$2
                  echo "TARPNGET    Abort script"
                  exit 1
               fi
            fi
         fi
      fi
   fi
}


