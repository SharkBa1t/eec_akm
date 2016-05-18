#!/bin/bash
#1 May 2016

# TODO!!!!!!!!!!!!!!!!
# Subtract Baseline Stats - Uncomment code only
# Avoid writing to Min/Max if previous and next frequencies are same -Uncomment code only

#Parameters being considered - CPU utilizations 
#on 8 values 	
#		User processes (with no nice values)
#		System processes
#		User processes (with nice values)
#		Idle handlers
#		Waiting for I/O 	
#		Hardware Interrupts
#		Software Interrupts
#		Cumulative utlization

#Global variables
TIME=1				#How long to run this. Decides iterations.
LOG_FILE="/tmp/topdump"		#tmp contents get deleted on reboot
ITERATIONS=1
SCRIPT_FILE=`basename $0`
LOOKUP_FILE="./DVFS_LOOKUP"	#Our lookup file.
#Format 
#Line 1 - Frequency
#Line 2 - Parameters

FREQUENCY=0.1			#interval for top capture
R_FLAG=1			#Record mode - DEFAULT
M_FLAG=0			#Monitor mode
C_FLAG=0			#Capture mode
SLEEP_LEN=2			#Sleeping duration for Monitor mode

#Per-iteration variables for parameters
USER_CPU=0
SYSTEM_CPU=0
NICE_CPU=0
IDLE_CPU=0
IOWAIT_CPU=0
HWI_CPU=0
SWI_CPU=0
CPU_UTILIZATION=0

#Baseline variables for parameters 
BASE_USER_CPU=0
BASE_SYSTEM_CPU=0
BASE_NICE_CPU=0
BASE_IDLE_CPU=0
BASE_IOWAIT_CPU=0
BASE_HWI_CPU=0
BASE_SWI_CPU=0
BASE_CPU_UTILIZATION=0

#Switch variable to identify initial run
BASELINE=0

#Loop count used for calculating averages
LOOP_COUNT=0

#Variables for averages during workload run 
WLOAD_USER_CPU=0
WLOAD_SYSTEM_CPU=0
WLOAD_NICE_CPU=0
WLOAD_IDLE_CPU=0
WLOAD_IOWAIT_CPU=0
WLOAD_HWI_CPU=0
WLOAD_SWI_CPU=0
WLOAD_CPU_UTILIZATION=0

TARGET_FREQUENCY=800000		#Written to Min and Max in scaling cpufreq
AVAIL_FREQUENCY=0		#Holds the possible frequencies for system
declare -A FLT			#Lookup Table for target frequencies 
declare -A AVF			#Lookup Table for available frequencies


#Populate lookup table FLT
#Read from ./DVFS_LOOKUP  
function lookUp			
{
  MAX_FREQ=0			#Maximum possible frequency
  MIN_FREQ=0			#Minimum possible frequency

  LINE_COUNT=0
  LINE_ID=0

  MAX_FREQ=$( cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq )
  MIN_FREQ=$( cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq )

  AVAIL_FREQUENCY=$( cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies )

  #Populate lookup table AVF 
  for freqs in $AVAIL_FREQUENCY
  do
    freqs=$( echo $freqs | tr -d '\040\011\012\015' )
    AVF[$freqs]=1
  done 

  SKIP_FREQ=0
  prev_line=0

  #Sanity checks
  #Checked Maximum, Minimum and Supported frequencies
  #Unsupported are not populated into lookup table
  #Valid/Supported values added to FLT
  while read line
  do
    LINE_ID=$(($LINE_COUNT % 2))
    if [ $LINE_ID == 0 ]
    then
      line=$( echo $line | tr -d '\040\011\012\015' )
      prev_line=$line
      LINE_COUNT=$(($LINE_COUNT + 1))
      if [ $line -gt $MAX_FREQ ]
      then
        SKIP_FREQ=1
      fi
      if [[ ${AVF[$line]} -ne 1 ]]
      then 
        SKIP_FREQ=1
      fi
      if [ $line -lt $MIN_FREQ ]
      then
        SKIP_FREQ=1
      fi
      #echo "DEBUG "$line "SKIP "$SKIP_FREQ
    else
      line=$( echo $line | tr -d '\040\011\012\015' )
      LINE_COUNT=$(($LINE_COUNT + 1))
      if [ $SKIP_FREQ != 1 ]
      then
        #echo "PREV LINE "$prev_line $line
        FLT[$line]=$prev_line
      else
        #echo "Out of Range" $prev_line
        SKIP_FREQ=0
      fi
    fi
    if [ $LINE_COUNT == 2000 ]
    then 
      LINE_COUNT=0
    fi
  done < $LOOKUP_FILE
}	#end of function lookUp

