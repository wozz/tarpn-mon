#!/bin/bash

DOTSH=".sh"
     # tr '\r' '#' < firstline.txt > out.txt

#echo "more shortly..."
     read newvalue                # read to get rid of the callsign.
#echo -n "callsign is "
     #echo $newvalue
if [ -d /home/pi/bpq-extensions ];
then
echo "List of available programs:"
     ls -1 /home/pi/bpq-extensions/*.sh | cut -d\. -f1 | cut -d\/ -f5
     echo -n "Which program do you want to run? -->"
     read apptorun
     echo $apptorun > /home/pi/apptorun.tmp
     tr '\r' '#' < /home/pi/apptorun.tmp > /home/pi/apptorun2.tmp
     sed 's/#//g' /home/pi/apptorun2.tmp > /home/pi/apptorun3.tmp
     APPTORUN=$(</home/pi/apptorun3.tmp)

     value="$APPTORUN$DOTSH"
     #echo $value | od -x
     #echo "Looking for  " $value

     if [ -f "/home/pi/bpq-extensions/$value" ];
     then
          echo "Calling the script " /home/pi/bpq-extensions/$value
          /home/pi/bpq-extensions/$value
          exit 1
     else
        echo "That program is not on the list.   Returning to node prompt."
     fi
else
     echo "ERROR: There is supposed to be a folder /home/pi/bpq-extensions"
     echo "       I couldn't find it.  LINUX call is aborting."
fi
echo " "
sleep 2



#### use CUT to parse the new line character out. 
## pi@taddnode:~ $ od -h secondline.txt
## 0000000 7070 7070 0d70 000a
## 0000007

