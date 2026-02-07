#!/bin/bash

######## PI SHUTDOWN BACKGROUND script -- See VERSION # below.
###### Code written by Tadd Torborg  (callsign KA2DEW)  in February 2016 in support of the
###### power manager project.  This runs on a Raspberry PI and establishes a dialog over a
###### ribbon cable to a Firmware device (PWRMAN) using GPIO lines and slow speed signalling.

## This script is called from pi_shutdown.service, which is a service control file.
## pi_shutdown.service controls the registry of this script and specifies that
## this script should be restarted if it ever quits.
## This script is deployed to /usr/local/sbin and is redeployed by "tarpn update".
##
## This script toggles a GPIO output at a 1hz or so rate and drives another GPIO to high continuously.
## It also reads a GPIO.  If that GPIO is driven high, then this script calls sudo shutdown

## Note: The sysfs interface (/sys/class/gpio/...) is optional. Make sure your kernel configuration has the CONFIG_GPIO_SYSFS option enabled and rebuild.

PATH_TO_TARPN_APPS="/usr/tarpn/sbin"

source $PATH_TO_TARPN_APPS/gpio_for_controlpanel.sh


check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}




perform_shutdown1button()  {
     #### turn off the control panel LEDs immediately
     ### TARPN HOME shouldn't be running right now.  Stop it right now.
     if [ -d /tmp/tarpn ]; then
        if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
          echo -ne $(date) "" >> $HOME_LOGFILE
          echo "pi-shutdown-background.sh: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
          sudo rm -rf /tmp/tarpn/tarpn_home_go.flag       ## added log write
        fi
     fi
     #### Tell all the log files that we're going down
     echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
     echo "1-button shutdown Button Pressed!!!  " >> $TARPN_CONTROL_PANEL_LOGFILE
     echo -ne $(date) "" >> $START_STOP_LOGFILE
     echo " ### Control-Panel-Shutdown"  >> $START_STOP_LOGFILE
     echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
     echo " ### Control-Panel-Shutdown"  >> $TARPNCOMMANDLOGFILE
     date >> $TARPN_CONTROL_PANEL_LOGFILE
     uptime >> $TARPN_CONTROL_PANEL_LOGFILE
     sudo killall piminicom
     sudo killall linbpq
     sudo touch /forcefsck
    ### Turn off TARPN 0.5hz LED
    ### turn off BPQ-is-running LED
    turn_off_status_gpio9
    turn_off_node_gpio22
    turn_off_linux_gpio24
    turn_on_status_gpio9
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24


    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24


    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24         ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    turn_on_linux_gpio24         ### 24 "LINUX" on
    sudo shutdown -h now;
    sleep 900
    exit 0
}
###                            toward SDcard
### output high if NODE up   GPIO 22     GPIO 23  input.  if high, do reboot
###                          3V3 PWR     GPIO 24  output high if LINUX
### Shutdown when High input GPIO 10     GROUND
###            .5hz output   GPIO  9     GPIO 25 NC
###           /======= input GPIO 11     GPIO  8 output >>====\
###           |                 toward USB                    |
###           |                                               |
###           \===============================================/