#Sets up temp files for parameters
function setupTempFiles
{
  touch "$LOG_FILE"USER
  > "$LOG_FILE"USER
  touch "$LOG_FILE"SYSTEM
  > "$LOG_FILE"SYSTEM
  touch "$LOG_FILE"NICE
  > "$LOG_FILE"NICE
  touch "$LOG_FILE"IDLE
  > "$LOG_FILE"IDLE
  touch "$LOG_FILE"IOWAIT
  > "$LOG_FILE"IOWAIT
  touch "$LOG_FILE"HWI
  > "$LOG_FILE"HWI
  touch "$LOG_FILE"SWI
  > "$LOG_FILE"SWI
  touch "$LOG_FILE"CPU
  > "$LOG_FILE"CPU
}	#end of function setupTempFiles

#Top invocation and generating parameter averages
function topSampling		
{

  touch $LOG_FILE
  > $LOG_FILE
  touch "$LOG_FILE"00
  > "$LOG_FILE"00
  touch "$LOG_FILE"01
  > "$LOG_FILE"01
  touch "$LOG_FILE"02
  > "$LOG_FILE"02
  touch "$LOG_FILE"03
  > "$LOG_FILE"03

  # Top invoked in batch mode -b
  # for n iterations
  # with d frequency/sampling rate

  #More parameters should be added here
  top -b -n $ITERATIONS -d $FREQUENCY | \
    egrep -e "top|Tasks|Cpu|Mem|Swap|$SCRIPT_FILE" -s |\
    sed '/load/d'   |   \
    sed '/Tasks/d'  |   \
    sed '/Swap/d'   |   \
    sed 's/,/  /g'  |   \
    sed 's/)/  /g'  |   \
    sed 's/:/  /g'  |   \
    sed 's/ \+/ /g' |   \
    sort                \
    >> $LOG_FILE 

  split -dl $ITERATIONS $LOG_FILE $LOG_FILE

  #DO NOT REMOVE sleep. Files not generated quickly enough on the akm machine
  sleep 0.01
  #Sleep till files are generated

  #Process readings dont match averaged output. Disregarding process level entries
  #for top command and $SCRIPT_FILE

  USER_CPU=$(cut -d ' ' "$LOG_FILE"02 -f2 | paste -s -d + | bc)
  USER_CPU=$(echo "scale=0;$USER_CPU/$ITERATIONS" | bc)
  USER_CPU=$(($USER_CPU-$BASE_USER_CPU))


  SYSTEM_CPU=$(cut -d ' ' "$LOG_FILE"02 -f4 | paste -s -d + | bc)
  SYSTEM_CPU=$(echo "scale=0;$SYSTEM_CPU/$ITERATIONS" | bc)
  SYSTEM_CPU=$(($SYSTEM_CPU-$BASE_SYSTEM_CPU))


  NICE_CPU=$(cut -d ' ' "$LOG_FILE"02 -f6 | paste -s -d + | bc)
  NICE_CPU=$(echo "scale=0;$NICE_CPU/$ITERATIONS" | bc)
  NICE_CPU=$(($NICE_CPU-$BASE_NICE_CPU))


  IDLE_CPU=$(cut -d ' ' "$LOG_FILE"02 -f8 | paste -s -d + | bc)
  IDLE_CPU=$(echo "scale=0;$IDLE_CPU/$ITERATIONS" | bc)
  IDLE_CPU=$(($IDLE_CPU-$BASE_IDLE_CPU))

  IOWAIT_CPU=$(cut -d ' ' "$LOG_FILE"02 -f10 | paste -s -d + | bc)
  IOWAIT_CPU=$(echo "scale=0;$IOWAIT_CPU/$ITERATIONS" | bc)
  IOWAIT_CPU=$(($IOWAIT_CPU-$BASE_IOWAIT_CPU))


  HWI_CPU=$(cut -d ' ' "$LOG_FILE"02 -f12 | paste -s -d + | bc)
  HWI_CPU=$(echo "scale=0;$HWI_CPU/$ITERATIONS" | bc)
  HWI_CPU=$(($HWI_CPU-$BASE_HWI_CPU))


  SWI_CPU=$(cut -d ' ' "$LOG_FILE"02 -f14 | paste -s -d + | bc)
  SWI_CPU=$(echo "scale=0;$SWI_CPU/$ITERATIONS" | bc)
  SWI_CPU=$(($SWI_CPU-$BASE_SWI_CPU))

  ####TODO### Comment for demo
  #echo ""
  #echo "Iterations       "$ITERATIONS
  #echo "User CPU         "$USER_CPU
  #echo "System CPU       "$SYSTEM_CPU
  #echo "Nice CPU         "$NICE_CPU
  #echo "Idle CPU         "$IDLE_CPU
  #echo "IOWAIT CPU       "$IOWAIT_CPU
  #echo "HWI CPU          "$HWI_CPU
  #echo "SWI CPU          "$SWI_CPU

  #CPU utilization - Add all utilizations except for idle.

  CPU_UTILIZATION=$(echo\
    "scale=0;$USER_CPU+$SYSTEM_CPU+$NICE_CPU+$HWI_CPU+$SWI_CPU+$IOWAIT_CPU" |bc)
  #echo "Total Utilization" $CPU_UTILIZATION
  CPU_UTILIZATION=$(($CPU_UTILIZATION-$BASE_CPU_UTILIZATION))
}	#end of function topSampling

