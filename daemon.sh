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
cmToInches=2.54
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
  #jsonRainfall=$(rtl_433 -F json -E Quit)
  #jsonRainfall=$(rtl_433 -F csv -E Quit)
  #jsonRainfall=$(rtl_433 -F json -M RGR968 -E quit)
  #jsonRainfall=$(rtl_433 -M RGR968 -E)
  jsonRainfall=$(rtl_433 -M RGR968 -E quit)
  echo "Rain Gauge JSON output: $jsonRainfall"
  #parsedOutput= JSON.parse($jsonRainfall)
  #rainfallTest=$(echo $jsonRainfall | python -c "import json, sys; [sys.stdout.write(x['rain_mm'] + '\n') for x in json.load(sys.stdin)]")
  #echo "rainfallTest: $rainfallTest"

  array=$(echo "$jsonRainfall" | jq -r 'to_entries[] | "[" + (.key|@sh) + "]=" + (.value | @sh)'
  #readarray -t array < <(sed -n '/{/,/}/{s/[^:]*:[^"]*"\([^"]*\).*/\1/p;}' $jsonRainfall)
  echo "Array: ${array[@]}"
  #rainfall=$(echo $jsonRainfall | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"Message\"][\"Consumption\"])/$cmToInches")
  rainfall=$(echo $jsonRainfall | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"total_rain\"])/$cmToInches")
  
  # Only do something if a reading has been returned
  if [ ! -z "$rainfall" ]; then
    echo "Total rain: $rainfall inches"
  else 
    echo "***NO RAINFALL READ***"
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

