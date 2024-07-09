#!/bin/bash
day=$(date +'%d')
month=$(date +'%b')
year=$(date +'%Y')
hour=$(date +'%H')
minute=$(date +'%M')
minute_1=$(date +'%M' --date='-1 minute')
minute_2=$(date +'%M' --date='-2 minute')

current_timestamp="$day/$month/$year:$hour:$minute:"
one_minute_ago_timestamp="$day/$month/$year:$hour:$minute_1:"
two_minute_ago_timestamp="$day/$month/$year:$hour:$minute_2:"

CONFIG_DIR="/etc/apache2/sites-available/"

DDOS_THRESHOLD=200

for conf_file in "$CONFIG_DIR"*
do
    domain=$(basename "$conf_file" .conf)
    access_log=$(grep -E "CustomLog\s+\".*\"" "$conf_file" | awk '{print $2}' | tr -d '"')

    # Check if the access log file exists
    if [ -f "$access_log" ]; then
        two_minute_ago_log=$(grep "$two_minute_ago_timestamp" "$access_log")
        one_minute_ago_log=$(grep "$one_minute_ago_timestamp" "$access_log")
        current_log=$(grep "$current_timestamp" "$access_log")
       all_logs="$two_minute_ago_log $one_minute_ago_log $current_log"

        repeated_ips=$(echo "$all_logs" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort | uniq -c | sort -nr | awk -v threshold="$DDOS_THRESHOLD" '$1 >= threshold && $2 != "125.0.0.0" { print $2 }')

       # If repeated IPs are found, consider it a DDoS attack
        if [ ! -z "$repeated_ips" ]; then
            # Extract logs containing repeated IPs
            repeated_logs=$(echo "$all_logs" | grep -F "$repeated_ips")

           repeated_patterns=$(echo "$repeated_logs" | grep -o 'https\?://[^"/]*' | sort | uniq -c | sort -n)
            echo "Potential DDoS attack detected in access log for: $domain"
            echo "  Config file: $conf_file"
            echo "  Access log: $access_log"
	    echo " The DDOS attacking ip's are :"
	    echo "$repeated_ips"
            echo "  Repeated patterns:"
            echo "$repeated_patterns"
        fi
    else
        echo "Access log not found for $domain. Skipping..."  
    fi
done
