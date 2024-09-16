#!/usr/bin/env bash

# Trap Ctrl+C and exit gracefully
trap ctrl_c INT
function ctrl_c() {
    whiptail --msgbox "Script interrupted. Exiting now!" 8 40
    exit 1
}

# Display a header using ASCII art
function header_info {
clear
cat <<"EOF"
    ____  _           __   __  ___                  __ 
   / __ )(_)___  ____/ /  /  |/  /___  __  ______  / /_
  / __  / / __ \/ __  /  / /|_/ / __ \/ / / / __ \/ __/
 / /_/ / / / / / /_/ /  / /  / / /_/ / /_/ / / / / /_  
/_____/_/_/ /_/\__,_/  /_/  /_/\____/\__,_/_/ /_/\__/  

EOF
}

# Show the welcome message using whiptail
function show_welcome {
  whiptail --title "LXC Setup Script" --msgbox "Welcome to the LXC Bind Mount Setup Script!" 8 60
}

# Function to simulate file browsing using whiptail
function browse_directory {
  local CURRENT_DIR="$1"
  local SELECTION
  
  while true; do
    # List files and directories, include ../ to go up one directory
    ITEMS=$(find "$CURRENT_DIR" -maxdepth 1 -type d -printf "%f/ " -o -type f -printf "%f " | xargs -n 1)
    SELECTION=$(whiptail --title "File Browser" --menu "Browsing $CURRENT_DIR" 20 78 10 ../ $ITEMS 3>&1 1>&2 2>&3)

    # If user cancels
    if [ $? -ne 0 ]; then
      return 1
    fi

    # If the user chooses to go up a directory
    if [[ "$SELECTION" == "../" ]]; then
      CURRENT_DIR=$(dirname "$CURRENT_DIR")
    elif [[ -d "$CURRENT_DIR/$SELECTION" ]]; then
      # If it's a directory, navigate into it
      CURRENT_DIR="$CURRENT_DIR/$SELECTION"
    else
      # It's a file, so return the selection
      echo "$CURRENT_DIR/$SELECTION"
      return 0
    fi
  done
}

# Function to get host directory interactively
function get_host_directory {
  local BASE_DIR="/tank/data"
  
  HOST_DIR=$(browse_directory "$BASE_DIR")
  
  if [[ -z "$HOST_DIR" ]]; then
    whiptail --msgbox "No directory selected. Exiting..." 8 40
    exit 1
  fi
}

# Function to select container directory interactively
function get_container_directory {
  # Browse directories inside the container
  CONTAINER_DIR=$(pct exec ${CT_ID} -- find / -maxdepth 1 -type d | whiptail --menu "Select a container directory" 20 60 10 3>&1 1>&2 2>&3)
  
  # If the user cancels or no valid selection is made
  if [[ -z "$CONTAINER_DIR" ]]; then
    whiptail --msgbox "No directory selected. Exiting..." 8 40
    exit 1
  fi
}

# Main script execution
header_info
show_welcome
get_host_directory  # Simulated file browsing for the host
get_container_directory  # Simulated file browsing for the container