perform_reboot() {
    #### Tell all the log files that we're going down
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "1-button REBOOT Button Pressed!!!  " >> $TARPN_CONTROL_PANEL_LOGFILE
    turn_off_status_gpio9
    turn_off_node_gpio22
    turn_off_linux_gpio24
     ### TARPN HOME shouldn't be running right now.  Stop it right now.
    if [ -d /tmp/tarpn ]; then
       if [ -e /tmp/tarpn/tarpn_home_go.flag ]; then
         echo -ne $(date) "" >> $HOME_LOGFILE
         echo "pi-shutdown-background.sh: Delete the taprn-home-go.flag" >> $HOME_LOGFILE
         sudo rm -rf /tmp/tarpn/tarpn_home_go.flag       ## added log write
       fi
    fi
    echo -ne $(date) "" >> $START_STOP_LOGFILE
    echo " ### Control-Panel-Reboot"  >> $START_STOP_LOGFILE
    echo -ne $(date) "" >> $TARPNCOMMANDLOGFILE
    echo " ### Control-Panel-Reboot"  >> $TARPNCOMMANDLOGFILE
    date >> $TARPN_CONTROL_PANEL_LOGFILE
    uptime >> $TARPN_CONTROL_PANEL_LOGFILE
    sudo killall piminicom
    sudo killall linbpq
    sudo touch /forcefsck
    ### Turn off TARPN 0.5hz LED
    ### turn off BPQ-is-running LED
    turn_off_status_gpio9
    turn_off_node_gpio22
    turn_off_linux_gpio24
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24


    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24


    sleep 0.1
    turn_on_status_gpio9          ### 9 on
    sleep 0.1
    turn_off_status_gpio9
    turn_on_node_gpio22         ### 22 on
    sleep 0.1
    turn_off_node_gpio22
    turn_on_linux_gpio24        ## 24 on
    sleep 0.1
    turn_off_linux_gpio24

    turn_on_linux_gpio24         ### 24 "LINUX" on
    sudo shutdown -r now;
    sleep 900
}

START_STOP_LOGFILE="/var/log/tarpn_startstop.log"
HOME_LOGFILE="/var/log/tarpn_home.log"
OLDLOGFILE="/var/log/tarpn_pwrman.log"
TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"
TARPNCOMMANDLOGFILE="/var/log/tarpn_command.log"

