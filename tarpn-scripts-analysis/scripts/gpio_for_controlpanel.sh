#!/bin/bash

TARPN_CONTROL_PANEL_LOGFILE="/var/log/tarpn_control_panel.log"


#### 10-17-2025 Bullseye001  First Version
#### 10-30-2025 Bullseye002  Stop configuring GPIO 8 with every output command.


announce_gpio_version() {
    echo -ne $(date) "" >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio_for_controlpanel.sh --VERSION-- Bullseye002 - start" >> $TARPN_CONTROL_PANEL_LOGFILE
}

check_process() {
  #  echo "$ts: checking $1"
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}


##### VERIFY GPIO SYSTEM SUPPORT
##### returns 1 if we think GPIO support exists on this Raspberry PI

verify_gpio_system_support() {
    if [ -f /sys/class/gpio/export ];
    then
        _inputport=1;         ### GPIO support exists.
    else
        _inputport=0;         ### GPIO support not found.
    fi
}

################## GPIO 8   LOOPBACK test OUTPUT DRIVE pin.


#### enable GPIO 8 to be a port and to be an output
#### This function is null in Bookworm because driving the port to be an output also makes it a port
#### This function is only called from drive_loopback_gpio 8_XXXX
configure_gpio8_output() {
    echo "8" > /sys/class/gpio/export                      #### configure-gpio 8-output
    echo "out" > /sys/class/gpio/gpio8/direction         #### configure-gpio 8-output
}

tristate_and_remove_gpio_service_loopback_drive_gpio8() {
    echo "in" > /sys/class/gpio/gpio8/direction     ### configure-gpio 8-tristate
    echo "8" > /sys/class/gpio/unexport             ### configure-gpio 8-tristate
}

#### called from drive_loopback_gpio8 only
turn_on_loopbackdrive_gpio8() {
    echo "1" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to high,
}

#### called from drive_loopback_gpio8 only
turn_off_loopbackdrive_gpio8() {
    echo "0" > /sys/class/gpio/gpio8/value      ### while driving GPIO 8 loopback, drive it to low,
}

drive_loopback_gpio8_low() {
    turn_off_loopbackdrive_gpio8              ### drive-loopback-gpio 8-low
}

drive_loopback_gpio8_high() {
    turn_on_loopbackdrive_gpio8            ### drive-loopback-gpio 8-high
}



################## GPIO 9  STATUS led OUTPUT
configure_gpio9_output() {
    echo "9" > /sys/class/gpio/export                       ## configure-gpio 9-output enabling GPIO 9 as an output
    echo "out" > /sys/class/gpio/gpio9/direction            ## configure-gpio 9-output enabling GPIO 9 as an output
}

turn_on_status_gpio9() {
    echo "1" > /sys/class/gpio/gpio9/value          ### 9 on
}
turn_off_status_gpio9() {
    echo "0" > /sys/class/gpio/gpio9/value          ### 9 off
}

remove_gpio_coverage_of_gpio9_status_led_output() {
    turn_off_status_gpio9                            ### configure-gpio 9-tristate
    echo "9" > /sys/class/gpio/unexport              ### configure-gpio 9-tristate
}




############# GPIO 10 Shutdown button INPUT

remove_gpio_coverage_of_gpio10_shutdown_button_input_pin() {
    echo "0" > /sys/class/gpio/gpio10/value          ### configure-gpio 10-tristate   SHUTDOWN button
    sleep 0.1
    echo "10" > /sys/class/gpio/unexport             ### configure-gpio 10-tristate   SHUTDOWN button
}

configure_gpio10_shutdown_button_as_input() {
    echo "10" > /sys/class/gpio/export                  ### configure-gpio 10-shutdown-button_as-input
    sleep 0.1
    echo "in" > /sys/class/gpio/gpio10/direction        ### configure-gpio 10-shutdown-button_as-input
}

#### Read SHUTDOWN button
#### This function assumes that port 10 is already set to be an input, or doesn't need to be set to an input before this operation.
read_shutdown_button_gpio10() {
    _inputport=$(cat /sys/class/gpio/gpio10/value)
}



########## GPIO 11 is the LOOPBACK input
## This is used in concert with GPIO 8 to test if the control panel is attached.

remove_gpio_coverage_of_gpio11_loopback_input_pin() {
    echo "11" > /sys/class/gpio/unexport             ### configure-gpio 11-tristate
}

#### Set gpio 11 to be an input.
#### This function may be null in some GPIO paradigms, like when using pinctrl for GPIOs.
configure_gpio11_input() {
    echo "11" > /sys/class/gpio/export                         ### configure-gpio 11-input
    sleep 0.1
    echo "in" > /sys/class/gpio/gpio11/direction               ### configure-gpio 11-input
}

