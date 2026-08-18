#!/bin/bash


### bullseye 001   add --text option when grepping node.ini.  For some reason grep thinks node.ini is a binary file.  --text suppresses that check.
### bullseye 002   Remove the fully qualified path on vcgencmd measure_temp.
### bullseye 003   add date of update, DF of boot disk.
### bullseye 004   working on fixing the no-TNCs-reporting file-not-found error.
### bookworm 005   Create LATLON.SH from TINFO.SH.
### Bookworm006   add version number line that can be displayed in tarpn sysinfo
### =LATLON.SH                 Bookworm006=   --VERSION--

   echo -n "lat/lon coordinates: "
   grep --text latlon /home/pi/node.ini | cut -d: -f2


echo " "
echo " "
echo " "
   sleep 2
