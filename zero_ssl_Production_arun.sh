#!/bin/bash
set -x

API_KEY="d26c350f24da603a5d9b84cf6dbeceb0"
API_ENDPOINT="https://api.zerossl.com/certificates"
CERT_NAME="$1"
PASSWORD="$2"
REMOTE_CONFIG_DIR="/etc/nginx/conf.d"

# Command to modify .conf files remotely
comment=" \
    for CONFIG_FILE in $REMOTE_CONFIG_DIR/*.conf; do \
        if [ -f \"\$CONFIG_FILE\" ]; then \
          sed -i 's/^ *return 301   https:\/\/\$host\$request_uri;/# &/' \"\$CONFIG_FILE\"; \
            if [ \$? -eq 0 ]; then \
                echo \"Successfully commented out the redirect line in \$CONFIG_FILE\"; \
            else \
                echo \"Failed to comment out the redirect line in \$CONFIG_FILE\"; \
            fi; \
        fi; \
    done"

uncomment="\
    for CONFIG_FILE in $REMOTE_CONFIG_DIR/*.conf; do \
        if [ -f \"\$CONFIG_FILE\" ]; then \
         sed -i 's/^# *return 301   https:\/\/\$host\$request_uri;/return 301   https:\/\/\$host\$request_uri;/' \"\$CONFIG_FILE\"; \
            if [ \$? -eq 0 ]; then \
                echo \"Successfully uncommented out the redirect line in \$CONFIG_FILE\"; \
            else \
                echo \"Please check the server for HTTP to HTTPS redirection.Because failed to uncomment out the redirect line in \$CONFIG_FILE\"; \
            fi; \
        fi; \
    done"

# Function to create the certificate
create_cert() {
    txt_file_name=$(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_url_https | split("/")[-1]')
    txt_file_content_array=($(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_content[]'))
    id=$(echo "$create_response" | jq -r '.id')

    echo "id=$id"

    # Create verification file
    printf "%s\n" "${txt_file_content_array[@]}" > "$txt_file_name"

    echo "Created verification file: $txt_file_name with content:"
    cat "$txt_file_name"

    # Check if Nginx is active on remote server
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no root@"$CERT_NAME" 'sudo systemctl is-active --quiet nginx'

    # Check the exit status of the SSH command
    if [ $? -eq 0 ]; then
        echo "Nginx service is active. Initiating HTTP file copy."
        move_http_file
    else
        echo "Nginx service is not active or SSH command failed. Certificate creation aborted."
    fi
}

# Function to move the verification file
move_http_file() {
    LOCAL_FILE="$txt_file_name"
    EC2_INSTANCE="root@$CERT_NAME:/usr/share/nginx/html/.well-known/pki-validation/"

    # Copy file using SCP
    sshpass -p $PASSWORD scp "$LOCAL_FILE" "$EC2_INSTANCE"

    if [ $? -eq 0 ]; then
        echo "HTTP File Copied To The Domain Successfully."
	sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no root@$CERT_NAME "$comment"
	sleep 2
        sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no root@"$CERT_NAME" 'sudo systemctl reload nginx'
	sleep 2
        certificate_verify
    else
        echo "File not copied. SCP operation failed."
    fi
    sleep 5
}

# Function to verify and download the certificate
certificate_verify() {
    verify_response=$(curl -s -X POST "$API_ENDPOINT/$id/challenges?access_key=$API_KEY" -d validation_method=HTTP_CSR_HASH)
    #echo "Verify response: $verify_response"
    sleep 20

    verify_response_check=$(echo "$verify_response" | jq -r '.type')

    if [ "$verify_response_check" = "1" ]; then
        echo " The Certificate Downloading is Initiated "
        download_cert
    else
        echo "Bad verify response. Skipping certificate download."
    fi
}

# Function to download the certificate
download_cert() {
    download_response=$(curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY")

    #echo "Download Response: $download_response"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."certificate.crt"' > "certificate.crt"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."ca_bundle.crt"' > "ca_bundle.crt"
    cat certificate.crt ca_bundle.crt >> certificate.crt

    # Copy certificate and key to remote server
    sshpass -p $PASSWORD scp certificate.crt private.key "root@$CERT_NAME:/etc/ssl"
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no root@$CERT_NAME "$uncomment"
    sleep 2
    # Reload Nginx on remote server
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no root@"$CERT_NAME" 'sudo systemctl reload nginx'
    sleep 5

    # Clean up temporary files
    rm "$txt_file_name" "$CERT_NAME.csr" private.key certificate.crt ca_bundle.crt
}

# Main

# Check if certificate name is provided
if [ -z "$CERT_NAME" ]; then
    echo "Certificate name/IP not provided. Please provide a IP as an argument."
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
    echo "Bad Response. Skipping certificate creation."
fi