CONTROL_PANEL_PRESENCE_ASSERT_FILE="/home/pi/control_panel_assert.txt"
CONTROL_PANEL_DARK_FILE="/home/pi/control_panel_dark.txt"
CONTROL_PANEL_BBS_FILE="/home/pi/control_panel_bbs.txt"
######################################################################################## VERSION INFO ####################################################################################################
####  2-13-2016 j101  Start from tarpn_background j102
####  2-13-2016 j102  Invert the POWER-DOWN signal.  Temporarily disable the call to sudo shutdown
####  2-13-2016 j103  put the call to sudo shutdown back.  Ready to ship?
####  2-14-2016 j108  j104 through j107 were about moving the ribbon connector 1 step closer to USB connectors.  Move it back.
####  2-14-2016 j109  add forcefsck
####  4-26-2016 j110  add some comments.  Get rid of waste-time-if-not-running()
####  5-27-2016 j111  Add support for GPIOs 25, 10 and 22 which will indicate BPQ status, as well as staying-up/going-down.
####  6-15-2016 j113  move the log file from /usr/local/etc to /var/log.  Change name of things from shutdown to tarpn_pwrman
####  6-24-2016 j114  Create a one-button-shutdown feature which runs if PWRMAN is not discovered.
####  6-25-2016 j115  Debugging the one-button-shutdown feature
####  6-26-2016 j116  One-Button-Shutdown works ok as does the PWRMAN
####  7-11-2016 j117  In PWRMAN shutdown, turn off LINBPQ LED a half second before the linux LEDs.
####  3-25-2017 j118  Fix version number so tarpn sysinfo can parse it.
####  4-28-2018 s001  Leave GPIO-9 driven HIGH before shutdown linux so the observer can see when the Broadcom chip tristates.
####  7-01-2018 s002  Add LINUX and LINBPQ LEDs to one-button-shutdown.  Create dedicated perform-shutdown() function for 1-button
####  7-01-2018 s003  In perform_shutdown1button()  Write a line to the logfile when button is pressed, also blink the LEDs once.
####  1-14-2019 s004  stop TARPN HOME at shutdown
####  3-18-2019 s005  in one-button-shutdown, if gpio23 is pulled high, do a shutdown -r
####  3-18-2019 s006  do shutdown at the bottom side of the loop-back test cycle as well as the top side
####  3-18-2019 s007  fix gpio23 in one-button-shutdown.  It was de-initialized after PWRMAN loopback fail.
####  5-11-2019 s008  add code to support TARPN I2C-ASSIGN with bluetooth.
####  5-12-2019 s009  remove assign-write-completely-needed.txt  if we complete ok
####  5-13-2019 s010  change the i2c-assign process again.  Now the process is completed manually using tarpn finish-i2c
####  5-13-2019 s011  debugging i2c-assign process
#### 10-12-2019 b001  remove i2c-assign process from pi-shutdown-background
####  5-28-2020 b002  add some fluff to the one-button-shutdown sequence
####  5-28-2020 b003  add some fluff to the one-button-shutdown sequence
####  7-25-2020 b006  slow down the control-panel (1 button shutdown) loop back read.
####  7-25-2020 b007  slow down the control-panel (1 button shutdown) loop back read.
####  7-25-2020 b008  slow down the control-panel (1 button shutdown) loop back read.
#### 11-01-2020 b009  where I did a killall python, print a message about it.
####  5-19-2021 b010  new TARPN-HOME run/don't run semaphore
####  5-23-2021 b011  Fix check_process()
####  6-07-2021 b012  Add writes to START_STOP_LOGFILE when LINBPQ starts and stops
####  6-08-2021 b013  unexport everythign at start of this script
####  6-12-2021 b014  Add a print to STDOUT telling the viewer to ignore the invalid argument error message during the unexport instruction
####  6-12-2021 b015  In 1-button-shutdown, test the power-off and reboot buttons 3 times before acting on them.
####  9-21-2022 Bullseye016  when doing an unexport-everything, set all outputs to 0 before unexporting them.
#### 12-27-2022 Bullseye017  Stop looking for the loop-back after finding it the first time.  Change log file name from pwrman.log to tarpn-control-panel.log
####  1-17-2023 Bullseye018  Add write to TARPNCOMMANDLOGFILE when we do a control panel originated shutdown or reboot.
####  1-17-2023 Bullseye019  Move the unexport-everything call to after checking of the gpio export facility exists.
####  3-17-2025 Bullseye020  Check for class gpio and output to the log file if it exists   start using tarpn_control_panel.log
####  7-16-2025 Bullseye021  Unexport-everything now only unexports ports that are exported.
####  7-17-2025 Bullseye022  Remove PWRMAN board support.
####  9-25-2025 Bullseye023  Add a feature where we check existence of $CONTROL_PANEL_PRESENCE_ASSERT_FILE - if it exists, skip loopback test.
####  9-30-2025 Bullseye024  When doing a reboot, toggle all 3 of the LEDs to show that something is happening.
#### 10-02-2025 Bullseye025  When doing a reboot, toggle all 3 of the LEDs to show that something is happening.
#### 10-14-2025 Bullseye026  Check for the existance of $CONTROL_PANEL_DARK_FILE -- if it exists, turn off the lights.
#### 10-17-2025 Bullseye027  modify script to put all gpio-driver-specific code at the top of the function in trivial functions() -- this to support future OSs
#### 10-19-2025 Bullseye028  Fix the shutdown button.  It was always read as Pressed in the startup check.
#### 10-30-2025 Bullseye029  Use the GPIO 24 Linux LED to indicate if BBS has mail, if the $CONTROL_PANEL_BBS_FILE is present
#### 10-30-2025 Bullseye030  Announce the version of the gpio_for_controlpanel.sh file
####  2-06-2026 Bullseye031  Enhance the version string to match tarpn sysinfo.   Fix bug in time-stamp output in "PASS - ONE-BUTTON loopback cable" messages
####

echo -e "\n\n\n\n"  >> $TARPN_CONTROL_PANEL_LOGFILE
echo -ne $(date) "" >> $TARPN_CONTROL_PANEL_LOGFILE
echo "#### -PI_SHUTDOWN_BACKGROUND.SH Bookworm031"  >> $TARPN_CONTROL_PANEL_LOGFILE; #  --VERSION--#########
announce_gpio_version






if [ -d /sys/class/gpio ];
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "/sys / class/gpio  CONFIG_GPIO_SYSFS option, seems to exist." >> $TARPN_CONTROL_PANEL_LOGFILE
fi

_linbpqExecutionStatus=0;

RUNNING=1;
NOTRUNNING=0;

