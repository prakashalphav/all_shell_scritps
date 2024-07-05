#!/bin/bash
#set -x
API_KEY="dop6d3af7c37d705e8a57a"
root_password="Ght0219@Madurai"
response_page1=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" "https://api.digitalocean.com/v2/droplets?page=1&per_page=200")

response_page2=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" "https://api.digitalocean.com/v2/droplets?page=2&per_page=200")

combined_response=$(jq -s '.[0].droplets + .[1].droplets' <<< "$response_page1 $response_page2")

droplet_names_without_index=$(echo "$combined_response" | jq -r '.[].name' | sort)
#echo " droplet_names_without_index: $droplet_names_without_index"

########################################################################################################

ssh_operations() {

    config_dir="/etc/nginx/conf.d"
    echo "Executing the conf file copying function..."
    if [ -n "$1" ]; then
    server_ip="$1"
    else
    read -p "Please enter the Droplet(server) Reserved IP for copying the conf file:" server_ip
    fi
    echo "Enter the conf file name:"
    read config_file_name
    echo "Enter the conf file content (use Ctrl+D twice to finish input):"
    config_file_content=$(</dev/stdin)
    echo "$config_file_content" > "$config_file_name"
    echo "$config_file_name"
    sleep 2
    sshpass -p "$password" ssh root@"$server_ip" "
    for file in \"$config_dir\"/*.conf; do
        if [ -f \"\$file\" ]; then
            filename=\$(basename \"\$file\")
            mv \"\$file\" \"$config_dir/\${filename}.bkp\"
            echo \"Moved \$file to \${filename}.bkp\"
        fi
    done
"
    sleep 1
    sshpass -p "$root_password" scp "$config_file_name" root@"$server_ip":/etc/nginx/conf.d/"$config_file_name"
    sleep 2
    output=$(sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no root@"$server_ip" 'nginx -t' 2>&1)

    if [[ "$output" == *"syntax is ok"* && "$output" == *"test is successful"* ]]; then
        echo "nginx configuration syntax is ok"


        sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no root@"$server_ip" 'sudo systemctl is-active --quiet nginx'

        if [ $? -eq 0 ]; then
            echo "Nginx service is active. Reloading nginx."
            sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no root@"$server_ip" 'sudo systemctl reload nginx'
        else
            echo "Nginx service is not active. Restarting nginx."
            sshpass -p "$root_password" ssh -o StrictHostKeyChecking=no root@"$server_ip" 'sudo systemctl restart nginx'
        fi
    else
        echo "nginx configuration test failed. Please check nginx configuration."
    fi
}


get_ip_details() {

  echo "Droplet IP search function executed"
  echo "Please enter the exact Droplet name get the Droplet's IP's details"
  read search_droplet_ip
required_droplet_ip=$(echo "$combined_response" | jq --arg search "$search_droplet_ip" '.[] | select(.name == $search) | "\(.name): Default Public IP = \(.networks.v4[-4].ip_address), Reserved IP = \(.networks.v4[-1].ip_address)"')

    if [ -n "$required_droplet_ip" ]; then
        echo "The droplet \"$search_droplet_ip\" and It's Ip details"
	echo "             "
        echo "$required_droplet_ip"
   else
        echo "No droplets found with name $search_droplet_ip"
    fi
}

droplet_search() {

    echo "Executing search function..."
    echo "Please enter the name would you like to search:"
    read search_droplet

  required_droplet=$(echo "$combined_response" | jq --arg search "$search_droplet" '.[] | select(.name | test($search; "i"))| .name')
    if [ -n "$required_droplet" ]; then
        echo " \"$search_droplet\" related droplets are:"
        echo "               "
        echo "$required_droplet" 
   else
        echo "No droplets found with name $search_droplet"
    fi
}



create_droplet() {
    echo "Executing the create function..."
    echo "Please enter the Droplet name for creating the new Droplet:"
    read droplet_name

    cloud_init=$(cat <<EOF
#cloud-config
chpasswd:
  list: |
    root:$root_password
  expire: False
EOF
)


create_droplet() {
    echo "Executing the create function..."
    echo "Please enter the Droplet name for creating the new Droplet:"
    read droplet_name

    create_response=$(curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{
        "name": "'"$droplet_name"'",
        "region": "sgp1",
        "size": "s-1vcpu-1gb",
        "image": "142244909",
        "user_data":"'"$cloud_init"'",
        "backups": false,
        "ipv6": false,
        "monitoring": false,
        "tags": ["'"$droplet_name"'", "GHT"],
        "vpc_uuid": "16eb342f-6b94-46f6-9a06-a108988cfe5f"
    }' \
    https://api.digitalocean.com/v2/droplets)


    echo "Create Droplet Response:"
    echo "$create_response"
    echo "The droplet creation is on progress, so please wait for 50 seconds"
    sleep 50
    droplet_id=$(echo "$create_response" | jq -r '.droplet.id')
    echo "$droplet_id"
    echo "Do you want to assign a reserved IP to this droplet? (yes: 'y', no: 'n')"
   # echo "a. Assign reserved IP"
   # echo "b. No need to assign reserved IP"
    read assign_option
    case $assign_option in
        y) assign_reserved_ip "$droplet_id" ;;
        n) echo "No reserved IP will be assigned." ;;
        *) echo "Invalid option. No action taken." ;;
    esac

}

assign_reserved_ip() {
    local droplet_id=$1
   assign_reserved_ip_response=$(curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" -d "{\"droplet_id\": $droplet_id}" "https://api.digitalocean.com/v2/reserved_ips")
   assigned_reserved_ip=$(echo $assign_reserved_ip_response |  jq -r '.reserved_ip.ip')
     if [ "$assigned_reserved_ip" = "null" ]; then
        echo "Reserved IP is not assigned. Please check the droplet and unassign the existing reserved IP."
   else

	ipv4=$(echo "$assign_reserved_ip_response" | jq -r '.reserved_ip.droplet.networks.v4[] | select(.type == "public") | .ip_address')
        echo "The assigned reserved IP is:"
        echo "$assigned_reserved_ip"
        echo "============================================================="
        echo "The droplet default public IP is:"
        echo "$ipv4"

	read ssh_option
    case $ssh_option in
        y) ssh_operations "$assigned_reserved_ip" ;;
        n) echo "No need for nginx configuration." ;;
        *) echo "Invalid option. No action taken." ;;
    esac
    fi
}
unassign_reserved_ip() {
    echo "Executing the create function..."
    echo "Please enter the droplet reserved ip to unsassign"
    read reserved_ip

unassign_reserved_ip_response=$(curl -X DELETE -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" "https://api.digitalocean.com/v2/reserved_ips/$reserved_ip")
 }

delete_droplet() {

    echo "Executing the create function..."
    echo "Please enter the Droplet name for deleting the droplet:"
    read delete_droplet_name
    delete_response=$( curl -X DELETE   -H "Content-Type: application/json"   -H "Authorization: Bearer $API_KEY"   "https://api.digitalocean.com/v2/droplets?tag_name=$delete_droplet_name")
    echo "$delete_response" >> delete_response.json
}

get_droplet() {
    echo "Executing the assinging Reserved IP function..."
    echo "Please enter the droplet name for assign the Reserved IP:"
   read search_exact_droplet
   droplet_id=$(echo "$combined_response" | jq -r ".[] | select(.name == \"$search_exact_droplet\") | .id")
    if [ -n "$droplet_id" ]; then
        echo "$droplet_id"
        assign_reserved_ip "$droplet_id"
    else
        echo "No droplets found with name $search_exact_droplet"
    fi
}

while true; do

echo "                 "
echo "                 "
# Main script starts here
echo "Welcome to the script!"

# Display options and read user input
echo "Select an option:"
echo "a. List the existing droplet with related name"
echo "b. Get the Droplet's IP details"
echo "c. Create the new droplet"
echo "d. Delete the existing droplet"
echo "e. Assign the Reserved IP to the droplet"
echo "f. Unassign the Reserved IP from the droplet"
echo "g. copy the nginx conf to the server"
echo "q. Quit"

read option

# Act based on user input
case $option in
    a) droplet_search ;;
    b) get_ip_details ;;
    c) create_droplet ;;
    d) delete_droplet ;;
    e) get_droplet;;
    f) unassign_reserved_ip;;
    g) ssh_operations;;
    q) echo "Exiting script..... .... ... .. . "; exit 0;; 
    *) echo "Invalid option. Please select a, b, or c ............." ;;
esac
done
