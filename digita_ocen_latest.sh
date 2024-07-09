#!/bin/bash
# Replace these variables with your values
API_TOKEN="<API_KEY>"
REGION="sgp1"
SIZE="s-1vcpu-1gb"
SNAPSHOT_NAME="IPDOMAIN_NEW_CENTOS7"
FIREWALL_NAME="GHT"
ROOT_PASSWORD="<password>"  # Set your secure password here
TIMEOUT=300  # Timeout in seconds
INTERVAL=5   # Interval in seconds
RETRY_COUNT=3  # Number of retries for SSH connection
LOCAL_FILE_PATH="/home/ubuntu/zero_ssl/zero_ssl.sh"  # Path to your local file
REMOTE_FILE_PATH="/opt/IPdomianrenewal.sh"  # Path on remote server
REMOTE_SCRIPT_PATH="/opt/IPdomianrenewal.sh"  # Path to the script on the remote server

#Getting previous Droplet Informations
FETCH_RESPONSE1=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $API_TOKEN" "https://api.digitalocean.com/v2/droplets?page=1&per_page=200")

FETCH_RESPONSE2=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $API_TOKEN" "https://api.digitalocean.com/v2/droplets?page=2&per_page=200")
COMBINED_RESPONSE=$(jq -s '.[0].droplets + .[1].droplets' <<< "$FETCH_RESPONSE1 $FETCH_RESPONSE2")
#echo "$COMBINED_RESPONSE"

