#!/bin/bash

# 8/25/21  - Back to "-single=false"
# 8/25/21  - Try "-single=true"
# 8/25/21  - Allow scan of all nearby meters
# 2/14/21  - Allow for different device models for rain and temperature
# 2/12/21  - Make imperial/metric configurable for weather readings
# 2/5/21   - Make rtl_443 parameters configurable
# 11/18/19 - Use correct variable name for rain/temperature timer
# 11/17/19 - Time entire read cycle
# 11/10/19 - Reduce interval between successive rain gauge readings and wait 10s after killing rtl_tcp
# 11/10/19 - Echo 433 JSON output
# 11/10/19 - Handle thermometer/raingauge not being readable
# 11/9/19  - Make reading temperature/rain configurable
# 11/9/19  - Added support for up to three 900MHz meters
# 11/9/19  - Taken from Rain-Water

#See https://github.com/merbanan/rtl_433/pull/986

#$ git reset --hard HEAD; git pull; git push balena master --force

#-----------------------------------------------------------------------------------------------
#| This supports reading 3 different types of meter + rain gauge and thermometer               |
#| The following are configurable:                                                             |
#| Meter Scan:                                                                                 |
#|         METER_SCAN: Scan all meters (y/n)                                                   |
#|         MSG_TYPE:   Message type scanned (all, scm, scm+, idm, netidm, r900 and r900bcd)    |
#| Meter 1:                                                                                    |
#|         METER_1_API:      URL to which data will be posted                                  |
#|         METER_1_ID:       Meter ID                                                          |
#|         METER_1_TYPE:     Meter Type (gas, water, electric)                                 |
#|         METER_1_MSG_TYPE: Message type supported by meter(scm, r900, ...)                   |
#| Meter 2:                                                                                    |
#|         METER_2_API:      URL to which data will be posted                                  |
#|         METER_2_ID:       Meter ID                                                          |
#|         METER_2_TYPE:     Meter Type (gas, water, electric)                                 |
#|         METER_2_MSG_TYPE: Message type supported by meter(scm, r900, ...)                   |
#| Meter 3:                                                                                    |
#|         METER_3_API:      URL to which data will be posted                                  |
#|         METER_3_ID:       Meter ID                                                          |
#|         METER_3_TYPE:     Meter Type (gas, water, electric)                                 |
#|         METER_3_MSG_TYPE: Message type supported by meter(scm, r900, ...)                   |
#|                                                                                             |
#| METERS_METRIC: Convert meter readings to metric (y/n)                                       |
#|                                                                                             |
#| READ_RAIN: Read rain gauge (y/n)                                                            |
#| READ_TEMP: Read thermometer (y/n)                                                    |
#| WEATHER_METRIC: Metric vs Imperial (y/n)                                                    |
#| RTL_433_RAIN: RTL_433 parameter string for rain gauge                                       |
#| RTL_433_TEMP: RTL_433 parameter string for thermometer                                      |
#|                                                                                             |
#| READ_INTERVAL: Number of seconds between successive readings                                |
#| TIME_TO_WAIT: Number of seconds before marking instruments off-line                         |
#| WATCHDOG_TIMEOUT: Number of minutes without data before reboot                              |
#|                                                                                             |
#-----------------------------------------------------------------------------------------------

# rtl_443 device parameters are configurable
if [ -z "$RTL_433_RAIN" ]; then
  echo "RTL_443 parameter for rain gauge not set, using default: -M RGR968"
  RTL_433_RAIN=" -M RGR968 "
fi
if [ -z "$RTL_433_TEMP" ]; then
  echo "RTL_443 parameter for thermometer not set, using default: -M RGR968"
  RTL_433_TEMP=" -M RGR968 "
fi

# For weather: Should the measure be imperial rather than metric?
if [ -z "$WEATHER_METRIC" -o "$WEATHER_METRIC" = "n" ]; then
  echo "Weather readings are imperial"
  WEATHER_MEASURE=" -C customary "
else
  echo "Weather readings are metric"
  WEATHER_MEASURE=" -C si "
fi
  
