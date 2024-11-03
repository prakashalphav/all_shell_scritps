#!/bin/bash

# Set your Cloudflare email and API key
CLOUDFLARE_EMAIL="ght.network@golden-hippo.com"
CLOUDFLARE_API_KEY="5ade36d7a6c831df592457f86fc10cfafde1e"

echo "Enter domain names (press Enter after each, and type 'done' when finished):"

DOMAIN_NAMES=()

# Read domain names until 'done' is entered
while true; do
    read DOMAIN_NAME
    if [ "$DOMAIN_NAME" == "done" ]; then
        break
    fi
    DOMAIN_NAMES+=("$DOMAIN_NAME")
done

# Print header
printf "%-30s %-40s %-25s\n" "Domain" "Zone ID" "Proxy Read Timeout (s)"

# Loop through each domain name and fetch the zone ID and proxy_read_timeout
for DOMAIN_NAME in "${DOMAIN_NAMES[@]}"; do
    # Get the Zone ID
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN_NAME" \
    -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
    -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ "$ZONE_ID" != "null" ]; then
        # Get the proxy_read_timeout
        proxy_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/proxy_read_timeout" \
        -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
        -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
        -H "Content-Type: application/json")

        # Extract the proxy_read_timeout from the JSON response
        proxy_read_timeout=$(echo "$proxy_response" | jq -r '.result.value')

        # Output the domain name, Zone ID, and proxy_read_timeout in aligned format
        printf "%-30s %-40s %-25s\n" "$DOMAIN_NAME" "$ZONE_ID" "$proxy_read_timeout"
    else
        # Output if the domain is not found
        printf "%-30s %-40s %-25s\n" "$DOMAIN_NAME" "Not found" "N/A"
    fi
done
