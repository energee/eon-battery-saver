#!/usr/bin/bash
#
# SCRIPT: battery_saver.sh
# AUTHOR: Rick Lan <ricklan@gmail.com>
# DATE:   2018-09-10
#
# PURPOSE: Reduce battery usage and heat depending on the status of temp + usb status (connect or disconnect)
#          * When battery capacity is greater than bat_limit, and battery temp is greater than temp_limit, then stop charging
#          * When phone is not connected to USB, then change CPU max scale freq to minimum.
#          * (OPTIONAL) When no USB connection for xxx hours, execute shut down command to reserve battery.



# default values, change this to suit your need
power_off_timer=3 # shut down after xxx hours of no USB connection, set to 0 to disable this.
sleep=5 # sleep timer, in seconds, how often you would like the script to query the system status.
temp_limit=460 # temp limit - 46 degree, match thermald.py, it stop charging when reach this temp level.
bat_limit=35 # battery limit (percentage), if battery capacity is lower than this then it will keep charging.
cpu_power_bat_limit=5 # when battery reach this capacity, we turn cpu freq back on prepare for a shutdown



# a few system optimisation, may only effect from next reboot
# Wi-Fi (scanning always available) off
settings put global wifi_scan_always_enabled 0
# disable notify the user of open networks.
settings put global wifi_networks_available_notification_on 0
# keep wifi on during sleep only when plugged in
settings put global wifi_sleep_policy 1
# disable nfc
LD_LIBRARY_PATH="" svc nfc disable



# function to loop through available CPUs
# @param $1 set to max when it's 1, set to min when it's 0
set_cpu_freq(){
  cd /sys/devices/system/cpu/
  for c in ./cpu[0-4]* ; do
    check_n_set_freq $1 ${c}
  done
}

# function to set CPU to max/min available frequency (max scaling only)
# @param $1 set to max when it's 1, set to min when it's 0
# @param $2 cpu name, e.g. cpu0, cpu1, cpu2. cpu3
check_n_set_freq() {
  cd /sys/devices/system/cpu/

  if [ $1 -eq "1" ]; then
    # get max cpu freq
    freq=`awk '{print $NF}' ./$2/cpufreq/scaling_available_frequencies`
  else
    # get min cpu freq
    freq=`awk '{print $1}' ./$2/cpufreq/scaling_available_frequencies`
  fi

  # set max/min freq to scaling_max_freq
  echo $freq > ./$2/cpufreq/scaling_max_freq
}

set_charging_status() {
  echo $1 > /sys/class/power_supply/battery/charging_enabled
}

####################################
######### logic start here #########
####################################

# when first execute

# set CPU freq to max
set_cpu_freq 1

# allow charging
set_charging_status 1

PREVIOUS=$(cat /sys/class/power_supply/usb/present)
timer=0
power_off_at=0

# calculate power_off_at value
if [ $power_off_timer -gt "0" ]; then
  ((power_off_at=60*60*power_off_timer/sleep))
fi

# loop every second
while [ 1 ]; do
  # retrieve values
  temp=$(cat /sys/class/power_supply/battery/temp)
  bat_now=$(cat /sys/class/power_supply/battery/capacity)
  charging_status=$(cat /sys/class/power_supply/battery/charging_enabled)

  # if temp is high AND we still have enough battery capacity, then we stop charging the battery
  if ([ $temp -gt $temp_limit ] && [ $bat_now -gt $bat_limit ]); then
    allow_charge=0
  else
    allow_charge=1
  fi

  # set battery charging status only when it's different then previous.
  if [ $charging_status -ne $allow_charge ]; then
    set_charging_status $allow_charge
  fi

  # current usb status
  CURRENT=$(cat /sys/class/power_supply/usb/present)

  # we set cpu back to original freq when usb is not charging
  # and bat is less than the limit
  # so when next time we boot up, it boot faster.
  if ([ $bat_now -le $cpu_power_bat_limit ] && [ $PREVIOUS -eq "0" ]); then
    set_cpu_freq 1
    PREVIOUS=1
  else
    # if USB status changed, we update CPU frequency accordingly.
    if [ $CURRENT -ne $PREVIOUS ]; then
      set_cpu_freq $CURRENT
      PREVIOUS=$CURRENT
    fi
  fi

  # update timer based on current usb status, reset it once it detect usb is online
  if [ $CURRENT -eq "0" ]; then
    ((timer=timer+1))
  else
    timer=0
  fi

  # if timer is greater than power_off_at timer, set cpu freq back to max and then shut down
  if ([ $power_off_at -gt "0" ] && [ $timer -gt $power_off_at ]); then
    set_cpu_freq 1
    reboot -p
  fi

  sleep $sleep

done