#Handle Ctrl-C
trap ctrl_c INT
ctrl_c() 
{
  echo " Exiting.."
  exit 1
}

#Print Help
function printHelpAndExit
{
  echo "akm_dvfs - Script to capture, record or monitor workload CPU utilizations and CPU frequencies"
  echo "Usage - #./akm_dvfs -[r/c/m/h] -t sample_rate -f logfile(r mode only) -s sleep duration(m mode only)"
  echo "Options are "
  echo "-r Record mode - Generates uitilzation averages for workload duration. Dumped to log file"
  echo "-f Specify different log file for record mode"
  echo "-c Capture mode - Capture utilization and operating frequencies. Dumped to lookup file"
  echo "-m Monitor mode - Monitor workload utilizations and change operating frequencies dynamically. Needs root shell"
  echo "-s Sleep duration of script for monitor mode"
  echo "-t Duration for sampling\(used by top\) the utilization. Default is 3s"
  echo "-h Show this help"
  echo "Press q to exit any mode."
  exit 1
}

#Record Mode 
#For Description - Refer function printHelpandExit
function recordMode
{
  echo "Record Mode."
  setupTempFiles
  while :
  do
    topSampling
    echo $USER_CPU >> "$LOG_FILE"USER
    echo $SYSTEM_CPU >> "$LOG_FILE"SYSTEM
    echo $NICE_CPU >> "$LOG_FILE"NICE
    echo $IDLE_CPU >> "$LOG_FILE"IDLE
    echo $IOAIT_CPU >> "$LOG_FILE"IOWAIT
    echo $HWI_CPU >> "$LOG_FILE"HWI
    echo $SWI_CPU >> "$LOG_FILE"SWI
    echo $CPU_UTILIZATION >> "$LOG_FILE"CPU
    LOOP_COUNT=$(($LOOP_COUNT+1))
    echo "LOOP COUNT" $LOOP_COUNT
    sleep 1
    read -s -t 1 -n 1 KEY
    if [[ $KEY = q ]]
    then
      echo "Quitting.."
      if [ $LOOP_COUNT == 0 ]
      then
        echo "Insufficient data. Lower the sleep value or allow more iterations"
        exit 1
      fi

      WLOAD_USER_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"USER)
      WLOAD_SYSTEM_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"SYSTEM)
      WLOAD_NICE_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"NICE)
      WLOAD_IDLE_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"IDLE)
      WLOAD_IOWAIT_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"IOWAIT)
      WLOAD_HWI_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"HWI)
      WLOAD_SWI_CPU=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"SWI)
      WLOAD_CPU_UTILIZATION=$(awk '{mean += $1} END {print \
        mean/NR}' "$LOG_FILE"CPU)
      echo ""
      echo "Workload Averages"
      echo "User Processes          "$WLOAD_USER_CPU
      echo "System Processes        "$WLOAD_SYSTEM_CPU
      echo "Niced User Processes    "$WLOAD_NICE_CPU
      echo "Idle Handlers           "$WLOAD_IDLE_CPU
      echo "I/O Completion wait     "$WLOAD_IOWAIT_CPU
      echo "Hardware Interrupts     "$WLOAD_HWI_CPU
      echo "Software Interrupts     "$WLOAD_SWI_CPU
      echo "Overall CPU Utilization "$WLOAD_CPU_UTILIZATION
      exit 1
    fi
  done      
}