verify_gpio_system_support             #### returns _inputport == 1 if the loopback is high (i.e. driven high by gpio8).
_value=1
if [ $_value -ne $_inputport ]; then
    echo "ERROR9-0: No GPIO support found.  See SBIN / gpio_for_controlpanel.sh for this operating system" >> $TARPN_CONTROL_PANEL_LOGFILE
    sleep 900
    exit 1
fi

echo "GPIO support found." >> $TARPN_CONTROL_PANEL_LOGFILE


### ###### Make sure we have the GPIO export facility.  We always should, but if not, wait 15 minutes and then exit
### if [ -f /sys/class/gpio/export ];
### then
###     echo "gpio export facility exists " >> $TARPN_CONTROL_PANEL_LOGFILE
###     _inputport=1;
### else
###     echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
###     echo "ERROR9-1: /sys / class/gpio/export doesn't seem to exist." >> $TARPN_CONTROL_PANEL_LOGFILE
###     sleep 900
###     exit 1
### fi

#### Clear out any earlier programming in case this background task runs more than once.
    unexport_everything;

##### set up our GPIO ports to read and write the power management features

### echo "8" > /sys/class/gpio/export
### echo "out" > /sys/class/gpio/gpio8/direction
### echo "1" > /sys/class/gpio/gpio8/value
### echo "11" > /sys/class/gpio/export
### echo "in" > /sys/class/gpio/gpio11/direction
### echo "1" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to high,
### sleep 0.1
### _inputport=$(cat /sys/class/gpio/gpio11/value)        ### read status of loopback gpio 11
### echo "Xread-status-of-loopback-gpio11=" $_inputport >> $TARPN_CONTROL_PANEL_LOGFILE
###
### echo "0" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to low,
### sleep 0.1
### _inputport=$(cat /sys/class/gpio/gpio11/value)        ### read status of loopback gpio 11
### echo "Xread-status-of-loopback-gpio11=" $_inputport >> $TARPN_CONTROL_PANEL_LOGFILE
###
### echo "1" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to high,
### sleep 0.1
### _inputport=$(cat /sys/class/gpio/gpio11/value)        ### read status of loopback gpio 11
### echo "Xread-status-of-loopback-gpio11=" $_inputport >> $TARPN_CONTROL_PANEL_LOGFILE
###
### echo "0" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to low,
### sleep 0.1
### _inputport=$(cat /sys/class/gpio/gpio11/value)        ### read status of loopback gpio 11
### echo "Xread-status-of-loopback-gpio11=" $_inputport >> $TARPN_CONTROL_PANEL_LOGFILE
###

#echo "10" > /sys/class/gpio/export
#echo "in" > /sys/class/gpio/gpio10/direction
#sleep 0.1
#_inputport=$(cat /sys/class/gpio/gpio10/value)        ### read status of shutdown gpio 10
#echo "Xread-status-of-shutdown-switch-gpio10=" $_inputport >> $TARPN_CONTROL_PANEL_LOGFILE



##### Touch FORCE-FSCK.  This tells Linux to set up for a full FSCK check the next time the Raspberry PI boots.
sudo touch /forcefsck


echo "check to see if we're doing one-button shutdown mode"

############
############ One Button Shutdown setup  ((used for control panel))
############
###                            toward SDcard
### output high if LINBPQ up GPIO 22     GPIO 23  input.  if high, do reboot
###                          3V3 PWR     GPIO 24  output high if LINUX
### Shutdown when High input GPIO 10     GROUND
###            .5hz output   GPIO  9     GPIO 25 NC
###           /======= input GPIO 11     GPIO  8 output >>====\
###           |                 toward USB                    |
###           |                                               |
###           \===============================================/
###
### If the circuit is properly connected, GPIO 8 and GPIO 11 will be tied together
### through a jumper.  If that is seen to be true, then this script will keep GPIO 9 toggling
### GPIO24 will be HIGH always, and GPIO 10 will be read as a SHUTDOWN pin.
### IF GPIO 10 is read as a high, then do a shutdown command.
####
#### GPIO  8 is output   (loopback test output to be read by gpio 11)        gpio 8  one button shutdown
#### GPIO  9 is output   (toggle this at .5 hz)                              gpio 9  one button shutdown
#### GPIO 10 is input    (if this is high, do a shutdown)                    gpio 10 one button shutdown
#### GPIO 11 is input    (loopback test input)                               gpio 11 one button shutdown
#### GPIO 23 is input                                                        gpio 23 one button shutdown

