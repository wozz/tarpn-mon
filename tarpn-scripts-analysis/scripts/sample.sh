#!/bin/bash

echo "SAMPLE"
echo "This is a sample script provided at install time."
echo
echo "Here are the last 10 lines of the node's linkstatus log"
tail -10 /var/log/tarpn_linkstatus.log
echo " "
sleep 2
