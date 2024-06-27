#!/bin/bash

API_KEY="b2d6af5106dbafa24086ef72ec43ca16"
API_ENDPOINT="https://api.zerossl.com/certificates"
CERT_NAME="$1"

response=$(curl -s -H "Accept: application/json" "$API_ENDPOINT?access_key=$API_KEY")

print_certificate_details() {

    echo "$response" | jq -r '.results[] | "Name= \(.common_name)  Created Date= \(.created) Expires= \(.expires) Status= \(.status)"'
}
openssl req -new -newkey rsa:2048 -nodes -out "$CERT_NAME".csr -keyout "private".key -subj "/C=IN/ST=TNE/L=Lon/O=GH/OU=IPDomain/CN=$CERT_NAME" &>/dev/null

create_response=$(curl -s -X POST https://api.zerossl.com/certificates?access_key="$API_KEY" --data-urlencode certificate_csr@"$CERT_NAME".csr -d certificate_domains="$CERT_NAME" -d certificate_validity_days=90)

echo "Create_response: $create_response"


txt_file_name=$(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_url_https | split("/")[-1]')

txt_file_content_array=$(echo "$create_response" | jq -r --arg certname "$CERT_NAME" '.validation.other_methods[$certname].file_validation_content[]')
id=$(echo "$create_response" | jq -r '.id')

echo "id=$id"

txt_file_content=$(printf "%s\n" "${txt_file_content_array[@]}")


echo "$txt_file_content" > "$txt_file_name"


echo "Created TXT file: $txt_file_name with content:"
cat "$txt_file_name"

# Optionally, you can add a cleanup step to remove the file after use
# rm "$txt_file_name"

LOCAL_FILE=$txt_file_name
EC2_INSTANCE="ubuntu@$CERT_NAME:/var/www/html/.well-known/pki-validation/"


ssh -i /home/ubuntu/cert/prakash-test.pem ubuntu@$CERT_NAME 'sudo mkdir -p /var/www/html/.well-known/pki-validation'

scp -i /home/ubuntu/cert/prakash-test.pem $LOCAL_FILE $EC2_INSTANCE
sleep 10
#verify_api_endpoint="https://api.zerossl.com/certificates/$id/challenges"
verify_response=$(curl -s -X POST https://api.zerossl.com/certificates/"$id"/challenges?access_key="$API_KEY" -d validation_method=HTTPS_CSR_HASH)
echo "Verify response =$verify_response"

sleep 30

download_response=$(curl -s https://api.zerossl.com/certificates/"$id"/download/return?access_key="$API_KEY")

echo "Download Response: $download_response"
curl -s https://api.zerossl.com/certificates/"$id"/download/return?access_key="$API_KEY" | jq -r '."certificate.crt"' > "certificate".crt
curl -s https://api.zerossl.com/certificates/"$id"/download/return?access_key="$API_KEY" | jq -r '."ca_bundle.crt"' > "ca_bundle".crt

working_dir=$(pwd)

cat certificate.crt ca_bundle.crt >> certificate.crt

scp -i /home/ubuntu/cert/prakash-test.pem certificate.crt private.key ubuntu@$CERT_NAME:/etc/ssl

ssh -i /home/ubuntu/cert/prakash-test.pem ubuntu@$CERT_NAME 'sudo systemctl restart nginx'