echo "If this is not the 1st time this service started up, there may be errors right here.  That's ok."

#### set-up for One-Button-Shutdown FIRST-RUN loopback test.
configure_gpio8_output                  ### Configure but don't set the high/low sense of gpio8
drive_loopback_gpio8_high
configure_gpio11_input


### See if we want to skip the loopback test
if [ -f $CONTROL_PANEL_PRESENCE_ASSERT_FILE ];then
   echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
   echo "$CONTROL_PANEL_PRESENCE_ASSERT_FILE FOUND - skip loopback test" >> $TARPN_CONTROL_PANEL_LOGFILE
else
    drive_loopback_gpio8_high
    sleep 0.5
    read_status_of_loopback_gpio11
   _value=1
   if [ $_value -ne $_inputport ]; then
     echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
     echo "FAIL - ONE-BUTTON loopback cable fail at startup on first -1- echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
     tristate_and_remove_gpio_service_loopback_drive_gpio8
     sleep 900;
     exit 1
   else
     echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
     echo "PASS - ONE-BUTTON loopback cable pass at startup on first -1- echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
   fi
   drive_loopback_gpio8_low
     sleep 0.5
   read_status_of_loopback_gpio11
   _value=0
   if [ $_value -ne $_inputport ]; then
     echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
     echo "FAIL - ONE-BUTTON loopback cable fail at startup on first -0- (2nd) echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
     tristate_and_remove_gpio_service_loopback_drive_gpio8
     sleep 900;
     exit 1
   else
      echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
      echo "PASS - ONE-BUTTON loopback cable pass at startup on first -0- echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
   fi


    drive_loopback_gpio8_high
    sleep 0.1
    read_status_of_loopback_gpio11      #### returns _inputport == 1 if the loopback is high (i.e. driven high by gpio8).
    _value=1
    if [ $_value -ne $_inputport ]; then
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
        echo "FAIL - ONE-BUTTON loopback cable fail at startup on 2nd -1- (3rd) echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
        tristate_and_remove_gpio_service_loopback_drive_gpio8
        remove_gpio_coverage_of_gpio11_loopback_input_pin               ### we don't want to claim gpio 11.  Somebody else may need this pin.
        sleep 900;
        exit 1
    else
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
        echo "PASS - ONE-BUTTON loopback cable pass at startup on 2nd -1- echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
    fi


    drive_loopback_gpio8_low
    sleep 0.5
    read_status_of_loopback_gpio11      #### returns 1 if the loopback is high (i.e. driven high by gpio8).
    _value=0
    if [ $_value -ne $_inputport ]; then
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
        echo "FAIL - ONE-BUTTON loopback cable fail at startup on 2nd -0- (4th) echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
        tristate_and_remove_gpio_service_loopback_drive_gpio8
        remove_gpio_coverage_of_gpio11_loopback_input_pin               ### we don't want to claim gpio 11.  Somebody else may need this pin.
        sleep 900;
        exit 1
    else
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
        echo "PASS - ONE-BUTTON loopback cable pass at startup on 2nd -0- echo test" >> $TARPN_CONTROL_PANEL_LOGFILE
    fi
fi         ## bypass loopback test


#### LOOPBACK test passes.

echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
echo "####  ONE-BUTTON loopback cable PASS at startup" >> $TARPN_CONTROL_PANEL_LOGFILE



configure_gpio9_output
turn_on_status_gpio9

#### port 10 is input for SHUTDOWN command
configure_gpio10_shutdown_button_as_input


#### port 23 is input for REBOOT command
configure_gpio23_reboot_button_as_input

#### set up output 22 to say that LINBPQ is running
configure_gpio22_node_led_as_output
turn_off_node_gpio22

