#!/bin/bash

#$echo off
WMBUSMETERS_METERS_PATH="/etc/wmbusmeters.d"
WMBUSMETERS_CONFIG_FILE="/etc/wmbusmeters.conf"
MQTT_TOPIC_STATE_INIT=""
MQTT_BROKER_URL="192.168.15.20"
MQTT_USER="mqtt_user"
MQTT_PASSWD="mqtt_user"
HA_DISCOVERY_TOPIC="homeassistant"
NO_EVAL="False"
PRINT_MSG="False"
WMBUSMETERS_VERSION="`wmbusmeters --version`"

#Extract from line shell MQTT topic state
MQTT_TOPIC_STATE_INIT=`grep -i "^shell=" $WMBUSMETERS_CONFIG_FILE` 

if [[ -z $MQTT_TOPIC_STATE_INIT ]]; then
	echo "Missing \"shell\" option in file $WMBUSMETERS_CONFIG_FILE terefore potential MQTT publisher is not set"
	exit 1
fi


if [[ $MQTT_TOPIC_STATE_INIT != *" -t "* ]] && [[ $MQTT_TOPIC_STATE_INIT == *"mosquitto_pub"*  ]] ; then
        echo "Missing \"-t\" option for mosquitto_pub in file $WMBUSMETERS_CONFIG_FILE"
        exit 1
fi

MQTT_TOPIC_STATE_INIT=${MQTT_TOPIC_STATE_INIT#*"-t"}

#echo $MQTT_TOPIC_STATE_INIT
MQTT_TOPIC_STATE_INIT=`echo $MQTT_TOPIC_STATE_INIT | cut -d ' ' -f 1`  #eg.  wmbusmeters/$METER_ID  or  homeassistant/sensor/$METER_NAME/state


if [[ $MQTT_TOPIC_STATE_INIT == *"METER_MEDIA"* ]]; then
	echo "Cannot use env \"METER_MEDIA\" becasue cannot determine at this stage media type"
	exit 0
fi

#echo $MQTT_TOPIC_STATE_INIT
#echo $METER_NAME

#exit 0

OPTSTRING=":m:noh"
unset PROCESS_ONLY_THIS_METER_FILE

while getopts ${OPTSTRING} opt; do
  case ${opt} in
	m)
		if ! [ -f $WMBUSMETERS_METERS_PATH/${OPTARG} ]; then
			echo "ERROR. File ${OPTARG} does not exist in  folder $WMBUSMETERS_METERS_PATH"
			exit 1
		fi
		echo "Processing only meter file: ${OPTARG}"
		PROCESS_ONLY_THIS_METER_FILE=${OPTARG}
		;;
	n)
		echo "No sending generated discovery msg to Home Assistant"
 		NO_EVAL="True"
		;;

	o)
		echo "Printing generated discovery msg to std output"
		PRINT_MSG="True"
		;;
	h)
		echo "List of options:"
		echo "-m Generate discovery msg only for meter file, without this option all available meters files are processed."
		echo "-n Not eval, not send discovery msg to HA, sens use together with option -o"
		echo "-o Print generated discovery mgs to std output (on screen), without this option no print on screen"
		exit 0
		;;

    :)
      echo "Option -${OPTARG} requires an argument."
      exit 1
      ;;
    ?)
      echo -e "Invalid option: -${OPTARG}. \nPlease check option -h for more details"
      exit 1
      ;;
  esac
done

#exit 0


#echo $WMBUSMETERS_VERSION