SSH_OPERATION() {
  
  echo "Please enter the Mirror Domain for the Nginx conf"	
  read DOMAIN
  DOMAIN_PROXY=$(echo "$DOMAIN" | sed 's/\./\\./g')

    if [ -n "$1" ]; then
    FLOATING_IP="$1"
    else
   echo "Please enter Remote Server IP for change the Nginx conf:"
    read FLOATING_IP
    fi
# Function to execute SSH command with retries
ssh_with_retry() {
    local attempt=1
    local max_attempts=2
    while true; do
        if [ $attempt -gt $max_attempts ]; then
            echo "Failed to SSH into the Droplet after $max_attempts attempts."
            exit 1
        fi
        echo "Attempt $attempt: SSHing into Droplet..."
        sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$FLOATING_IP "$@"
        if [ $? -eq 0 ]; then
            echo "SSH connection successful."
            break
        fi
        echo "SSH connection failed. Retrying in 10 seconds..."
        sleep 10
        attempt=$((attempt + 1))
    done
}

# Remove existing configuration file if needed
ssh_with_retry "rm -rf /etc/nginx/conf.d/pbowin-new.conf"

# Update Nginx configuration file on the server
ssh_with_retry "cat > /etc/nginx/conf.d/$DOMAIN.conf <<'EOF'
server {
    listen      80;
    server_name  $FLOATING_IP;
    return 301   https://\$host\$request_uri;
}

# HTTPS CUSTOM PORT
server {
    listen             443 ssl;
    server_name        $FLOATING_IP;
    ssl_certificate     /etc/ssl/certificate.crt;
    ssl_certificate_key /etc/ssl/private.key;
    client_max_body_size 40M;
    location ~ ^/(.*)$ {
        add_header Set-Cookie \"targetip=$FLOATING_IP\";
        proxy_ssl_server_name on;
        proxy_set_header Accept-Encoding \"\";
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass https://www.$DOMAIN;
        proxy_redirect ~^https?://www\.$DOMAIN_PROXY(/.*)?$ https://\$host:\$1;
        sub_filter 'www.$DOMAIN' '$FLOATING_IP';
        sub_filter_types *;
        sub_filter_once off;
        sub_filter_last_modified on;
        ## Allow Southeastasia IP's ##
        include /etc/nginx/conf.d/countrywiseallow/*.conf;
        deny all;
    }
    access_log  /var/log/nginx/$DOMAIN.access.log;
    error_log   /var/log/nginx/$DOMAIN.error.log;
}
EOF"

# Restart Nginx
ssh_with_retry 'systemctl restart nginx'

# Copy local file to remote server
scp_with_retry() {
    local attempt=1
    local max_attempts=2
    while true; do
        if [ $attempt -gt $max_attempts ]; then
            echo "Failed to copy file to the Droplet after $max_attempts attempts."
            exit 1
        fi
        echo "Attempt $attempt: Copying file to Droplet..."
        sshpass -p "$ROOT_PASSWORD" scp -o StrictHostKeyChecking=no "$LOCAL_FILE_PATH" root@$FLOATING_IP:"$REMOTE_FILE_PATH"
        if [ $? -eq 0 ]; then
            echo "File copy successful."
            break
        fi
        echo "File copy failed. Retrying in 10 seconds..."
        sleep 10
        attempt=$((attempt + 1))
    done
}

# Execute the SCP command to copy the file
scp_with_retry

# Set execute permissions for the remote script
ssh_with_retry "chmod +x $REMOTE_SCRIPT_PATH"

# Install JQ
ssh_with_retry 'yum install jq -y'

# Execute the remote script
ssh_with_retry "bash $REMOTE_SCRIPT_PATH"

# Add the remote script to crontab to run every 12 hours
ssh_with_retry "echo '0 */12 * * * root /bin/bash $REMOTE_SCRIPT_PATH' > /etc/cron.d/remote_script"

echo "Droplet created, Floating IP assigned, file copied, Nginx configured, script executed, and crontab set successfully."
}

# Function to get IP details of a specific droplet
GET_IP_DETAILS() {
    echo "Droplet IP search function executed"
    echo "Please enter the exact Droplet name to get the Droplet's IP details:"
    read SEARCH_DROPLET_IP
    DROPLET_IP_RESPONSE=$(echo "$COMBINED_RESPONSE" | jq --arg search "$SEARCH_DROPLET_IP" '.[] | select(.name == $search) | "\(.name): Default Public IP = \(.networks.v4[-4].ip_address), Reserved IP = \(.networks.v4[-1].ip_address)"')

    if [ -n "$DROPLET_IP_RESPONSE" ]; then
        echo "The droplet \"$SEARCH_DROPLET_IP\" and its IP details:"
	echo "========================================================================================================"
	echo "                                                                                                       "
        echo "$DROPLET_IP_RESPONSE"
	echo "                                                                                                       "
	echo "========================================================================================================"
else
        echo "No droplets found with name \"$SEARCH_DROPLET_IP\""
    fi
}

# Function to search for droplets by name
DROPLET_SEARCH() {
    echo "Executing search function..."
    echo "Please enter the name you would like to search:"
    read SEARCH_DROPLET
   DROPLET_SEARCH_RESPONSE=$(echo "$COMBINED_RESPONSE" | jq --arg search "$SEARCH_DROPLET" '.[] | select(.name | test($search; "i")) | .name')

    if [ -n "$DROPLET_SEARCH_RESPONSE" ]; then
        echo "Droplets related to \"$SEARCH_DROPLET\":"
        echo "$DROPLET_SEARCH_RESPONSE"
    else
        echo "No droplets found with name \"$SEARCH_DROPLET\""
    fi
}


# Function to assign reserved IP to a droplet
ASSIGN_FLOATING_IP() {
    local DROPLET_ID=$1

# Create a Floating IP
echo "Creating Floating IP..."
create_floating_ip_response=$(curl -s -X POST "https://api.digitalocean.com/v2/floating_ips" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "region":"'"$REGION"'"
        }')

# Check if Floating IP creation was successful
if echo "$create_floating_ip_response" | jq -e '.floating_ip.ip' > /dev/null 2>&1; then
    FLOATING_IP=$(echo $create_floating_ip_response | jq -r '.floating_ip.ip')
    echo "Floating IP created successfully: $FLOATING_IP"
else
    echo "Error creating Floating IP: $(echo $create_floating_ip_response | jq -r '.message')"
    exit 1
fi

# Assign Floating IP to the Droplet
echo "Assigning Floating IP to the Droplet..."
assign_floating_ip_response=$(curl -s -X POST "https://api.digitalocean.com/v2/floating_ips/$FLOATING_IP/actions" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "type":"assign",
          "droplet_id":"'"$DROPLET_ID"'"
        }')

# Check if Floating IP assignment was successful
if echo "$assign_floating_ip_response" | jq -e '.action.status' > /dev/null 2>&1; then
    FLOATING_IP=$(echo $create_floating_ip_response | jq -r '.floating_ip.ip')
    echo "Floating IP assigned successfully."
else
    echo "Error assigning Floating IP: $(echo $assign_floating_ip_response | jq -r '.message')"
    exit 1
fi

# Add Droplet to Firewall
echo "Adding Droplet to Firewall..."
curl -s -X POST "https://api.digitalocean.com/v2/firewalls/$FIREWALL_ID/droplets" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "droplet_ids":["'"$DROPLET_ID"'"]
        }'

# Print Floating IP details
echo "Fetching Floating IP details..."
floating_ip_details=$(curl -s -X GET "https://api.digitalocean.com/v2/floating_ips/$FLOATING_IP" \
    -H "Authorization: Bearer $API_TOKEN")
    echo "1. CS confirmed the Floating IP, Proceed the Nginx Configuration"
    echo "2. CS requested to change the Floating IP, Proceed with change the Floating IP"
        read ssh_option
        case $ssh_option in
            1) SSH_OPERATION "$FLOATING_IP" ;;
            2) UNASSIGN_FLOATING_IP "$FLOATING_IP" "$DROPLET_ID" ;;
            *) echo "Invalid option. No action taken." ;;
        esac
}

# Function to unassign reserved IP from a droplet
UNASSIGN_FLOATING_IP() {
    FLOATING_IP=$1
    UNASSIGN_FLOATING_IP_RESPONSE=$(curl -X DELETE -H "Content-Type: application/json" -H "Authorization: Bearer $API_TOKEN" "https://api.digitalocean.com/v2/floating_ips/$FLOATING_IP")
    echo "$UNASSIGN_FLOATING_IP_RESPONSE"
    sleep 10
    ASSIGN_FLOATING_IP "$DROPLET_ID"

}


