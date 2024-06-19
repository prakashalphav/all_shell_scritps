#!/bin/bash
access_file_dir="/home/ubuntu/log_file/"
text_httpd_logs() {

     from_days_to_get_logs="7"
     to_days_to_get_logs="14"

    for access_log_zip in "$access_file_dir"access_log*; do
        if [ -f "$access_log_zip" ]; then
            filename=$(basename "$access_log_zip")
            log_file="${access_file_dir}zipped-Access-logs/${filename}.txt"
            echo -n > "$log_file"
            for (( j="$to_days_to_get_logs";j>="$from_days_to_get_logs"; j-- )); do
                zip_date=$(date -d "$j days ago" '+%d/%b/%Y')
         # echo "$zip_date"
		all_logs=$(grep -E "$zip_date" "$access_log_zip" | sed 's/^[ \t]*//;s/[ \t]*$//')
                if [ -n "$all_logs" ]; then
                echo "$all_logs" >> "$log_file"
                fi
            done
            echo "Created $log_file"
        else
            echo "No log files detected in $access_file_dir"
        fi
    done
}

text_httpd_logs

# Define the function to zip all txt files older than 7 days to 30 days in a specified directory
zip_text_files() {

   zip_log_directory="${access_file_dir}zipped-Access-logs/"

    if [ -d "$zip_log_directory" ]; then
        find "$zip_log_directory" -type f -name "*.txt" -mtime -1 -print0 |
        while IFS= read -r -d '' file; do
            gzip "$file" -f
            if [ $? -eq 0 ]; then
                echo "Compressed '$file' to '$file.gz'"
            else
                echo "Failed to compress '$file'"
            fi
        done
    else
        echo "Logs directory '$zip_log_directory' not found."
    fi
}

# Call the function to execute
zip_text_files

clear_old_httpd_logs() {
 
delete_no_of_days_from="07"
delete_upto_no_of_days="100"
    for access_log in "$access_file_dir"access_log*; do
        echo "Checking log file: $access_log"

        if [ -f "$access_log" ]; then
            for (( i="$delete_no_of_days_from"; i<="$delete_upto_no_of_days"; i++ )); do
                No_of_days_ago=$(date -d "$i days ago" '+%d\/%b\/%Y')
                sed -i "/$No_of_days_ago/d" "$access_log"
                echo "Logs older than $delete_no_of_days_from are deleted from $access_log"
            done
        else
            echo "No log files detected in $access_file_dir"
        fi
    done
}

clear_old_httpd_logs
