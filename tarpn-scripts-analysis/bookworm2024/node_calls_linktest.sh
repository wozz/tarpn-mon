#!/bin/bash
read newvalue                # read to get rid of the callsign.

# 02-04-2026  Bookworm002  Use more concise code Don N2IRZ recommended, for parsing the input.

###### =NODE_CALLS_LINKTEST.SH    Bookworm002=  #  --VERSION--#########




echo "Which port is linktest going to transmit on"
read newvalue
newvalue=$(printf '%s' "$newvalue" | tr -d '\r' | sed 's/#//g')

echo "Calling linktest" $newvalue
echo "Note that other transmissions on this link may interfere with reception of"
echo "the numbered messages, and the numbered messages may collide with inbound"
echo "packets from the neighbor."
/usr/tarpn/sbin/linktest $newvalue NOPRINT

echo "Linktest has ended"
sleep 2
exit 0

