#!/bin/bash

echo "TRR"
echo -ne "node: "
grep nodename /home/pi/node.ini | cut -f 2 -d:
echo -ne "date: "
date
/usr/local/sbin/trr
sleep 5
exit 0

