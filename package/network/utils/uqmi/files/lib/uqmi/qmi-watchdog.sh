#!/bin/sh

. /usr/share/libubox/jshn.sh

DEVICE_PATH=$1
CHECK_INTERVAL=$2
DISCONNECTED_TIMEOUT=$3
CID_LIST=$4

while true; do
	oldifs="$IFS"
	IFS=","
	for cid in $CID_LIST; do
		IFS="$oldifs"

		# Reset for every CID
		timeout_counter=0

		while true; do
			sleep "$CHECK_INTERVAL"
			if [ "$timeout_counter" -gt "$DISCONNECTED_TIMEOUT" ]; then
				echo "Data / Network connection error exceeds timeout - restart interface now"
				return 1
			fi

			data_status="$(uqmi -t 1000 -s -d "$DEVICE_PATH" --set-client-id wds,$cid  --get-data-status)"
			registration_status=$(uqmi -s -d "$DEVICE_PATH" --get-serving-system 2>/dev/null | jsonfilter -e "@.registration" 2>/dev/null)

			json_init
			json_load "$(uqmi -s -d "$DEVICE_PATH" --uim-get-sim-state)"
			json_get_var card_application_state card_application_state

			if [ "$card_application_state" = "illegal" ]; then
				# This does not recover. We don't have to wait out the timeout.
				echo "SIM card in illegal state - restart interface now"
				return 1
			elif [ -z "$card_application_state" ]; then
				# No SIM Status. Either the next request succeeds or the SIM card
				# potentially needs to be power-cycled
				echo "Empty SIM card application status"
				let timeout_counter++
				continue
			elif [ "$data_status" != "\"connected\"" ]; then
				# PDP context might recover in case autoconnect is enabled
				# and still working. Give the modem a fair chance to recover.
				echo "PDP context not connected for CID $cid"
				let timeout_counter++
				continue
			elif [ "$registration_status" != "registered" ]; then
				# Sometimes Data status reports "connected" although
				# we are not registered to a mobile network.
				echo "No network registration"
				let timeout_counter++
				continue
			fi
		done
	done
done