#### set up output 24 to say that LINUX is running
configure_gpio24_as_linux_led_output
if [ -f $CONTROL_PANEL_DARK_FILE ];         ### don't turn on GPIO 24 for Linux if this file is present
then
    turn_off_linux_gpio24                   ### file is present, turn off GPIO 24
else                                        ### but wait!
    if [ -f $CONTROL_PANEL_BBS_FILE ];      ### use GPIO 24 for Has BBS Mail indicator if this file is present
    then
        turn_off_linux_gpio24                   #### We're using GPIO 24 for BBShasMail.  turn it off for now.
    else
        turn_on_linux_gpio24                    #### turn on GPIO 24 to tell the operator that Linux is running.
    fi
fi




#### make sure Shutdown button is NOT pressed at start of this script.
read_shutdown_button_gpio10
_value=0
if [ $_value -ne $_inputport ]; then
   echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
   echo "ERROR9.1: Power-Off input port was at SHUTDOWN at start of the pi_shutdown_background.sh"  >> $TARPN_CONTROL_PANEL_LOGFILE
   echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
   echo "          Stall for 15 minutes and then abort the script"  >> $TARPN_CONTROL_PANEL_LOGFILE
   sudo touch /forcefsck
   sleep 900
   echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
   echo "          Abort the script"  >> $TARPN_CONTROL_PANEL_LOGFILE
   exit
fi


