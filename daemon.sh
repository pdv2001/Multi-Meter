#!/bin/bash

# 10/31/19 - Taken from My-Water-Meter and after much trial and error, here we are

# The interval at which the meter is read is now configureable
if [ -z "$READ_INTERVAL" ]; then
  echo "READ_INTERVAL not set, will read meter every 60 seconds"
  READ_INTERVAL=60
fi

while true; do
  unset rainfall_in #Clear these for 
  unset temp_f      # inner loop

  while [ -z "$rainfall_in" -o -z "$temp_f" ]; do
  
    jsonOutput=$(rtl_433 -M RGR968 -E quit) #quit after signal is read so that we can process the data

    rainfall_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')

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
        # Currently uses a GET request
        #The "start" and "end" are hacks to get pass the readings into the Google web API!
        url_string=`echo "$CURL_API\"start=here&rainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f&end=here\"" | tr -d ' '`
        curl -L $url_string
      else
        echo "rainfall=$rainfall_in&rate=$rainrate_in&temperature=$temp_f"
      fi
    else
      sleep 5 # Sleep for 5 seconds before trying again
    fi
  done
    sleep $READ_INTERVAL  # I don't need THAT many updates
done