#### Read Status Of Loopback GPIO 11
#### This function assumes that port 11 is already set to be an input, or doesn't need to be set to an input before this operation.
read_status_of_loopback_gpio11() {
    _inputport=$(cat /sys/class/gpio/gpio11/value)        ### read status of loopback gpio 11
}





############ GPIO 22 is the NODE-is-running status light.
turn_on_node_gpio22() {
    echo "1" > /sys/class/gpio/gpio22/value          ### turn on gpio 22   NODE-is-running
}
turn_off_node_gpio22() {
    echo "0" > /sys/class/gpio/gpio22/value          ### turn off gpio 22   NODE is NOT running
}


#### Configure GPIO 22 as NODE-is-running status LED output
configure_gpio22_node_led_as_output() {
    echo "22" > /sys/class/gpio/export               ### configure-gpio 22-NODE-LED
    sleep 0.1
    echo "out" > /sys/class/gpio/gpio22/direction    ### configure-gpio 22-NODE-LED
}


remove_gpio_coverage_of_gpio22_NODE_led() {
    turn_off_node_gpio22                             ### UNEXPORT-linux-led-gpio 22-tristate   for UNEXPORT
    echo "22" > /sys/class/gpio/unexport             ### UNEXPORT-linux-led-gpio 22-tristate   for UNEXPORT
}




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


############ GPIO 23 is REBOOT button

#### Configure GPIO 23 as Reboot button input
configure_gpio23_reboot_button_as_input() {
    echo "23" > /sys/class/gpio/export                  ### configure-gpio 23-reboot-button_as-input
    sleep 0.1
    echo "in" > /sys/class/gpio/gpio23/direction        ### configure-gpio 23-reboot-button_as-input
}

#### Read RESET button
#### This function assumes that port 23 is already set to be an input, or doesn't need to be set to an input before this operation.
read_reboot_button_gpio23() {
   _inputport=$(cat /sys/class/gpio/gpio23/value)
}





############ GPIO2 4 is the LINUX is running LED.

turn_on_linux_gpio24() {
    echo "1" > /sys/class/gpio/gpio24/value          #### TURN ON LINUX GPIO 24
}
turn_off_linux_gpio24() {
    echo "0" > /sys/class/gpio/gpio24/value          #### TURN OFF LINUX GPIO 24
}

configure_gpio24_as_linux_led_output() {
    echo "24" > /sys/class/gpio/export                   #### configure GPIO 24 as linux LED output
    sleep 0.1
    echo "out" > /sys/class/gpio/gpio24/direction        #### configure GPIO 24 as linux LED output
}

remove_gpio_coverage_of_gpio24_linux_led() {
    turn_off_linux_gpio24                            #### REMOVE GPIO 24 pin from GPIO sys class
    echo "24" > /sys/class/gpio/unexport             #### REMOVE GPIO 24 pin from GPIO sys class
}







unexport_everything()  {
echo "start of unxport-everything()."
###### Check each GPIO and if it exists, turn it off and unexport it.
if [ -f /sys/class/gpio/gpio8 ];                                              ### unexport-everything needs to know if gpio 8 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio8 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    tristate_and_remove_gpio_service_loopback_drive_gpio8
fi
if [ -f /sys/class/gpio/gpio9 ];                                             ### unexport-everything needs to know if gpio 9 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio9 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    remove_gpio_coverage_of_gpio9_status_led_output
fi
if [ -f /sys/class/gpio/gpio10 ];                                            ### unexport-everything needs to know if gpio 10 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio10 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    remove_gpio_coverage_of_gpio10_shutdown_button_input_pin
fi

if [ -f /sys/class/gpio/gpio11 ];                                           ### unexport-everything needs to know if gpio 11 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio11 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    remove_gpio_coverage_of_gpio11_loopback_input_pin
fi

if [ -f /sys/class/gpio/gpio22 ];                                           ### unexport-everything needs to know if gpio 22 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio22 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    remove_gpio_coverage_of_gpio22_NODE_led
fi
if [ -f /sys/class/gpio/gpio24 ];                                           ### unexport-everything needs to know if gpio 24 is exported, else we'd get an error when unexporting it.
then
    echo -ne $(date) " " >> $TARPN_CONTROL_PANEL_LOGFILE
    echo "gpio24 exists " >> $TARPN_CONTROL_PANEL_LOGFILE
    remove_gpio_coverage_of_gpio24_linux_led
fi
echo "end-of unexport_everything()."
}


