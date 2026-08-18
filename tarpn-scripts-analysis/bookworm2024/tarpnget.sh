#!/bin/bash

###tarpnget
### Do WGET several times if necessry

### 2023-05-06 -- bullseye 001 -- create tarpnget().
### 2023-05-06 -- bullseye 002 -- create tarpnget_path_and_filename().
### 2023-08-28 -- bullseye 003 -- add a 4th and 5th try.  Create a local 10second delay and use it in many places
### 2026-01-01 -- Bookworm004  -- move to Bookworm and add a version string for it.

###### =TARPNGET.SH               Bookworm004=    --VERSION--

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


tarpnget() {
sudo rm -rf /tmp/tarpngettemp
mkdir /tmp/tarpngettemp

if [ -f /usr/tarpn/etc/source_url.txt ];
then
    echo -n;
else
   echo "##### TARPNGET ERROR101.1: source_URL file not found."
   echo
   echo "##### TARPNGET Aborting"
   exit 1
fi
_source_url=$(tr -d '\0' </usr/tarpn/etc/source_url.txt);

if [ -f $1 ];
then
   mv $1 /tmp/tarpngettemp
fi

wget -o /dev/null $_source_url/$1
if [ -f $1 ];
then
   if grep -q "meta http-equiv" $1;
   then
      echo -n "ERROR! "
      echo $1 "might not exist at the source URL--contents are html file."
      rm $1;
      if [ -f /tmp/tarpngettemp/$1 ];
      then
         mv /tmp/tarpngettemp/$1 $1
      fi
      exit 1;
   else
     echo $1 "ok"
   fi
else
   sleep 1
   wget -o /dev/null $_source_url/$1
   if [ -f $1 ];
   then
      if grep -q "meta http-equiv" $1; then
         echo -n "ERROR! "
         echo $1 "might not exist at the source URL--contents are html file."
         rm $1;
         if [ -f /tmp/tarpngettemp/$1 ];then
            mv /tmp/tarpngettemp/$1 $1
         fi
         exit 1;
      else
         echo $1 "downlaoded on 2nd try by TARPNGET"
      fi
   else
      echo "retry $1 in 10 seconds"
      local_sleep10

      wget -o /dev/null $_source_url/$1
      if [ -f $1 ];
      then
         if grep -q "meta http-equiv" $1; then
            echo -n "ERROR! "
            echo $1 "might not exist at the source URL--contents are html file."
            rm $1;
            if [ -f /tmp/tarpngettemp/$1 ];then
                mv /tmp/tarpngettemp/$1 $1
            fi
            exit 1;
         else
            echo $1 "downlaoded on 3rd try by TARPNGET"
         fi
      else
         echo "retry $1 in 10 seconds"
         local_sleep10

         wget -o /dev/null $_source_url/$1
         if [ -f $1 ];
         then
            if grep -q "meta http-equiv" $1; then
               echo -n "ERROR! "
               echo $1 "might not exist at the source URL--contents are html file."
               rm $1;
               if [ -f /tmp/tarpngettemp/$1 ];then
                   mv /tmp/tarpngettemp/$1 $1
               fi
               exit 1;
            else
               echo $1 "downlaoded on 4th try by TARPNGET"
            fi
         else
            echo "retry $1 in 10 seconds"
            local_sleep10

            wget -o /dev/null $_source_url/$1
            if [ -f $1 ];
            then
               if grep -q "meta http-equiv" $1; then
                  echo -n "ERROR! "
                  echo $1 "might not exist at the source URL--contents are html file."
                  rm $1;
                  if [ -f /tmp/tarpngettemp/$1 ];then
                      mv /tmp/tarpngettemp/$1 $1
                  fi
                  exit 1;
               else
                  echo $1 "downlaoded on 5th try by TARPNGET"
               fi
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


