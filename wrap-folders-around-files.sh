#!/usr/bin/env bash

# Function to display a header
function header_info {
clear
cat <<"EOF"
  __  __                 _        
 |  \/  |               | |       
 | \  / | ___ _ __  _   _| |_ ___  
 | |\/| |/ _ \ '_ \| | | | __/ _ \ 
 | |  | |  __/ | | | |_| | || (_) |
 |_|  |_|\___|_| |_|\__,_|\__\___/ 
                                   
Movie Directory Organizer
EOF
}

# Function to prompt for the directory path
function prompt_for_input {
  read -rp "Enter the full path to the directory containing your movie files: " MOVIE_DIR

  if [[ ! -d "${MOVIE_DIR}" ]]; then
    echo "Directory does not exist. Please check the path and try again."
    exit 1
  fi

  echo "You have entered: ${MOVIE_DIR}"
  read -rp "Do you want to proceed with creating directories and moving files? (y/n): " confirmation

  if [[ "${confirmation}" != "y" ]]; then
    echo "Operation canceled."
    exit 0
  fi
}

# Function to move files into their own directories
function move_files_to_directories {
  echo "Processing files in ${MOVIE_DIR}..."
  
  # Iterate through all files in the directory
  for file in "${MOVIE_DIR}"/*; do
    # Only process files, skip directories
    if [[ -f "$file" ]]; then
      # Get the filename without the extension
      filename=$(basename "$file")
      # Get the name without extension
      name="${filename%.*}"

      # Create a directory with the same name as the file
      mkdir -p "${MOVIE_DIR}/${name}"

      # Move the file into the newly created directory
      mv "$file" "${MOVIE_DIR}/${name}"
      echo "Moved $filename to $name/"
    fi
  done

  echo "All files have been processed."
}

# Function to confirm restart (this is optional based on your workflow)
function confirm_restart {
  read -rp "Would you like to restart your system or container? (y/n): " restart

  if [[ "${restart}" == "y" ]]; then
    echo "Restarting system or container..."
    # Uncomment the line below if you want to restart your container or system
    # pct restart <container-id>  (if it’s a Proxmox container)
    # reboot                      (if you want to reboot the whole system)
    echo "Restart completed."
  else
    echo "No restart performed."
  fi
}

# Main script execution
header_info
prompt_for_input
move_files_to_directories
confirm_restart
echo "Script complete! All files have been moved to their respective directories."
