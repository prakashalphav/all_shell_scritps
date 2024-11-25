#!/bin/bash

# Path to the file containing instance IPs
instances_file="./instances.txt"

# SSH user
ssh_user="ecs-user"  # Replace with the correct user for your instances

# Path to private SSH key
ssh_key="/location/test.pem"

# Log file path
log_file="./status_httpd.log"

# Start logging
echo "=== HTTPD Update Script Started: $(date) ===" > "$log_file"

# Ensure the instances file exists
if [ ! -f "$instances_file" ]; then
  echo "Instances file $instances_file not found! Exiting." | tee -a "$log_file"
  exit 1
fi

# Read the IPs from the file
instances=($(cat "$instances_file"))

# Loop through all instances
for instance in "${instances[@]}"; do
  echo "Processing instance: $instance" | tee -a "$log_file"
  
  ssh -o StrictHostKeyChecking=no -i "$ssh_key" "$ssh_user@$instance" <<'EOF' 2>&1 | tee -a "$log_file"
    set -e  # Exit on error
    echo "Checking and upgrading httpd service on $(hostname)..."

    # Check if httpd is installed
    if ! rpm -q httpd &>/dev/null; then
      echo "httpd is not installed. Installing it..."
      sudo yum install -y httpd || { echo "Failed to install httpd"; exit 1; }
    else
      echo "httpd is installed. Checking for updates..."
    fi

    # Check if httpd is up to date
    if sudo yum check-update httpd &>/dev/null; then
      echo "httpd is already the latest version. Skipping..."
      exit 0
    fi

    # Update httpd
    echo "Updating httpd..."
    sudo yum update -y httpd || { echo "Failed to update httpd"; exit 1; }

    # Restart httpd service
    if sudo systemctl is-active --quiet httpd; then
      echo "httpd service is active. Restarting it..."
      sudo systemctl restart httpd || { echo "Failed to restart httpd"; exit 1; }
    else
      echo "httpd service is inactive. Starting it..."
      sudo systemctl start httpd || { echo "Failed to start httpd"; exit 1; }
    fi

    # Check service status
    if sudo systemctl is-active --quiet httpd; then
      echo "httpd service is running successfully."
    else
      echo "httpd service failed to start!" >&2
      exit 1
    fi
EOF

  # Check SSH exit status
  if [ $? -eq 0 ]; then
    echo "Instance $instance processed successfully." | tee -a "$log_file"
  else
    echo "Error occurred on instance $instance. Stopping further execution." | tee -a "$log_file"
    exit 1
  fi
done

echo "=== HTTPD Update Script Completed: $(date) ===" | tee -a "$log_file"

