#!/bin/bash
set -x

API_KEY="ab846e72191e235e44de30589dab02c5"
API_ENDPOINT="https://api.zerossl.com/certificates"
CERT_NAME="$1"

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
    ssh -i /home/ubuntu/cert/prakash-test.pem ubuntu@"$CERT_NAME" 'sudo systemctl is-active --quiet nginx'

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
    EC2_INSTANCE="ubuntu@$CERT_NAME:/var/www/html/.well-known/pki-validation/"

    # Copy file using SCP
    scp -i /home/ubuntu/cert/prakash-test.pem "$LOCAL_FILE" "$EC2_INSTANCE"

    if [ $? -eq 0 ]; then
        echo "File copied successfully."
        certificate_verify
    else
        echo "File not copied. SCP operation failed."
    fi

    sleep 10
}

# Function to verify and download the certificate
certificate_verify() {
    verify_response=$(curl -s -X POST "$API_ENDPOINT/$id/challenges?access_key=$API_KEY" -d validation_method=HTTPS_CSR_HASH)
    echo "Verify response: $verify_response"
    sleep 20

    verify_response_check=$(echo "$verify_response" | jq -r '.type')

    if [ "$verify_response_check" = "1" ]; then
        download_cert
    else
        echo "Type is not 1. Skipping certificate creation."
    fi
}

# Function to download the certificate
download_cert() {
    download_response=$(curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY")

    echo "Download Response: $download_response"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."certificate.crt"' > "certificate.crt"
    curl -s "$API_ENDPOINT/$id/download/return?access_key=$API_KEY" | jq -r '."ca_bundle.crt"' > "ca_bundle.crt"
    cat certificate.crt ca_bundle.crt >> fullchain.pem

    # Copy certificate and key to remote server
    scp -i /home/ubuntu/cert/prakash-test.pem certificate.crt private.key "ubuntu@$CERT_NAME:/etc/ssl"

    # Reload Nginx on remote server
    ssh -i /home/ubuntu/cert/prakash-test.pem ubuntu@"$CERT_NAME" 'sudo systemctl reload nginx'
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
    echo "Type is not 1. Skipping certificate creation."
fi
