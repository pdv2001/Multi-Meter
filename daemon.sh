#!/bin/bash

# 9/20/19 - Make sure that consumption is being read and reboot if not.
#           Add READ_INTERVAL to allow configuration of how often the meter is read.  
#           NOTE: The Neptune 900 is only updated every 15 minutes anyway

# The interval at which the meter is read is now configureable
if [ -z "$READ_INTERVAL" ]; then
  echo "READ_INTERVAL not set, will read meter every 60 seconds"
  READ_INTERVAL=60
fi

# Watchdog timeout is now configureable
if [ -z "$WATCHDOG_TIMEOUT" ]; then
  echo "WATCHDOG_TIMEOUT not set, will reset if no reading for 30 minutes"
  WATCHDOG_TIMEOUT=30
fi


# Setup for Metric/CCF
UNIT_DIVISOR=10000
mmToInches=25.4
UNIT="CCF" # Hundred cubic feet
if [ ! -z "$METRIC" ]; then
  echo "Setting meter to metric readings"
  UNIT_DIVISOR=1000
  UNIT="Cubic Meters"
fi

# Kill this script (and restart the container) if we haven't seen an update in 30 minutes
# Nasty issue probably related to a memory leak, but this works really well, so not changing it
./watchdog.sh $WATCHDOG_TIMEOUT updated.log &

while true; do
  jsonOutput=$(rtl_433 -M RGR968 -E quit)
  echo "Rain Gauge JSON output: $jsonOutput"
  rainfall_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${1}p)
  #rainfall=$(echo $jsonOutput | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"total_rain\"])/$cmToInches")
  
  # Only do something if a reading has been returned
  if [ ! -z "$rainfall_mm" ]; then
    rainfall_in=$(printf %.1f\\n "$(($rainfall_mm/$mmToInches))")
    rainrate_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_rate_mm_h'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${1}p)
    rainrate_in=$(echo "$rainrate_mm/$mmToInches"|bc)
    echo "Total rain: $rainfall_in inches... Rate of fall: $rainrate_in inches/hr"
  else #Look for temperature
    temp_c=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'temperature_C'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${1}p)
    if [ ! -z "$temp_c" ]; then
      temp_f=$(echo "($temp_c*9/5)+32"|bc)
      echo "Temperature: $temp_f"
    else
      echo "***NO DATA***"
    fi
  fi

  # Suppress the very verbose output of rtl_tcp and background the process
#  rtl_tcp &> /dev/null &
#  rtl_tcp_pid=$! # Save the pid for murder later
#  sleep 10 #Let rtl_tcp startup and open a port

#  json=$(rtlamr -msgtype=r900 -filterid=$METERID -single=true -format=json)
#  echo "Meter info: $json"

  
#  consumption=$(echo $json | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"Message\"][\"Consumption\"])/$UNIT_DIVISOR")
    
  # Only do something if a reading has been returned
#  if [ ! -z "$consumption" ]; then
#    echo "Current consumption: $consumption $UNIT"


    # Replace with your custom logging code
#    if [ ! -z "$CURL_API" ]; then
#      echo "Logging to custom API"
#      # For example, CURL_API would be "https://mylogger.herokuapp.com?value="
#      # Currently uses a GET request
#      curl -L "$CURL_API$consumption"
#    fi

#    kill $rtl_tcp_pid # rtl_tcp has a memory leak and hangs after frequent use, restarts required - https://github.com/bemasher/rtlamr/issues/49
    sleep $READ_INTERVAL  # I don't need THAT many updates

    # Let the watchdog know we've done another cycle
#    touch updated.log
#  else 
#    echo "***NO CONSUMPTION READ***"
#  fi


done