DROPLET_CREATE() {

 local_DROPLET_NAME=$1
# Get Snapshot ID
echo "Fetching snapshot ID..."
SNAPSHOT_ID=$(curl -s -X GET "https://api.digitalocean.com/v2/snapshots" \
    -H "Authorization: Bearer $API_TOKEN" | jq -r '.snapshots[] | select(.name == "'"$SNAPSHOT_NAME"'") | .id')

if [ -z "$SNAPSHOT_ID" ]; then
    echo "Error: Snapshot ID not found for name '$SNAPSHOT_NAME'"
    exit 1
fi

echo "Snapshot ID: $SNAPSHOT_ID"

# Get Firewall ID
echo "Fetching firewall ID..."
FIREWALL_ID=$(curl -s -X GET "https://api.digitalocean.com/v2/firewalls" \
    -H "Authorization: Bearer $API_TOKEN" | jq -r '.firewalls[] | select(.name == "'"$FIREWALL_NAME"'") | .id')

if [ -z "$FIREWALL_ID" ]; then
    echo "Error: Firewall ID not found for name '$FIREWALL_NAME'"
    exit 1
fi

echo "Firewall ID: $FIREWALL_ID"

# Cloud-init script to set root password
CLOUD_INIT=$(cat <<EOF
#cloud-config
chpasswd:
  list: |
    root:$ROOT_PASSWORD
  expire: False
EOF
)

# Create a Droplet from Snapshot with Password Authentication
echo "Creating Droplet from Snapshot..."
CREATE_DROPLET_RESPONSE=$(curl -s -X POST "https://api.digitalocean.com/v2/droplets" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
          "name":"'"$DROPLET_NAME"'",
          "region":"'"$REGION"'",
          "size":"'"$SIZE"'",
          "image":"'"$SNAPSHOT_ID"'",
          "user_data":"'"$CLOUD_INIT"'",
          "tags":["'"$DROPLET_NAME"'"]
        }')

# Check if Droplet creation was successful
if echo "$CREATE_DROPLET_RESPONSE" | jq -e '.droplet.id' > /dev/null 2>&1; then
    DROPLET_ID=$(echo $CREATE_DROPLET_RESPONSE | jq -r '.droplet.id')
    echo "Droplet ID: $DROPLET_ID"
else
    echo "Error creating Droplet: $(echo $CREATE_DROPLET_RESPONSE | jq -r '.message')"
    exit 1
fi

    # Wait for the Droplet to be active
echo "Waiting for the Droplet to become active..."
start_time=$(date +%s)
while [ $(curl -s -X GET "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" \
          -H "Authorization: Bearer $API_TOKEN" \
          | jq -r '.droplet.status') != "active" ]; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ $elapsed_time -ge $TIMEOUT ]; then
        echo "Timeout: Droplet is not active after $TIMEOUT seconds."
        exit 1
    fi
    echo "Droplet status: $(curl -s -X GET "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" \
          -H "Authorization: Bearer $API_TOKEN" | jq -r '.droplet.status')"
    sleep $INTERVAL
done
ASSIGN_FLOATING_IP $DROPLET_ID
}

DROPLET_NAME_MATCH() {

	
echo "Enter the Droplet name for creating the new droplet"	
read DROPLET_NAME
SEARCH_DROPLET_RESPONSE=$(echo "$COMBINED_RESPONSE" | jq --arg search "$DROPLET_NAME" '.[] | select(.name == $search) | .name') 

#echo "R1: $SEARCH_DROPLET_RESPONSE"
SEARCH_DROPLET_RESPONSE2=$(echo "$SEARCH_DROPLET_RESPONSE" | sed 's/^"\(.*\)"$/\1/')    

#echo "R2: $SEARCH_DROPLET_RESPONSE2"
echo "$SEARCH_DROPLET_REPONSE2"
if [ -z "$SEARCH_DROPLET_RESPONSE2" ]; then
    echo "The droplet name '$SEARCH_DROPLET_RESPONSE2' does not match the input name '$DROPLET_NAME'. Starting the new droplet creation."
    DROPLET_CREATE $DROPLET_NAME
elif [ "$SEARCH_DROPLET_RESPONSE2" = "$DROPLET_NAME" ]; then
    echo "The droplet name '$SEARCH_DROPLET_RESPONSE2' matches the input name '$DROPLET_NAME'. Please enter the new droplet name."
    DROPLET_NAME_MATCH
fi

}

echo "                      "
echo "                      "
# Main loop for user interaction
while true; do
    echo "Welcome to the script!"
    echo "Select an option:"
    echo "1.Create a new droplet"
    echo "2.Copy nginx conf to a server"
    echo "3.List existing droplets by name"
    echo "4.Get the Doplet IP details"
    echo "q. Quit"

    read option

    case $option in

	    1)DROPLET_NAME_MATCH ;;
	    2)SSH_OPERATION ;;
	    3)DROPLET_SEARCH ;;
            4)GET_IP_DETAILS ;;
            q) echo "Exiting script..."; exit 0 ;;
            *) echo "Invalid option. Please select a valid option (a-g or q)." ;;
    esac
done
