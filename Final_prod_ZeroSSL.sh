#!/bin/bash
#set -x

API_KEY="d26c350f24da603a5d9b84cf6dbeceb0"
API_ENDPOINT="https://api.zerossl.com/certificates"


CONFIG_DIR="/etc/nginx/conf.d"

my_public_ip="$(curl http://169.254.169.254/metadata/v1/reserved_ip/ipv4/ip_address)"

CERT_NAME="$my_public_ip"
RENEW_DAYS="7"


comment() {
    for CONFIG_FILE in "$CONFIG_DIR"/*.conf; do
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i 's/^ *return 301   https:\/\/\$host\$request_uri;/# &/' "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                echo "Successfully commented out the redirect line in $CONFIG_FILE"
            else
                echo "Failed to comment out the redirect line in $CONFIG_FILE"
            fi
        fi
    done
}


uncomment() {
    for CONFIG_FILE in "$CONFIG_DIR"/*.conf; do
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i 's/^# *return 301   https:\/\/\$host\$request_uri;/return 301   https:\/\/\$host\$request_uri;/' "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                echo "Successfully uncommented out the redirect line in $CONFIG_FILE"
            else
                echo "Failed to uncomment out the redirect line in $CONFIG_FILE"
            fi
        fi
    done
}


create_cert() {
    txt_file_name=$(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_url_https | split("/")[-1]')
    txt_file_content_array=($(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_content[]'))
    id=$(echo "$create_response" | jq -r '.id')

    echo "Certificate ID: $id"

    printf "%s\n" "${txt_file_content_array[@]}" > "$txt_file_name"

    echo "Created verification file: $txt_file_name with content:"
    cat "$txt_file_name"

    if sudo systemctl is-active --quiet nginx; then
        echo "Nginx service is active. Initiating HTTP file copy."
        move_http_file
    else
        echo "Nginx service is not active. Certificate creation aborted."
    fi
}

move_http_file() {
    LOCAL_FILE="$txt_file_name"
    HTTP_FILE_PATH="/usr/share/nginx/html/.well-known/pki-validation/"

    sudo mkdir -p "$HTTP_FILE_PATH"
    sudo cp "$LOCAL_FILE" "$HTTP_FILE_PATH"

    if [ $? -eq 0 ]; then
        echo "HTTP file copied successfully."
        comment
        sleep 2
        sudo systemctl reload nginx
        sleep 2
        certificate_verify
    else
        echo "File not copied. Operation failed."
    fi
}

certificate_verify() {
    verify_response=$(curl -s -X POST "$API_ENDPOINT/$id/challenges?access_key=$API_KEY" -d validation_method=HTTP_CSR_HASH)
    sleep 10

    verify_response_check=$(echo "$verify_response" | jq -r '.type')

    if [ "$verify_response_check" = "1" ]; then
        echo "Certificate validation successful. Downloading certificate."
        download_cert
    else
        echo "Failed to verify certificate. Skipping certificate download."
    fi
}


download_cert() {
    download_response=$(curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY")

    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."certificate.crt"' > "certificate.crt"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."ca_bundle.crt"' > "ca_bundle.crt"
    cat certificate.crt ca_bundle.crt >>certificate.crt


    sudo cp certificate.crt /etc/ssl/
    sudo cp private.key /etc/ssl/

    uncomment
    sleep 2
    sudo systemctl reload nginx
    sleep 2

    rm "$txt_file_name" "$CERT_NAME.csr" "private.key" "certificate.crt" "ca_bundle.crt"


    revoke_cert
}


revoke_cert() {
    revoke_response=$(curl -s -X POST "$API_ENDPOINT/${certificate_id}/revoke?access_key=$API_KEY&reason=Superseded")
        success_response=$(echo "${revoke_response}" | jq -r '.success')

    if [ "$success_response" = "1" ]; then
        echo "Certificate ${certificate_id} has been revoked."
    elif [ "$success_response" = "0" ]; then
        echo "Certificate ${certificate_id} could not be revoked."
        echo "API Response: ${revoke_response}"
    else
        echo "Failed to determine revocation status."
        echo "API Response: ${revoke_response}"
    fi
}

# Main script starts here

if [ -z "$CERT_NAME" ]; then
    echo "Certificate name not provided. Please provide a name/IP as an argument."
    exit 1
fi

list_response=$(curl -s -L -H "Accept: application/json" "$API_ENDPOINT?access_key=$API_KEY")

certificate_ids=$(echo "$list_response" | jq -r --arg common_name "$CERT_NAME" '
    .results[]
    | select(.common_name == $common_name and .status == "issued") | .id
')

if [ -z "$certificate_ids" ]; then
    echo "No issued certificates found for common name '$CERT_NAME'."
else
    for certificate_id in $certificate_ids; do

        response=$(curl -s -L -H "Accept: application/json" "${API_ENDPOINT}/${certificate_id}?access_key=${API_KEY}")

        echo "Certificate details for ID '$certificate_id':"
        #echo "$response"
        expiration_date=$(echo "$response" | jq -r '.expires')
        echo "The certificate expires: $expiration_date"
        current_date=$(date +%s)
        expiration_timestamp=$(date -d "$expiration_date" +%s)
        days_difference=$(( (expiration_timestamp - current_date) / 86400 ))
        echo "The certificate will expire in: $days_difference days"

        if [ $days_difference -lt $RENEW_DAYS ]; then
            echo "Certificate needs renewal."

         openssl req -new -newkey rsa:2048 -nodes -out "$CERT_NAME.csr" -keyout "private.key" -subj "/C=IN/ST=TNE/L=Lon/O=GH/OU=IPDomain/CN=$CERT_NAME" &>/dev/null
         create_response=$(curl -s -X POST "$API_ENDPOINT?access_key=$API_KEY" --data-urlencode certificate_csr@"$CERT_NAME.csr" -d certificate_domains="$CERT_NAME" -d certificate_validity_days=90)

          echo "The create_response: $create_response"
create_response_check=$(echo "$create_response" | jq -r '.type')

            echo "Create response type: $create_response_check"
            if [ "$create_response_check" = "1" ]; then
                create_cert
            else
                echo "Failed to create certificate. Skipping certificate creation."
            fi
        else
            echo "Certificate does not need renewal."
        fi
    done
fi