#### One Button Shutdown Loop
while [ 1 ];
do
   #### HIGH portion   -- WRITE HIGH to the 1 second HELLO output
   if [ -f $CONTROL_PANEL_DARK_FILE ];then     ### don't turn on gpio9 if this file is present
      turn_off_status_gpio9           ### if we are 'dark' then Linux LED should always be off
      turn_off_linux_gpio24
   else
      turn_on_status_gpio9
    fi

    #### Control GPIO 24, which has double duty.
    #### GPIO 24 can be the BBShasMAIL indicator, or it can be on all the time to show that Linux is still up.
    if [ -f $CONTROL_PANEL_BBS_FILE ];    ### use GPIO 24 for Has BBS Mail indicator if this file is present
    then
        #### BBS FILE is present.  See if we have mail or not
        if [ -f /usr/tarpn/etc/bbshasmail.txt ];
        then
            ####   GPIO 24 will be used only for BBS has Mail indication.  Check if there IS mail.
            if grep -q "BBS_HAS_MAIL" /usr/tarpn/etc/bbshasmail.txt; then
                turn_on_linux_gpio24           #### turn on GPIO 24 to tell the operator that BBS has mail.
            else
                turn_off_linux_gpio24          #### turn OFF GPIO 24 to tell the operator that BBS does NOT have mail.
            fi
        else
            ### bbshasmail.txt is missing.  That's interesting.  But turn off the LED anyway
            turn_off_linux_gpio24          #### turn OFF GPIO 24 to tell the operator that BBS does NOT have mail.
        fi
    else
        #### Not using GPIO 24 for BBS indication.
        ####   GPIO 24 will be used only for Linux is running mode indication - gate this based on DARK file.
        if [ -f $CONTROL_PANEL_DARK_FILE ];
        then     ### don't turn on gpio9 if this file is present
            turn_off_linux_gpio24          #### turn OFF GPIO 24 to be dark
        else
            turn_on_linux_gpio24           #### turn on GPIO 24 to tell the operator that Linus is running.
        fi
    fi

    #### Now, after waiting a blip, turn off the status LED GPIO 9, so it just blinks.
    #### Also turn off the BBS HAS MAIL LED if that is the mode GPIO 24 is in.
    sleep 0.01
    turn_off_status_gpio9
    if [ -f $CONTROL_PANEL_BBS_FILE ];    ### IF using GPIO 24 for Has BBS Mail indicator, then turn ot off after blinking
    then
        ####   GPIO 24 will be used only for BBS has Mail indication.  Check if there IS mail.
        turn_off_linux_gpio24          #### turn OFF GPIO 24 to tell the operator that BBS does NOT have mail.
    fi





    #### Now see if the ONE-BUTTON end wants us to shutdown
    read_shutdown_button_gpio10
    _value=0
    if [ $_value -ne $_inputport ]; then
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
	echo "Power-Off input port is not low -- Check it again"  >> $TARPN_CONTROL_PANEL_LOGFILE
        sleep 0.1
        read_shutdown_button_gpio10
        if [ $_value -ne $_inputport ]; then
            echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
            echo "Power-Off input port is not low a 2nd time-- Check it a 3rd time"  >> $TARPN_CONTROL_PANEL_LOGFILE
            sleep 0.1
            read_shutdown_button_gpio10
            if [ $_value -ne $_inputport ]; then
                echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
                echo "Power-Off input port is not low a 3rd time-- call SHUTDOWN (top)"  >> $TARPN_CONTROL_PANEL_LOGFILE
                perform_shutdown1button
                exit 0
            fi
        fi
	echo "Power-Off input port is low - don't power off"  >> $TARPN_CONTROL_PANEL_LOGFILE
    fi




    #### Now see if the REBOOT the PI input is high    HIGH means we should reboot
    read_reboot_button_gpio23
    _value=0
    if [ $_value -ne $_inputport ]; then
        echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
        echo "REBOOT input port is not low -- Check it again"  >> $TARPN_CONTROL_PANEL_LOGFILE
        sleep 0.1
        read_reboot_button_gpio23
        if [ $_value -ne $_inputport ]; then
            echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
            echo "REBOOT input port is not low a 2nd time -- Check it again"  >> $TARPN_CONTROL_PANEL_LOGFILE
            sleep 0.1
            read_reboot_button_gpio23
            if [ $_value -ne $_inputport ]; then
                echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
                echo "REBOOT input port is not low a 3rd time -- call REBOOT (top)"  >> $TARPN_CONTROL_PANEL_LOGFILE
                perform_reboot
                exit 0
            fi
       fi
       echo "REBOOT input port is low - don't power off"  >> $TARPN_CONTROL_PANEL_LOGFILE
   fi


   ### If LINBPQ is running, turn on GPIO22 to drive an LED
   check_process "linbpq"
   if [ $? -ge 1 ]; then
      ### BPQ node IS running
      if [ $_linbpqExecutionStatus == $NOTRUNNING ];
      then
         _linbpqExecutionStatus=$RUNNING;
         echo -ne $(date) "" >> $START_STOP_LOGFILE
         echo " LINBPQ status went to RUNNING in PI-SHUTDOWN-BACKGROUND"  >> $START_STOP_LOGFILE
      fi
      if [ -f $CONTROL_PANEL_DARK_FILE ];then     ### don't turn on gpio22 if this file is present
         turn_off_node_gpio22
      else
         turn_on_node_gpio22                    #### turn on gpio22 to tell the operator that the node is running
      fi
   else
      ### BPQ node is NOT running
      if [ $_linbpqExecutionStatus == $RUNNING ];
      then
         _linbpqExecutionStatus=$NOTRUNNING;
         echo -ne $(date) "" >> $START_STOP_LOGFILE
         echo " LINBPQ status went to NOT-running in PI-SHUTDOWN-BACKGROUND"  >> $START_STOP_LOGFILE
      fi
      turn_off_node_gpio22
   fi

   #### This sleep establishes the HELLO low half-wave cycle time
   sleep 0.4

   #### LOW portion

   #### Now see if the SHUTDOWN button wants us to shutdown
   read_shutdown_button_gpio10
   _value=0
   if [ $_value -ne $_inputport ]; then
	  #### #### #### We ARE being told to shutdown.
          echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
	  echo "Power-Off input port is not low -- do SHUTDOWN (bottom)"  >> $TARPN_CONTROL_PANEL_LOGFILE
	  perform_shutdown1button
	  exit
   fi

   #### Now see if the REBOOT the PI input is high
    read_reboot_button_gpio23
    _value=0
    if [ $_value -ne $_inputport ]; then
          echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
	  echo "REBOOT input port is not low -- call REBOOT (bottom)"  >> $TARPN_CONTROL_PANEL_LOGFILE
          perform_reboot
	  exit
   fi


   #### This sleep establishes the HELLO high half-wave cycle time
   sleep 0.5

done
exit 0