#Capture Mode
#For Description - Refer function printHelpandExit
#Attempts to capture every 0.5 seconds
function captureMode
{
  echo "Capture Mode."
  setupTempFiles
  while :
  do
    topSampling
    CUR_FREQ=$( cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    echo $CUR_FREQ >> "$LOOKUP_FILE"
    echo $USER_CPU" "$SYSTEM_CPU\
      $NICE_CPU" "$IDLE_CPU\
      $IOWAIT_CPU" "$HWI_CPU\
      $SWI_CPU" "$CPU_UTILIZATION >> "$LOOKUP_FILE"
    read -t 1 -n 1 KEY
    if [[ $KEY = q ]]
    then
      echo "Quitting.."
      exit 1
    fi
    sleep 0.5
  done
}

#Monitor Mode
#For Description - Refer function printHelpandExit
function monitorMode
{
  echo "Monitor Mode."
  #Check for root
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root for Monitor Mode" 1>&2
    exit 1
  fi
  while :
  do
    topSampling
    TARGET_KEY=$(echo -e "$USER_CPU\
      $SYSTEM_CPU\
      $NICE_CPU\
      $IDLE_CPU\
      $IOWAIT_CPU\
      $HWI_CPU\
      $SWI_CPU\
      $CPU_UTILIZATION\n")
    TARGET_KEY=$( echo $TARGET_KEY | tr -d '\040\011\012\015' )
    TARGET_FREQUENCY=${FLT["$TARGET_KEY"]}
    TARGET_FREQUENCY=$( echo $TARGET_FREQUENCY | tr -d '\040\011\012\015' )
    if [[ -z "$TARGET_FREQUENCY" ]]
    then
      echo "No Target Frequency Found for these parameters!!!!"
    else
      echo "Target Frequency found - "$TARGET_FREQUENCY
      PREV_TARGET_FREQUENCY=$(cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
      echo "Previous Target Frequency "$PREV_TARGET_FREQUENCY

      # If target and current frequencies are the same?
      if [[ $PREV_TARGET_FREQUENCY -eq $TARGET_FREQUENCY ]]
      then 
	continue
      fi
	
      if [[ $PREV_TARGET_FREQUENCY -lt $TARGET_FREQUENCY ]]
      then
        echo $TARGET_FREQUENCY > "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
        echo $TARGET_FREQUENCY > "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
      else
        echo $TARGET_FREQUENCY > "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
        echo $TARGET_FREQUENCY > "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
      fi
      echo "Cat output of Min Freq"
      cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
      echo "Cat output of Max Freq"
      cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
      echo "Cat output of CPU Cur Freq"
      cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq
    fi    
    read -t 1 -n 1 KEY
    if [[ $KEY = q ]]
    then
      echo "Quitting.."
      exit 1
    fi
    sleep $SLEEP_LEN
  done
}


#MAIN execution starts here
#Parse command line options
while getopts "hmrcs:t:f:" optionname; do
  case "$optionname" in
    h) printHelpAndExit 0;;
  m) R_FLAG=0
    C_FLAG=0
    M_FLAG=1;;
  r) R_FLAG=1
    M_FLAG=0
    C_FLAG=0;; 
  c) R_FLAG=0
    M_FLAG=0
    C_FLAG=1;; 
  t) TIME=$OPTARG;;
s) SLEEP_LEN=$OPTARG;;
    f) LOG_FILE="$OPTARG";;
  [?]) printErrorHelpAndExit "$badOptionHelp";;
esac
done


#Calculate required number of iterations
ITERATIONS=$(echo "scale=0;$TIME/$FREQUENCY" | bc)
echo "Script File"  $SCRIPT_FILE
echo "Sampling Rate" $FREQUENCY
echo "Log File Name" "$LOG_FILE"

#Generate Lookup table from file
lookUp
echo "Lookup prepared"

# Setup Baseline
topSampling
if [ $BASELINE == 0 ]
then 
  BASE_USER_CPU=$USER_CPU
  BASE_SYSTEM_CPU=$SYSTEM_CPU
  BASE_NICE_CPU=$NICE_SPU
  BASE_IDLE_CPU=$IDLE_CPU
  BASE_IOWAIT_CPU=$IOWAIT_CPU
  BASE_HWI_CPU=$HWI_CPU
  BASE_SWI_CPU=$SWI_CPU
  BASE_CPU_UTILIZATION=$CPU_UTILIZATION
  BASELINE=1
fi
echo "Baseline established"

#Run record mode?
if [ $R_FLAG == 1 ]
then
  echo ""
  recordMode
fi

#Run capture mode?
if [ $C_FLAG == 1 ]
then
  echo ""
  captureMode
fi

#Run monitor mode?
if [ $M_FLAG == 1 ]
then
  echo ""
  monitorMode
fi

#End of file