# Are we reading a rain gauge?
if [ -z "$READ_RAIN" -o "$READ_RAIN" = "n" ]; then
  echo "Not reading rain"
  READ_RAIN="n"
else
  echo "Reading rain"
  READ_RAIN="y"
fi

# Are we reading a thermometer?
if [ -z "$READ_TEMP" -o "$READ_TEMP" = "n" ]; then
  echo "Not reading temperature"
  READ_TEMP="n"
else
  echo "Reading temperature"
  READ_TEMP="y"
fi

# The interval at which the meter is read is now configureable
if [ -z "$READ_INTERVAL" ]; then
  echo "READ_INTERVAL not set, will read meter every 60 seconds"
  READ_INTERVAL=60
fi

# The time to wait before marking thermometer or rain gauge off line (in seconds)
if [ -z "$TIME_TO_WAIT" ]; then
  echo "TIME_TO_WAIT not set, will mark instruments off line after 200 seconds"
  TIME_TO_WAIT=200
fi

# Watchdog timeout is now configureable
if [ -z "$WATCHDOG_TIMEOUT" ]; then
  echo "WATCHDOG_TIMEOUT not set, will reset if no reading for 30 minutes"
  WATCHDOG_TIMEOUT=30
fi

# Setup for Metric/CCF
UNIT_DIVISOR=10000
UNIT="CCF" # Hundred cubic feet
if [ ! -z "$METERS_METRIC" ]; then
  echo "Setting meter to metric readings"
  UNIT_DIVISOR=1000
  UNIT="Cubic Meters"
fi

# Kill this script (and restart the container) if we haven't seen an update in x minutes
# Nasty issue probably related to a memory leak, but this works really well, so not changing it
./watchdog.sh $WATCHDOG_TIMEOUT updated.log &

rain_offline="n"
temp_offline="n"

while true; do

  start=$SECONDS #Time how long one cycle takes
  
  # Suppress the very verbose output of rtl_tcp and background the process
  rtl_tcp &> /dev/null &
  rtl_tcp_pid=$! # Save the pid for murder later
  sleep 10 #Let rtl_tcp startup and open a port

  if [ "$METER_SCAN" = "y" ]; then
    #Scan all nearby meters
    echo "Scanning all nearby meters"
    json=$(rtlamr -msgtype=$MSG_TYPE -single=false -format=json)
    echo "Meters found: $json"
  fi

  if [ ! -z "$METER_1_ID" ]; then
    #1ST METER
    echo "Reading $METER_1_TYPE meter"
    json=$(rtlamr -msgtype=$METER_1_MSG_TYPE -filterid=$METER_1_ID -single=true -format=json)
    echo "$METER_1_TYPE meter info: $json"

    consumption=$(echo $json | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"Message\"][\"Consumption\"])/$UNIT_DIVISOR")

    # Only do something if a reading has been returned
    if [ ! -z "$consumption" ]; then
      echo "Current $METER_1_TYPE consumption: $consumption $UNIT"

      # Replace with your custom logging code
      if [ ! -z "$METER_1_API" ]; then
        echo "Logging $METER_1_TYPE consumption to custom API"
        # For example, CURL_API would be "https://mylogger.herokuapp.com?value="
        # Currently uses a GET request
        curl -L "$METER_1_API$consumption"
      fi
    # Let the watchdog know we've read something
    touch updated.log
    else 
      echo "***NO $METER_1_TYPE CONSUMPTION READ***"
    fi
  fi

  if [ ! -z "$METER_2_ID" ]; then
    #2ND METER
    echo "Reading $METER_2_TYPE meter"
    json=$(rtlamr -msgtype=$METER_2_MSG_TYPE -filterid=$METER_2_ID -single=true -format=json)
    echo "$METER_1_TYPE meter info: $json"

    consumption=$(echo $json | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"Message\"][\"Consumption\"])/$UNIT_DIVISOR")

    # Only do something if a reading has been returned
    if [ ! -z "$consumption" ]; then
      echo "Current $METER_2_TYPE consumption: $consumption $UNIT"

      # Replace with your custom logging code
      if [ ! -z "$METER_2_API" ]; then
        echo "Logging $METER_2_TYPE consumption to custom API"
        # For example, CURL_API would be "https://mylogger.herokuapp.com?value="
        # Currently uses a GET request
        curl -L "$METER_2_API$consumption"
      fi
    # Let the watchdog know we've read something
    touch updated.log
    else 
      echo "***NO $METER_2_TYPE CONSUMPTION READ***"
    fi
  fi

  if [ ! -z "$METER_3_ID" ]; then
    #3RD METER
    echo "Reading $METER_3_TYPE meter"
    json=$(rtlamr -msgtype=$METER_3_MSG_TYPE -filterid=$METER_3_ID -single=true -format=json)
    echo "$METER_1_TYPE meter info: $json"

    consumption=$(echo $json | python -c "import json,sys;obj=json.load(sys.stdin);print float(obj[\"Message\"][\"Consumption\"])/$UNIT_DIVISOR")

    # Only do something if a reading has been returned
    if [ ! -z "$consumption" ]; then
      echo "Current $METER_3_TYPE consumption: $consumption $UNIT"

      # Replace with your custom logging code
      if [ ! -z "$METER_3_API" ]; then
        echo "Logging $METER_3_TYPE consumption to custom API"
        # For example, CURL_API would be "https://mylogger.herokuapp.com?value="
        # Currently uses a GET request
        curl -L "$METER_3_API$consumption"
      fi
     # Let the watchdog know we've read something
    touch updated.log
   else 
      echo "***NO $METER_3_TYPE CONSUMPTION READ***"
    fi
  fi
  
  kill -9 $rtl_tcp_pid # rtl_tcp has a memory leak and hangs after frequent use, restarts required - https://github.com/bemasher/rtlamr/issues/49
  sleep 10 #Wait for kill signal (should probably wait longer!)
  
  ##RAIN GAUGE AND THERMOMETER
  start_rain=$SECONDS
  
  #If we are not reading rainfall or temperature set these values to 0
