#!/bin/bash

# 9/20/19 - Make sure that consumption is being read and reboot if not.
#           Add READ_INTERVAL to allow configuration of how often the meter is read.  
#           NOTE: The Neptune 900 is only updated every 15 minutes anyway

# The interval at which the meter is read is now configureable
if [ -z "$READ_INTERVAL" ]; then
  echo "READ_INTERVAL not set, will read meter every 60 seconds"
  READ_INTERVAL=60
fi

while true; do
  #jsonOutput=$(rtl_433 -M RGR968 -E quit) #Rain gauge signal was very random
  jsonOutput=$(rtl_433 -v -M RGR968 -T 2m00s)
  echo "Rain Gauge JSON output: $jsonOutput"
  rainfall_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
  #rainfall_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${1}p)
  #rainfall=$(echo $jsonOutput | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"total_rain\"])/$cmToInches")
  
  # Only do something if a reading has been returned
  if [ ! -z "$rainfall_mm" ]; then
    rainfall_in=`echo "$rainfall_mm 25.4" | awk '{printf"%.2f \n", $1/$2}'`
    rainrate_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_rate_mm_h'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
    rainrate_in=`echo "$rainrate_mm 25.4" | awk '{printf"%.2f \n", $1/$2}'`
    echo "Total rain: $rainfall_in inches... Rate of fall: $rainrate_in in/hr"
  else #Look for temperature
    temp_c=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'temperature_C'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
    if [ ! -z "$temp_c" ]; then
      temp_f=`echo "$temp_c" | awk '{printf"%.2f \n", $1*9/5+32}'`
      echo "Temperature: $temp_f"
    else
      echo "***NO DATA***"
    fi
  fi

  #Do we have both rainfall and temperature?
  if [ ! -z "$rainfall_in" -a ! -z "$temp_f" ]; then
    if [ ! -z "$CURL_API" ]; then
      echo "Logging to custom API"
      # For example, CURL_API would be "https://mylogger.herokuapp.com?value="
      # Currently uses a GET request
      url_string=`echo "$CURL_API\"rainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f\"" | tr -d ' '`
      #url_string=`echo "$CURL_APIrainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f" | tr -d ' '`
      echo $url_string
      curl -L $url_string
      #curl -L "$CURL_API\"rainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f\""
    else
      echo "rainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f"
    fi
  unset rainfall_in #Clear this for next time around
  unset temp_f      # and this
  else
    echo "No rainfall?"
  fi


    sleep $READ_INTERVAL  # I don't need THAT many updates

done
