#!/bin/bash
set -x

API_KEY="2c72219047d0b9b53fcd735aaced4b88"
API_ENDPOINT="https://api.zerossl.com/certificates"
my_public_ip="$(curl http://169.254.169.254/metadata/v1/reserved_ip/ipv4/ip_address)"
CERT_NAME=$my_public_ip

CONFIG_DIR="/etc/nginx/conf.d"


# Function to comment out redirect lines in Nginx configuration files
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

# Function to uncomment redirect lines in Nginx configuration files
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

# Function to create the certificate
create_cert() {
    txt_file_name=$(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_url_https | split("/")[-1]')
    txt_file_content_array=($(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_content[]'))
    id=$(echo "$create_response" | jq -r '.id')

    echo "Certificate ID: $id"

    # Create verification file
    printf "%s\n" "${txt_file_content_array[@]}" > "$txt_file_name"

    echo "Created verification file: $txt_file_name with content:"
    cat "$txt_file_name"

    # Check if Nginx is active
    if sudo systemctl is-active --quiet nginx; then
        echo "Nginx service is active. Initiating HTTP file copy."
        move_http_file
    else
        echo "Nginx service is not active. Certificate creation aborted."
    fi
}

# Function to move the verification file to Nginx web root
move_http_file() {
    LOCAL_FILE="$txt_file_name"
    HTTP_FILE_PATH="/usr/share/nginx/html/.well-known/pki-validation/"
   # HTTP_FILE_PATH="/var/www/html/.well-known/pki-validation/"

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

# Function to verify and download the certificate
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

# Function to download the certificate and install it
download_cert() {
    download_response=$(curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY")

    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."certificate.crt"' > "certificate.crt"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."ca_bundle.crt"' > "ca_bundle.crt"
    cat certificate.crt ca_bundle.crt >>certificate.crt

    # Copy certificate and key to appropriate locations
    sudo cp certificate.crt /etc/ssl/
    sudo cp private.key /etc/ssl/

    uncomment
    sleep 2
    sudo systemctl reload nginx
    sleep 2

    # Clean up temporary files
    rm "$txt_file_name" "$CERT_NAME.csr" "private.key" "certificate.crt" "ca_bundle.crt"
}

# Main script execution starts here

# Check if certificate name is provided
if [ -z "$CERT_NAME" ]; then
    echo "Certificate name not provided. Please provide a name/IP as an argument."
    exit 1
fi

# Generate CSR
openssl req -new -newkey rsa:2048 -nodes -out "$CERT_NAME.csr" -keyout "private.key" -subj "/C=IN/ST=TNE/L=Lon/O=GH/OU=IPDomain/CN=$CERT_NAME" &>/dev/null

# Request to create the certificate
create_response=$(curl -s -X POST "$API_ENDPOINT?access_key=$API_KEY" --data-urlencode certificate_csr@"$CERT_NAME.csr" -d certificate_domains="$CERT_NAME" -d certificate_validity_days=90)

create_response_check=$(echo "$create_response" | jq -r '.type')

echo "Create response type: $create_response_check"
if [ "$create_response_check" = "1" ]; then
    create_cert
else
    echo "Failed to create certificate. Skipping certificate creation."
fi
