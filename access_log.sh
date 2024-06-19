#!/bin/bash

text_httpd_logs() {

     httpd_access_dir="/home/ubuntu/access_zip/var/log/httpd/"
     from_days_to_get_logs="7"
     to_days_to_get_logs="14"

    for access_log_zip in "$httpd_access_dir"access_log*; do
        if [ -f "$access_log_zip" ]; then
            filename=$(basename "$access_log_zip")
            log_file="/home/ubuntu/log_file/${filename}.txt"
            echo -n > "$log_file"
            for (( j="$to_days_to_get_logs";j>="$from_days_to_get_logs"; j-- )); do
                zip_date=$(date -d "$j days ago" '+%d/%b/%Y')
                echo "$zip_date"
		all_logs=$(grep -E "$zip_date" "$access_log_zip" | sed 's/^[ \t]*//;s/[ \t]*$//')
                if [ -n "$all_logs" ]; then
                echo "$all_logs" >> "$log_file"
                fi
            done
            echo "Created $log_file"
        else
            echo "No log files detected in $httpd_access_dir"
        fi
    done
}

text_httpd_logs

# Define the function to zip all txt files older than 7 days to 30 days in a specified directory
zip_text_files() {

    log_directory="/home/ubuntu/log_file"

    if [ -d "$log_directory" ]; then
        find "$log_directory" -type f -name "*.txt" -mtime -1 -print0 |
        while IFS= read -r -d '' file; do
            gzip "$file" -f
            if [ $? -eq 0 ]; then
                echo "Compressed '$file' to '$file.gz'"
            else
                echo "Failed to compress '$file'"
            fi
        done
    else
        echo "Logs directory '$log_directory' not found."
    fi
}

# Call the function to execute
zip_text_files

#Delete all the old Zip files older than 14 days ago

Delete_old_zip_files() {
    zip_log_directory="/home/ubuntu/log_file"
    no_of_days_ago_to_delete="+14"
    # Check if the log directory exists
    if [ -d "$zip_log_directory" ]; then
        # Find all txt files in the log directory older than 7 days and zip them

	  find "$zip_log_directory" -type f \( -name "*.txt" -o -name "*.gz" \) -mtime "$no_of_days_ago_to_delete" -delete
            echo "$no_of_days_ago_to_delete Days old log files removed successfully from '$zip_log_directory'."
        else
            echo "Logs directory '$zip_log_directory' not found."
        fi
}
#Delete_old_zip_files
