#!/bin/bash

# Prompt user for the domains
echo "Enter the domains (press Ctrl+D when done):"

# Read multiple lines of input into an array
mapfile -t DOMAINS

# Check if any domains are provided
if [ ${#DOMAINS[@]} -eq 0 ]; then
  echo "No domains provided. Exiting."
  exit 1
fi

# Print table header
printf "%-30s %-15s %-30s %-30s %-30s\n" "Domain Name" "Expiry Date" "Common Name (CN)" "Organisation (O)" "Days to Expiry"
printf "%-30s %-15s %-30s %-30s %-30s\n" "-----------" "-----------" "----------------" "----------------" "----------------"

# Loop through each domain and get the SSL certificate details
for DOMAIN in "${DOMAINS[@]}"; do
  OUTPUT=$(echo | openssl s_client -connect "$DOMAIN":443 -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates -subject -issuer)

  # Check if the output is empty
  if [ -z "$OUTPUT" ]; then
    printf "%-30s %-15s %-30s %-30s %-30s\n" "$DOMAIN" "Failed to retrieve SSL certificate" "" "" ""
  else
    # Extract notAfter date and format it
    EXPIRY_DATE=$(echo "$OUTPUT" | grep "notAfter=" | cut -d'=' -f2)
    FORMATTED_DATE=$(date -d "$EXPIRY_DATE" +"%b %d %Y")

    # Extract Common Name (CN) from subject
    COMMON_NAME=$(echo "$OUTPUT" | grep "subject=" | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\(.*\)/\1/p')

    # Extract Organization (O) from issuer
    ORGANIZATION=$(echo "$OUTPUT" | grep "issuer=" | sed -n 's/.*O[[:space:]]*=[[:space:]]*\(.*\)/\1/p')

    # Calculate the number of days to expiry
    EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_TIMESTAMP=$(date +%s)
    DAYS_TO_EXPIRY=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / 86400 ))

    # Prepare the message for days to expiry
    if [ "$DAYS_TO_EXPIRY" -le 30 ]; then
      DAYS_MESSAGE="This certificate will expire in $DAYS_TO_EXPIRY days"
    else
      DAYS_MESSAGE=""
    fi

    # Print the certificate information
    printf "%-30s %-15s %-30s %-30s %-30s\n" "$DOMAIN" "$FORMATTED_DATE" "$COMMON_NAME" "$ORGANIZATION" "$DAYS_MESSAGE"
  fi
done
