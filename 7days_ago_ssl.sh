#!/bin/bash

API_KEY="d26c350f24da603a5d9b84cf6dbeceb0"
API_ENDPOINT="https://api.zerossl.com/certificates"

# Common name you want to search for
COMMON_NAME="104.248.99.62"

# Fetching list of certificates
list_response=$(curl -s -L -H "Accept: application/json" "$API_ENDPOINT?access_key=$API_KEY")

# Extracting certificate IDs based on common name, status, and expiration date
certificate_ids=$(echo "$list_response" | jq -r --arg common_name "$COMMON_NAME" '
    .results[]
    | select(.common_name == $common_name and .status == "issued") | .id
')

# Check if any issued certificates were found
if [ -z "$certificate_ids" ]; then
    echo "No issued certificates found for common name '$COMMON_NAME' that expire within 90 days."
else
    for certificate_id in $certificate_ids; do
        # Fetching certificate details
        response=$(curl -s -L -H "Accept: application/json" "${API_ENDPOINT}/${certificate_id}?access_key=${API_KEY}")

        echo "Certificate details for ID '$certificate_id':"
        #echo "$response"

        expiration_date=$(echo "$response" | jq -r '.expires')
        echo "The certificate expires: $expiration_date"
        current_date=$(date +%s)
        expiration_timestamp=$(date -d "$expiration_date" +%s)
        days_difference=$(( (expiration_timestamp - current_date) / 86400 ))
        echo " The certificate will expire in: $days_difference"
        if [ $days_difference -lt 90 ]; then
        ./script2.sh
        fi
    done
fi