for filename in $WMBUSMETERS_METERS_PATH/*; do
	{
	#Processing only one file condidtion check
	if [[ ${#PROCESS_ONLY_THIS_METER_FILE} > 0 ]] && [[ ${filename} != ${WMBUSMETERS_METERS_PATH}/${PROCESS_ONLY_THIS_METER_FILE} ]] ; then continue; fi

	declare -A array_meter_fields=()
	declare -A array_description_meter_fields=() #array for attribut description for each field
	declare -a array_diagnostic_meter_fields=()  #array of fields without UoM for diagnostic section in HA MQTT device
	echo "Processing meter file: "$filename
	echo "Start programu ">>output.txt
	while IFS= read -r line; do
		#check 1st character is #
		if [[ ${line:0:1} != "#" ]] ; then
			{
			#STR="ABCDE=12345"
			var1=${line%=*} # ABCDE
			#echo $var1
			var2=${line#*=} # 12345
			#echo $var2
			}
		else
			{
			var1=""
			var2=""
			}
		fi

		if [[ $var1 == "identitymode" ]] && [[ $var2 == "full" ]] then
			echo "Cannot set identitymode=full in meeter file $filename because generated JSON, based on meter, and send as MQTT state will not match to MQTT discovery state topic!"
			exit 1
		fi

		if [[ $var1 == "name" ]] then METER_NAME=$var2; #echo $var2; 
		fi  #eg. CO_4
                if [[ $var1 == calculate_* ]] then  #eg   calculate_total_energy_gj=total_energy_consumption_kwh
			#echo $var1 #calculate_total_energy_gj
			temp=${var1#*_} #total_energy_g
			uom_temp=`echo $temp | rev | cut -f1-1 -d'_' | rev`
			#echo $uom_temp
			#array_meter_fields+=$var2; 
	                array_meter_fields+=([${temp}]=${uom_temp})
			array_description_meter_fields+=([${temp}]="Calculated field based on << ${var2} >> field(s)/formula(s).")
			#echo $temp
			#echo $var2
	                #array_UOM_fields+=([$MAP_KEY]=$MAP_VALUE)
			#array_meter_fields+=([$VAR_METER_FIELD]=${array_UOM_fields[$UOM_FIELD]})
			fi  #eg   calculate_total_energy_gj=total_energy_consumption_kwh
		if [[ $var1 == field_* ]] then  #eg   field_static_data=Some constant string
			temp=${var1#*_} #field_static_data
			#if [[ $temp == *"_"* ]]; then 
			#	echo "Static field $temp in meter file $filename cannot containg underscore \"_\" character in name becasue is treated as UoM"
			#	exit 1
			#fi
			#static_temp=`echo $temp | rev | cut -f1-1 -d'_' | rev`
			array_diagnostic_meter_fields+=(${temp})
			#array_meter_fields+=([${temp}]=${var2}})
			array_description_meter_fields+=([${temp}]="Static field configured in meter file.")
		fi
		if [[ $var1 == "id" ]] then  #eg. 67554654  in telegram but cannot use: 67782120.M=KAM.V=30.T=0c
			METER_ID="$(echo -e "${var2}" | tr -d '[:space:]')"
			#METER_ID=$var2
			#echo $METER_ID
			#ID=echo ${var2%.*} | tr -d '"' ; 
			#METER_SHORT_ID=${var2%.*}
			#remove potential double quote
			#METER_SHORT_ID="${METER_SHORT_ID//[\",]}"
			#MANUFACTER=${var2#*.}
			#echo $METER_ID
			#echo $MANUFACTER
			fi #eg. 67554654
                if [[ $var1 == "pollinterval" ]] then POOLINTERVAL=${var2::-1}; fi #eg. 600s
		if [[ $var1 == "driver" ]] then
			{
			METER_TYPE_LONG=$var2 #eg. /etc/wmbusmeters.d/aptmbusx.xmq:SERIAL_1:mbus
			#echo $METER_TYPE
	                while [[ $METER_TYPE_LONG == *['!':]* ]]; do
				#echo "I'm in the loop"
				METER_TYPE_LONG=${METER_TYPE_LONG%:*}
                	done
			#echo "Po loop: "$METER_TYPE
			CMD_LIST_METERS="/usr/bin/wmbusmeters --listmeters="
			CMD_LIST_METERS+=$METER_TYPE_LONG #eg.kamheat or elf2 or /etc/wmbusmeters.drivers.d/aptmbusna.xmq
			DRIVER_TYPE=$($CMD_LIST_METERS) #eg. line is  "elf2 HeatMeter buildin"
			DRIVER_TYPE=${DRIVER_TYPE#*" "} #eg. "HeatMeter buildin"
			DRIVER_TYPE=${DRIVER_TYPE%" "*} #eg." HeatMeter " with space
			DRIVER_TYPE="$(echo -e "${DRIVER_TYPE}" | tr -d '[:space:]')" #HeatMeter
			#DEVICE_CLASS not used in the code!!, is used array_DEVICE_CLASS later in code
			#DEVICE_CLASS=""
			case $DRIVER_TYPE in
				"HeatMeter")		DEVICE_CLASS="energy" ;;
				"WaterMeter")		DEVICE_CLASS="water" ;;
				"ElectricityMeter")	DEVICE_CLASS="energy";;
				"GasMeter") 		DEVICE_CLASS="energy";;
				"HeatCostAllocationMeter":) DEVICE_CLASS="energy";;
				"AutoMeter") 		DEVICE_CLASS="energy";;
				"TempHygroMeter") 	DEVICE_CLASS="TEMPERATURE";;
				"SmokeDetector") 	DEVICE_CLASS="";;
				"DoorWindowDetector":) 	DEVICE_CLASS="";;
				"PulseCounter") 	DEVICE_CLASS="";;
				"Repeater") 		DEVICE_CLASS="";;
				"HeatCoolingMeter") 	DEVICE_CLASS="energy";;
				"UnknownMeter") 	DEVICE_CLASS="";;
				"PressureSensor") 	DEVICE_CLASS="PRESSURE";;
				*) 			DEVICE_CLASS="" ;;
			esac

			#echo $DEVICE_CLASS

			#Normalize driver from eg. /etc/wmbusmeters.drivers.d/aptmbusna.xmq to aptmbusna.xmq
			METER_TYPE=$METER_TYPE_LONG
		        while [[ $METER_TYPE == *['!'/]* ]]; do
        	        	#echo "IN DRIVER="$METER_TYPE
                		METER_TYPE=${METER_TYPE#*/}
        		done

			case $METER_TYPE in #eg. kamheat, elf2
				"kamheat")	MANUFACTER="Kamstrup" ;;
				"elf2")		MANUFACTER="Apator" ;;
				"aptmbusna.xmq"|"aptmbusna") MANUFACTER="Apator" ;;
				*)		MANUFACTER="n/a" ;;
			esac
			}
		fi
	done < "$filename"
	HW_VERSION="n/a"

        declare -A array_UOM_fields=() # array_UOM_fields[#UOM from wmbusmeters eg 'gj',  #CATEGORY eg. Energy]
        #echo "`wmbusmeters --listunits`"
        while read -r line; do
		if [[ -z "$line" ]]; then continue; fi #empty line skip
		#echo $line
                if [[ $line == *" ─────"* ]]; then
                        MAP_VALUE=${line%" "*}
			#echo $MAP_VALUE #eg. Energy, Volume, Time
			continue
                fi
		MAP_KEY=$(echo ${line} |cut -d ' ' -f1)
		#echo "key: $MAP_KEY" #eg. gj
		#echo "value: $MAP_VALUE" #.eg. Energy
		array_UOM_fields+=([$MAP_KEY]=$MAP_VALUE)
        done < <(echo "`wmbusmeters --listunits`")

	#atrificial add  dbm UOM, missing UoM in wmbusmeters
	array_UOM_fields+=(["dbm"]="SignalStrength")

	#echo ${array_UOM_fields[kwh]}

        declare -A array_UOM_NORMALIZE_fields=()  #UoM from HA array_UOM_NORMALIZE_fields[#Key =wmbusmeterd UOM ,  #Value= HA UOM]
	declare -A array_DEVICE_CLASS=()   #type of sensor, Arrays[#Key= wmbusmeters UOM,   #Value = HA device class] 
	for i in "${!array_UOM_fields[@]}"
		do
		#echo "============================"
		#echo $i
		array_DEVICE_CLASS+=([$i]=$DEVICE_CLASS)
		case $i in
			# AmountOfSubstance 
			"mol") 		array_UOM_NORMALIZE_fields+=([$i]="mol") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        #  Amperage
                        "a") 		array_UOM_NORMALIZE_fields+=([$i]="A") && 		array_DEVICE_CLASS+=([$i]="CURRENT")  ;;
                        # Angle
                        "rad") 		array_UOM_NORMALIZE_fields+=([$i]="rad") && 		array_DEVICE_CLASS+=([$i]="") ;;
                        "dag") 		array_UOM_NORMALIZE_fields+=([$i]="dag") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        #  Apparent Energy
                        "kvah") 	array_UOM_NORMALIZE_fields+=([$i]="kvah") && 		array_DEVICE_CLASS+=([$i]="");;#HA missing
                        # Apparent Power
                        "kva") 		array_UOM_NORMALIZE_fields+=([$i]="VA") && 		array_DEVICE_CLASS+=([$i]="APPARENT_POWER");;
                        #  Dimensionless
                        "pct") 		array_UOM_NORMALIZE_fields+=([$i]="pct") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        "nr") 		array_UOM_NORMALIZE_fields+=([$i]="nr") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        "factor") 	array_UOM_NORMALIZE_fields+=([$i]="factor") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        "counter") 	array_UOM_NORMALIZE_fields+=([$i]="counter") && 	array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        # Energy
                        "wh") 		array_UOM_NORMALIZE_fields+=([$i]="Wh")  && 		array_DEVICE_CLASS+=([$i]="ENERGY") ;;
                        "mj") 		array_UOM_NORMALIZE_fields+=([$i]="MJ") && 		array_DEVICE_CLASS+=([$i]="ENERGY") ;;
                        "m3c") 		array_UOM_NORMALIZE_fields+=([$i]="m3c") && 		array_DEVICE_CLASS+=([$i]="ENERGY") ;;#NOT A ENERGY!!!
                        "kwh") 		array_UOM_NORMALIZE_fields+=([$i]="kWh") && 		array_DEVICE_CLASS+=([$i]="ENERGY") ;;
                        "gj") 		array_UOM_NORMALIZE_fields+=([$i]="GJ") && 		array_DEVICE_CLASS+=([$i]="ENERGY") ;;
                        #  Flow
                        "m3h") 		array_UOM_NORMALIZE_fields+=([$i]="m³/h") && 		array_DEVICE_CLASS+=([$i]="VOLUME_FLOW_RATE") ;;
                        "lh")		array_UOM_NORMALIZE_fields+=([$i]="L/min") && 		array_DEVICE_CLASS+=([$i]="VOLUME_FLOW_RATE") ;;#Need multiplle 60x
                        #  Frequency
                        "hz")		array_UOM_NORMALIZE_fields+=([$i]="Hz") && 		array_DEVICE_CLASS+=([$i]="FREQUENCY") ;;
                        # HCA
                        "hca")		array_UOM_NORMALIZE_fields+=([$i]="hca") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        # Lenght
                        "m")		array_UOM_NORMALIZE_fields+=([$i]="m") && 		array_DEVICE_CLASS+=([$i]="DISTANCE") ;;
                        #  LuminousIntensity
                        "cd")		array_UOM_NORMALIZE_fields+=([$i]="cd") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        # Mass
                        "kg")		array_UOM_NORMALIZE_fields+=([$i]="kg") && 		array_DEVICE_CLASS+=([$i]="WEIGHT") ;;
                        # PointInTime
                        "utc")		array_UOM_NORMALIZE_fields+=([$i]="utc") && 		array_DEVICE_CLASS+=([$i]="TIMESTAMP") ;;#HA missing
                        "ut")		array_UOM_NORMALIZE_fields+=([$i]="ut") && 		array_DEVICE_CLASS+=([$i]="TIMESTAMP") ;;#HA missing
                        "time")		array_UOM_NORMALIZE_fields+=([$i]="time") && 		array_DEVICE_CLASS+=([$i]="TIME") ;;#HA missing
                        "date")         array_UOM_NORMALIZE_fields+=([$i]="date") &&            array_DEVICE_CLASS+=([$i]="DATE") ;;
                        "datetime")	array_UOM_NORMALIZE_fields+=([$i]="datetime") && 	array_DEVICE_CLASS+=([$i]="TIMESTAMP") ;;
                        # Power
                        "w") 		array_UOM_NORMALIZE_fields+=([$i]="W") && 		array_DEVICE_CLASS+=([$i]="POWER") ;;
                        "m3ch") 	array_UOM_NORMALIZE_fields+=([$i]="m3ch") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        "kw") 		array_UOM_NORMALIZE_fields+=([$i]="kW") && 		array_DEVICE_CLASS+=([$i]="POWER") ;;
                        # Pressure
                        "pa") 		array_UOM_NORMALIZE_fields+=([$i]="Pa") && 		array_DEVICE_CLASS+=([$i]="PRESSURE") ;;
                        "bar") 		array_UOM_NORMALIZE_fields+=([$i]="bar") && 		array_DEVICE_CLASS+=([$i]="PRESSURE") ;;
                        # Reactive Energy
                        "kvarh") 	array_UOM_NORMALIZE_fields+=([$i]="kvarh") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        # Reactive Power
                        "kvar")		 array_UOM_NORMALIZE_fields+=([$i]="var") && 		array_DEVICE_CLASS+=([$i]="REACTIVE_POWER") ;;#Need multiple 1000x
                        # Relative Humidity
                        "rh") 		array_UOM_NORMALIZE_fields+=([$i]="%") && 		array_DEVICE_CLASS+=([$i]="HUMIDITY") ;;
                        # Temperature
                        "k") 		array_UOM_NORMALIZE_fields+=([$i]="K") && 		array_DEVICE_CLASS+=([$i]="TEMPERATURE") ;;
                        "f") 		array_UOM_NORMALIZE_fields+=([$i]="°F") && 		array_DEVICE_CLASS+=([$i]="TEMPERATURE") ;;
                        "c") 		array_UOM_NORMALIZE_fields+=([$i]="°C") && 		array_DEVICE_CLASS+=([$i]="TEMPERATURE") ;;
                        # Text
                        "text") 	array_UOM_NORMALIZE_fields+=([$i]="text") && 		array_DEVICE_CLASS+=([$i]="") ;;#HA missing
                        # Time
                        "y") 		array_UOM_NORMALIZE_fields+=([$i]="y") && 		array_DEVICE_CLASS+=([$i]="");;#HA missing
                        "s") 		array_UOM_NORMALIZE_fields+=([$i]="s") && 		array_DEVICE_CLASS+=([$i]="DURATION");;
                        "month") 	array_UOM_NORMALIZE_fields+=([$i]="month") && 		array_DEVICE_CLASS+=([$i]="");;#HA missing
                        "min") 		array_UOM_NORMALIZE_fields+=([$i]="min") && 		array_DEVICE_CLASS+=([$i]="");;#HA missing
                        "max") 		array_UOM_NORMALIZE_fields+=([$i]="max") && 		array_DEVICE_CLASS+=([$i]="");;#HA missing
                        "h") 		array_UOM_NORMALIZE_fields+=([$i]="h") && 		array_DEVICE_CLASS+=([$i]="DURATION");;
                        "d") 		array_UOM_NORMALIZE_fields+=([$i]="d") && 		array_DEVICE_CLASS+=([$i]="DURATION");;
                        # Voltage
                        "v") 		array_UOM_NORMALIZE_fields+=([$i]="V") && 		array_DEVICE_CLASS+=([$i]="VOLTAGE");;
                        # Volume
                        "m3") 		array_UOM_NORMALIZE_fields+=([$i]="m³") && 		array_DEVICE_CLASS+=([$i]="WATER");; #Can be also Volume
                        "l") 		array_UOM_NORMALIZE_fields+=([$i]="L") && 		array_DEVICE_CLASS+=([$i]="WATER");; #Can be also Volume
			"dbm") 		array_UOM_NORMALIZE_fields+=([$i]="dBm") && 		array_DEVICE_CLASS+=([$i]="SIGNAL_STRENGTH");;
			#no UOM like fabrication_no
			#*) array_UOM_NORMALIZE_fields+=([$i]="NO_UOM")&& array_DEVICE_CLASS+=([$i]="");; 
		esac
	done

	#declare -A array_meter_fields  #already declateted for search from meter files on beggining of code
	#declare -a array_diagnostic_meter_fields=()  #already declarated
	#echo "`wmbusmeters --listfields=$METER_TYPE_LONG`"   #return eg. "power_kw  The current power flowing."
	#declare -A array_description_meter_fields=() # Already decalrated
	while read -r line; do #loop for `wmbusmeters --listfields=$METER_TYPE_LONG`
		#echo $line
 		#if [[ "$line" == *"─"* ]]; then
		#	MAP_VALUE=${line%-*}
		#	echo "LINIA JEST"
		#fi
		#echo $MAP_VALUE
		#var1=${line%" "*} # ABCDE
		#array_meter_fields+=(${line%" "*})


                #1st part, extract description plus field name
                #VAR_DESCRIPRION=${line#*" "}

		VAR_DESCRIPRION="$(echo -e "${line#*" "}" | sed -e 's/^[[:space:]]*//')"

		array_description_meter_fields+=([$(echo ${line} |cut -d ' ' -f1)]=$VAR_DESCRIPRION)

		#2ndpart extract: field  namr plus UoM
		VAR_METER_FIELD=$(echo ${line} |cut -d ' ' -f1) #eg.: "power_kw"
		if [[ $line == *_* ]] then  #check is suffix, assume UoM field here
			if [[ $line == *"timestamp_"*  ]] then continue; fi #skip ther timestamps
			UOM_FIELD=${VAR_METER_FIELD##*_} #eg.: "kw"
			#cheking is on list UoM, if no add to diagnostic field
			#echo $UOM_FIELD
			#echo ${array_UOM_NORMALIZE_fields[$UOM_FIELD]}
			if [[ ${array_UOM_NORMALIZE_fields[$UOM_FIELD]} == ""  ]] then 
				#echo #Missig on UoM list, add whole field to diagnostic list
                         	array_diagnostic_meter_fields+=($VAR_METER_FIELD)
				continue
			fi

		else
			array_diagnostic_meter_fields+=($VAR_METER_FIELD)
			#echo $VAR_METER_FIELD
			continue
		fi
		#echo "=================="
		#echo $VAR_METER_FIELD
		#echo $UOM_FIELD
		array_meter_fields+=([$VAR_METER_FIELD]=${array_UOM_fields[$UOM_FIELD]})
	done < <(echo "`wmbusmeters --listfields=$METER_TYPE_LONG`")

	#echo "${array_meter_fields[max_power_kw]}"
	#echo "${array_meter_fields[total_energy_consumption_kwh]}"
	#echo "${array_meter_fields[@]}"
	#echo "${!array_meter_fields[@]}"

	#CMD="/usr/bin/mosquitto_pub -h 192.168.15.20 -t \"homeassistant/sensor/$DRIVER_TYPE/$METER_NAME/config\""

	#Generate Ddiscovery msg for UOM fields
        for i in "${!array_meter_fields[@]}"    #eg i=total_energy_consumption_kwh
		do
		#if [[ $i == "fabrication_no" ]] then continue; fi #skip fabrication_no #UPDATE: should no be there anymore
		#echo $i
		#$DRIVER_TYPE eg. HeatMeter
		#$METER_NAME eg. CO_4
		#i# eg. total_heat_consumption_kwh

		#CMD="/usr/bin/mosquitto_pub -h $MQTT_BROKER_URL -t \"$HA_DISCOVERY_TOPIC/sensor/$DRIVER_TYPE/$METER_NAME/config\""
                CMD="/usr/bin/mosquitto_pub -h $MQTT_BROKER_URL -t \"$HA_DISCOVERY_TOPIC/sensor/$METER_NAME/$i/config\""
                CMD+=" -m '{"

		#echo ${array_UOM_NORMALIZE_fields[${i##*_}]} # UoM like kWh
		#echo $i #full name of  field with uom wmbusmeters
		#case ${array_UOM_NORMALIZE_fields[${i##*_}]} in
		#	"datetime") CMD+=" \"value_template\" : \"{{ as_datetime(value_json.$i) }}\", ";; #\"{{ strptime(value_json.$i,\\\"%Y-%m-%d %H:%M\\\") }}\", ";;
                #       "date")     CMD+=" \"value_template\" : \"{{ strptime(value_json.$i,\\\"%Y-%m-%d\\\") }\", ";;
		#	*)          CMD+=" \"value_template\" : \"{{ value_json.$i }}\", \"unit_of_measurement\" : \"${array_UOM_NORMALIZE_fields[${i##*_}]}\", ";;
		#esac
		#CMD+="\"name\" : \"$i\", \"state_topic\" : \"homeassistant/sensor/$METER_NAME/state\", \"unique_id\" : \"${i}_${METER_ID}_${METER_TYPE}\", \"expire_after\" : \"$((2*$POOLINTERVAL+10))\", "

		MQTT_TOPIC_STATE=$MQTT_TOPIC_STATE_INIT
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_DEVICE/"$METER_DEVICE"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_ID/"$METER_ID"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_JSON/"$METER_JSON"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_MEDIA/"$METER_MEDIA"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TYPE/"$METER_TYPE"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_NAME/"$METER_NAME"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP/"$METER_TIMESTAMP"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_LT/"$METER_TIMESTAMP_LT"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_UT/"$METER_TIMESTAMP_UT"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_UTC/"$METER_TIMESTAMP_UTC"}"

		#echo $MQTT_TOPIC_STATE
		#echo "end==========================="

		CMD+="\"name\" : \"$i\", \"state_topic\" : \"$MQTT_TOPIC_STATE\", "
		CMD+="\"unique_id\" : \"${i}_${METER_ID}_${METER_TYPE}\", \"expire_after\" : \"$((2*$POOLINTERVAL+10))\", "

	#echo "================================"
	#echo $METER_NAME #CO_4

	#MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_NAME/"$METER_NAME"}"

	#echo "MQTT_TOPIC: \"$MQTT_TOPIC_STATE\""   #"homeassistant/sensor/$METER_NAME/state"
        #echo "MQTT_TOPIC: $MQTT_TOPIC_STATE"   #homeassistant/sensor/$METER_NAME/state
        #echo $CMD
        #echo " "


		state_class=""
		case ${array_DEVICE_CLASS[${i##*_}]} in
			"APPARENT_POWER") state_class="MEASUREMENT";;
			"AQI") state_class="MEASUREMENT";;
			"ATMOSPHERIC_PRESSURE") state_class="MEASUREMENT";;
			"BATTERY") state_class="MEASUREMENT";;
			"CO2") state_class="MEASUREMENT";;
			"CO") state_class="MEASUREMENT";;
			"CONDUCTIVITY") state_class="MEASUREMENT";;
			"CURRENT") state_class="MEASUREMENT";;
			"DATA_RATE") state_class="MEASUREMENT";;
			"DATA_SIZE") state_class="MEASUREMENT";;
			"DATE") state_class="MEASUREMENT";;
			"DISTANCE") state_class="MEASUREMENT";;
			"DURATION") state_class="MEASUREMENT";;
			"ENERGY")
				{
				state_class="TOTAL"
				CMD+="\"suggested_display_precision\" : \"3\", "  #set precisiont to 3 digits aftere decimal separator
				};;
			"ENERGY_STORAGE")
                                {
                                state_class="TOTAL"
                                CMD+="\"suggested_display_precision\" : \"3\", " #set precisiont to 3 digits aftere decimal separator
                                };;
			"ENUM") state_class="MEASUREMENT";; "FREQUENCY") state_class="MEASUREMENT";;
			"GAS") state_class="TOTAL";; "HUMIDITY") state_class="MEASUREMENT";;
			"ILLUMINANCE") state_class="MEASUREMENT";;
			"IRRADIANCE") state_class="MEASUREMENT";;
			"MOISTURE") state_class="MEASUREMENT";; "MONETARY") state_class="MEASUREMENT";;
			"NITROGEN_DIOXIDE") state_class="MEASUREMENT";; "NITROGEN_MONOXIDE") state_class="MEASUREMENT";;
			"NITROUS_OXIDE") state_class="MEASUREMENT";;
			"OZONE") state_class="MEASUREMENT";;
			"PH") state_class="MEASUREMENT";;
			"PM1") state_class="MEASUREMENT";;
			"PM25") state_class="MEASUREMENT";;
			"PM10") state_class="MEASUREMENT";;
			"POWER") state_class="MEASUREMENT";;
			"POWER_FACTOR") state_class="MEASUREMENT";;
			"PRECIPITATION") state_class="MEASUREMENT";;
			"PRECIPITATION_INTENSITY") state_class="MEASUREMENT";;
			"PRESSURE") state_class="MEASUREMENT";;
			"REACTIVE_POWER") state_class="MEASUREMENT";;
			"SIGNAL_STRENGTH")
				{
				state_class="MEASUREMENT"
				CMD+="\"enabled_by_default\" : \"False\", \"entity_category\" : \"diagnostic\", "   #RSSI move to diagnostic and disable by default
				};;
			"SOUND_PRESSURE") state_class="MEASUREMENT";;
			"SPEED") state_class="MEASUREMENT";;
			"SULPHUR_DIOXIDE") state_class="MEASUREMENT";;
			"TEMPERATURE") state_class="MEASUREMENT";;
			"TIMESTAMP") state_class="MEASUREMENT";;
			"VOLATILE_ORGANIC_COMPOUNDS") state_class="MEASUREMENT";;
			"VOLATILE_ORGANIC_COMPOUNDS_PARTS") state_class="MEASUREMENT";;
			"VOLTAGE") state_class="MEASUREMENT";;
			"VOLUME") state_class="TOTAL_INCREASING";;
			"VOLUME_FLOW_RATE") state_class="MEASUREMENT";;
			"VOLUME_STORAGE") state_class="TOTAL_INCREASING";;
			"WATER") state_class="TOTAL";;
			"WEIGHT") state_class="MEASUREMENT";;
			"WIND_SPEED") state_class="MEASUREMENT";;
		esac
                case ${array_UOM_NORMALIZE_fields[${i##*_}]} in
                        date)     CMD+="\"value_template\" : \"{{ strptime(value_json.$i,\\\"%Y-%m-%d\\\")        }}\",  \"device_class\" : \"${array_DEVICE_CLASS[${i##*_}]}\", ";;
                        datetime) CMD+="\"value_template\" : \"{{ value_json.$i }}\", ";;
                        # "datetime") CMD+="\"value_template\" : \"{{ strptime(value_json.$i,\\\"%Y-%m-%d %H:%M\\\") | as_timestamp() |  timestamp_custom(\\\"%Y-%m-%d %H:%M\\\", \\\"True\\\") }}\", \"device_class\" : \"${array_DEVICE_CLASS[${i##*_}]}\", ";;
			h)	    CMD+="\"value_template\" : \"{{ value_json.$i }}\", \"unit_of_measurement\" : \"${array_UOM_NORMALIZE_fields[${i##*_}]}\", ";; #\"device_class\" : \"${array_DEVICE_CLASS[${i##*_}]}\", ";;
                        *)          CMD+="\"value_template\" : \"{{ value_json.$i }}\", \"unit_of_measurement\" : \"${array_UOM_NORMALIZE_fields[${i##*_}]}\", \"state_class\" : \"$state_class\", \"device_class\" : \"${array_DEVICE_CLASS[${i##*_}]}\", ";;
                esac
 		#CMD+="\"device_class\" : \"${array_DEVICE_CLASS[${i##*_}]}\", "
		#CMD+="\"state_class\" : \"$state_class\", "
		#Device part
		CMD+="\"json_attributes_topic\" : \"$MQTT_TOPIC_STATE\", "
		CMD+="\"json_attributes_template\" :  \"{{ { \\\"Description\\\" : \\\"${array_description_meter_fields[$i]}\\\" } | tojson }}\", "
		CMD+="\"device\": {\"serial_number\" : \"$METER_ID\", \"manufacturer\" : \"$MANUFACTER\", \"identifiers\" : \"$METER_ID\", \"name\" : \"$METER_NAME\", \"model\" : \"$DRIVER_TYPE ($METER_TYPE)\" }, \"origin\" : {\"name\" : \"wmbusmeters\", \"support_url\" : \"https://github.com/wmbusmeters/wmbusmeters/\",\"sw_version\" : \"$WMBUSMETERS_VERSION\"}}'"
		CMD+=" -u $MQTT_USER -P $MQTT_PASSWD"
        if [ $PRINT_MSG == "True" ]; then echo ""; echo ${CMD}; fi
        if [ $NO_EVAL == "False" ]; then eval $CMD; echo -e "Discovery messages has been send to Home Assistant for field "$i; fi
	done

	#Discovery for diagnostic fields
        #add fabrication_no

	#array_diagnostic_meter_fields+=("fabrication_no")
	for i in "${!array_diagnostic_meter_fields[@]}"    #index array, eg. id
                do
                #$DRIVER_TYPE eg. HeatMeter
                #$METER_NAME eg. CO_4
                #i# eg. id

                #CMD="/usr/bin/mosquitto_pub -h $MQTT_BROKER_URL -t \"$HA_DISCOVERY_TOPIC/sensor/$DRIVER_TYPE/$METER_NAME/config\""
                CMD="/usr/bin/mosquitto_pub -h $MQTT_BROKER_URL -t \"$HA_DISCOVERY_TOPIC/sensor/$METER_NAME/${array_diagnostic_meter_fields[$i]}/config\""
                CMD+=" -m '{\"entity_category\" : \"diagnostic\", \"name\" : \"${array_diagnostic_meter_fields[$i]}\", "
		case ${array_diagnostic_meter_fields[$i]} in
			"timestamp")
				{
				TEMP_DEVICE_CLASS="timestamp"
				CMD+="\"device_class\": \"$TEMP_DEVICE_CLASS\", "
				#CMD+="\"unit_of_measurement\" : \"${array_UOM_NORMALIZE_fields[${i##*_}]}\" ,\"state_class\" : \"measurement\", "
				CMD+="\"value_template\" : \"{{ value_json.${array_diagnostic_meter_fields[$i]} | as_datetime() }}\" , \"enabled_by_default\" : \"True\", "
                                #CMD+="\"value_template\" : \"{{ (now() - value_json.${array_diagnostic_meter_fields[$i]} | float) | round(1) }}\" , \"enabled_by_default\" : \"True\", "

				};;
			"status") CMD+="\"value_template\" : \"{{ value_json.${array_diagnostic_meter_fields[$i]} }}\" , \"enabled_by_default\" : \"True\", ";;
			*) 	  CMD+="\"value_template\" : \"{{ value_json.${array_diagnostic_meter_fields[$i]} }}\" , \"enabled_by_default\" : \"False\", ";;
		esac
		#CMD+="\"device_class\": \"$TEMP_DEVICE_CLASS\", \"unit_of_measurement\" : \"${array_UOM_NORMALIZE_fields[${i##*_}]}\" ,\"state_class\" : \"measurement\", "
		#CMD+=" \"state_topic\": \"homeassistant/sensor/$METER_NAME/state\", \"unique_id\": \"${array_diagnostic_meter_fields[${i}]}_${METER_ID}_${METER_TYPE}\", \"expire_after\":\"$((2*$POOLINTERVAL+10))\", "

                MQTT_TOPIC_STATE=$MQTT_TOPIC_STATE_INIT
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_DEVICE/"$METER_DEVICE"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_ID/"$METER_ID"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_JSON/"$METER_JSON"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_MEDIA/"$METER_MEDIA"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TYPE/"$METER_TYPE"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_NAME/"$METER_NAME"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP/"$METER_TIMESTAMP"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_LT/"$METER_TIMESTAMP_LT"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_UT/"$METER_TIMESTAMP_UT"}"
		MQTT_TOPIC_STATE="${MQTT_TOPIC_STATE/\$METER_TIMESTAMP_UTC/"$METER_TIMESTAMP_UTC"}"


                CMD+=" \"state_topic\" : \"$MQTT_TOPIC_STATE\", \"unique_id\" : \"${array_diagnostic_meter_fields[${i}]}_${METER_ID}_${METER_TYPE}\", \"expire_after\" : \"$((2*$POOLINTERVAL+10))\", "

		#device part
                CMD+="\"json_attributes_topic\" : \"$MQTT_TOPIC_STATE\", "
                CMD+="\"json_attributes_template\" :  \"{{ { \\\"Description\\\" : \\\"${array_description_meter_fields[${array_diagnostic_meter_fields[$i]}]}\\\" } | tojson }}\", "
		CMD+=" \"device\": {\"serial_number\" : \"$METER_ID\", \"manufacturer\" : \"$MANUFACTER\", \"identifiers\" : \"$METER_ID\", \"name\" : \"$METER_NAME\", \"model\" : \"$DRIVER_TYPE ($METER_TYPE)\" }, \"origin\" : {\"name\" : \"wmbusmeters\", \"support_url\" : \"https://github.com/wmbusmeters/wmbusmeters/\",\"sw_version\" : \"$WMBUSMETERS_VERSION\"}}'"
                CMD+=" -u $MQTT_USER -P $MQTT_PASSWD"

        if [ $PRINT_MSG == "True" ]; then echo ""; echo $CMD; fi
        if [ $NO_EVAL == "False" ]; then eval $CMD; echo -e "Discovery messages has been send to Home Assistant for field "${array_diagnostic_meter_fields[$i]}; fi
        done

	sleep 0.5
	}
done