#  if [ -z "$READ_RAIN" ]; then
#    rainfall_in=0
#    rainrate_in=0
#  else
#    rainfall_in=''
  if [ "$READ_RAIN" = "n" ]; then
    rainfall=0
    rainrate=0
  else
    rainfall=''
  fi
#  if [ -z "$READ_TEMP" ]; then
#    temp_f=0
#  else
#    temp_f=''
  if [ "$READ_TEMP" = "n" ]; then
    temp=0
  else
    temp=''
  fi

  #while [ -z "$rainfall_in" -o -z "$temp_f" ]; do
  #Now that we are initializing rainfall and temperature to 0 if we are not reading them this could be simplified as above
#  while [ \( ! -z "$READ_RAIN" -a  -z "$rainfall_in" \) -o  \( ! -z "READ_TEMP" -a  -z "$temp_f" \) ]; do
  while [ \( "$READ_RAIN" = "y" -a "$rain_offline" = "n" -a  -z "$rainfall" \) -o  \( "READ_TEMP" = "y" -a "$temp_offline" = "n" -a  -z "$temp" \) ]; do
    if [ "$READ_RAIN" = "y" -a "$rain_offline" = "n" -a  -z "$rainfall" ]; then
    echo "Reading rainfall"
    #jsonOutput=$(rtl_433 -M RGR968 -E quit) #quit after signal is read so that we can process the data
    jsonOutput=$(rtl_433 $RTL_433_RAIN $WEATHER_MEASURE -E quit) #quit after signal is read so that we can process the data
    #jsonOutput=$(rtl_433 -h -E quit) #quit after signal is read so that we can process the data
    echo "Rain gauge output: $jsonOutput"

      #Check for rainfall
#      rainfall_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
      if [ -z "$WEATHER_METRIC" -o "$WEATHER_METRIC" = "n" ]; then
        #Working in imperial
        rainfall=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_in'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
      else
        rainfall=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_mm'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
      fi

      # Only do something if a reading has been returned
