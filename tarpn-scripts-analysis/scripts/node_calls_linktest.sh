#!/bin/bash 
read newvalue                # read to get rid of the callsign.

echo "Which port is linktest going to transmit on"
read newvalue 
echo $newvalue > /home/pi/guess1.tmp 
tr '\r' "#" < /home/pi/guess1.tmp > /home/pi/guess2.tmp 
sed 's/#//g' /home/pi/guess2.tmp > /home/pi/guess3.tmp 
newvalue=$(</home/pi/guess3.tmp) 
echo "Calling linktest" $newvalue 
echo "Note that other transmissions on this link may interfere with reception of"
echo "the numbered messages, and the numbered messages may collide with inbound"
echo "packets from the neighbor."
linktest $newvalue NOPRINT

echo "Linktest has ended" 
sleep 2 
exit 0

