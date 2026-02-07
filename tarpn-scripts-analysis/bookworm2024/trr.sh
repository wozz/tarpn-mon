#!/bin/bash

##### 02-05-2026  Bookworm002  Add grep --text to be compatible with bookworm.  

###### =TRR.SH                    Bookworm002  #=  --VERSION--#########

echo -ne "date: "
date

if [ -f /usr/tarpn/sbin/trr.app ];
then
   if [ -f /usr/tarpn/etc/tarpn_home_linkquality.dat ];
   then
      sudo rm -rf /tmp/tarpn/linkquality.dat
      sudo grep --text -v ",0,0,0" /usr/tarpn/etc/tarpn_home_linkquality.dat | tail -100 > /tmp/tarpn/linkquality.dat
      /usr/tarpn/sbin/trr.app
   fi
else
   /usr/tarpn/sbin/trr
fi
sleep 3
exit 0