#      if [ ! -z "$rainfall_mm" ]; then
      if [ ! -z "$rainfall" ]; then
        echo "Rainfall was read"
        #rainfall_in=`echo "$rainfall_mm 25.4" | awk '{printf"%.2f \n", $1/$2}'`
        #Now get rate
        if [ -z "$WEATHER_METRIC" -o "$WEATHER_METRIC" = "n" ]; then
          #Working in imperial
          rainrate=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_rate_in_h'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
          echo "Total rain: $rainfall inches... Rate of fall: $rainrate in/hr"
        else
          rainrate=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_rate_mm_h'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
          echo "Total rain: $rainfall mm...  Rate of fall: $rainrate mm/hr"
        fi

        #rainrate_mm=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'rain_rate_mm_h'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
        #rainrate_in=`echo "$rainrate_mm 25.4" | awk '{printf"%.2f \n", $1/$2}'`
        let "time_taken = $SECONDS - $start_rain"
        echo "Reading rain took $time_taken seconds (Temperature: $temp)"
      fi
    fi

    if [ "$READ_TEMP" = "y" -a "$temp_offline" = "n" -a  -z "$temp" ]; then
      #Look for temperature
      #temp_c=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'temperature_C'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
      echo "Reading temperature"
      jsonOutput=$(rtl_433 $RTL_433_TEMP $WEATHER_MEASURE -E quit) #quit after signal is read so that we can process the data
      echo "Thermometer output: $jsonOutput"
      if [ -z "$WEATHER_METRIC" -o "$WEATHER_METRIC" = "n" ]; then
        #Working in imperial
        temp=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'temperature_F'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
        echo "Temperature: $temp F"
      else
        temp=$(echo $jsonOutput | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'temperature_C'\042/){print $(i+1)}}}' | tr -d '"' | sed -n '1p')
        echo "Temperature: $temp C"
      fi

     if [ ! -z "$temp" ]; then
        echo "Temperature was read"
        #temp_f=`echo "$temp_c" | awk '{printf"%.2f \n", $1*9/5+32}'`
        let "time_taken = $SECONDS - $start_rain"
        echo "Reading temperature took $time_taken seconds (Rainfall = $rainfall)"
      fi
    fi
    
    #Mark devices offline if no reading otherwise we just waste time waiting for them
    #This probably only works for the current cycle but at least it allows for one
    #reading if the other device has been marked off line
    #NEED SOME WAY OF RENABLING THEM
    let "time_taken = $SECONDS - $start_rain"
    if [ $time_taken -ge $TIME_TO_WAIT ]; then
      if [ -z "$rainfall" ]; then
        echo "***No rain measurement in $time_taken seconds. MARKING RAIN GAUGE UNAVAILABLE***"
        rain_offline="y"
        rainfall=0
        rainrate=0
      fi
      if [ -z "$temp" ]; then
        echo "***No temperature measurement in $time_taken seconds. MARKING THERMOMETER UNAVAILABLE***"
        temp_offline="y"
        temp=0
      fi
    fi
    
    #Do we have both rainfall and temperature?
    if [ ! -z "$rainfall" -a ! -z "$temp" ]; then
      if [ ! -z "$RAIN_API" ]; then
        echo "Logging to custom API"
        # Currently uses a GET request
        #The "start" and "end" are hacks to get pass the readings into the Google web API!
        url_string=`echo "$RAIN_API?value=\"start=here&rainfall=$rainfall&rate=$rainrate&temperature=$temp&readingrain=$READ_RAIN&readingtemp=$READ_TEMP&end=here\"" | tr -d ' '`
        echo "$url_string"
        curl -L $url_string
      else
        echo "rainfall=$rainfall & rate=$rainrate & temperature=$temp"
        let "time_taken = $SECONDS - $start_rain"
        echo "Reading rain and temperature took $time_taken seconds"
      fi
      #Reset for next time around
      echo "Resetting rain and temperature"
      rainfall=''
      temp=''
    else
      sleep 1 # Sleep for 1 seconds before trying again
    fi
  done
  let "time_taken = $SECONDS - start"
  echo "One cycle took $time_taken seconds"  
  sleep $READ_INTERVAL  # I don't need THAT many updates
  
done
