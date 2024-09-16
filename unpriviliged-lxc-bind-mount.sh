#!/usr/bin/env bash

# Trap Ctrl+C and exit gracefully
trap ctrl_c INT
function ctrl_c() {
    dialog --msgbox "Script interrupted. Exiting now!" 8 40
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

# Show the welcome message using dialog
function show_welcome {
  dialog --title "LXC Setup Script" --msgbox "Welcome to the LXC Bind Mount Setup Script!" 8 60
}

# Function to check if a mount point exists in the config file and pre-fill the paths
function check_existing_mount {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"
  if grep -q "mp0:" "${CONFIG_FILE}"; then
    # Extract existing mp0 paths for host and container
    EXISTING_HOST_DIR=$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 1 | cut -d ':' -f 2)
    EXISTING_CONTAINER_DIR=$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 2 | cut -d '=' -f 2)
    # Replace mp0 with lxc.mount.entry
    sed -i "/mp0:/d" "${CONFIG_FILE}"
    echo "Found mp0 mount. Replacing with lxc.mount.entry."
  elif grep -q "lxc.mount.entry:" "${CONFIG_FILE}"; then
    # Extract existing lxc.mount.entry paths
    EXISTING_HOST_DIR=$(grep "lxc.mount.entry:" "${CONFIG_FILE}" | cut -d ' ' -f 2)
    EXISTING_CONTAINER_DIR=$(grep "lxc.mount.entry:" "${CONFIG_FILE}" | cut -d ' ' -f 3)
  else
    # Default paths if no mount point is found
    EXISTING_HOST_DIR="/tank/data"
    EXISTING_CONTAINER_DIR="mnt/my_data"  # No leading slash for container
  fi
}

# Function to get container ID and validate it
function get_container_id {
  while true; do
    CT_ID=$(dialog --inputbox "Enter the ID of the LXC container you wish to bind the mount point to (or type 'exit' to quit):" 8 60 3>&1 1>&2 2>&3)
    
    # Exit option
    if [[ "${CT_ID}" == "exit" ]]; then
      dialog --msgbox "Exiting script..." 8 40
      exit 1
    fi

    if [[ -f /etc/pve/lxc/${CT_ID}.conf ]]; then
      break  # valid container ID, move on
    else
      dialog --msgbox "Container with ID ${CT_ID} does not exist. Please try again." 8 60
    fi
  done
}

# Function to simulate folder navigation using dialog for host directories
function navigate_directories {
  local BASE_DIR=$1
  local DIR_SELECTED

  while true; do
    # List directories in the current folder
    DIR_SELECTED=$(dialog --stdout --title "Select a directory" --dselect "${BASE_DIR}/" 20 60)

    # Exit on cancel
    if [ $? -ne 0 ]; then
      return 1
    fi

    # Check if the selected path is a directory and navigate into it
    if [[ -d "$DIR_SELECTED" ]]; then
      BASE_DIR="$DIR_SELECTED"
      break  # directory selected, move on
    else
      dialog --msgbox "Not a valid directory. Please try again." 8 40
    fi
  done

  echo "$DIR_SELECTED"  # return selected directory
}

# Function to select host directory interactively
function get_host_directory {
  while true; do
    BASE_HOST_DIR=$(dialog --inputbox "Enter the base path of the host directory to bind mount (or type 'exit' to quit):" 8 60 "/tank/data" 3>&1 1>&2 2>&3)

    # Exit option
    if [[ "${BASE_HOST_DIR}" == "exit" ]]; then
      dialog --msgbox "Exiting script..." 8 40
      exit 1
    fi

    if [[ -d "${BASE_HOST_DIR}" ]]; then
      break  # valid base directory, move on
    else
      dialog --msgbox "Base directory does not exist. Let's try again." 8 40
    fi
  done

  # Call the folder navigation function
  HOST_DIR=$(navigate_directories "${BASE_HOST_DIR}")
}

# Function to simulate folder navigation using dialog for container directories
function get_container_directory {
  local DIR_SELECTED

  while true; do
    # List directories in the container
    DIR_SELECTED=$(pct exec ${CT_ID} -- find / -maxdepth 1 -type d | dialog --stdout --menu "Select a container directory to mount:" 20 60 10 3>&1 1>&2 2>&3)

    # Remove leading slash if present
    CONTAINER_DIR="${DIR_SELECTED#/}"

    if pct exec ${CT_ID} -- ls "${CONTAINER_DIR}" &>/dev/null; then
      break  # valid container directory, move on
    else
      dialog --msgbox "Container directory is required. Let's try again." 8 40
    fi
  done
}

# Create the group if it doesn't exist in the container
function create_group_in_container {
  if pct exec ${CT_ID} -- getent group lxc_shares &>/dev/null; then
    dialog --msgbox "Group 'lxc_shares' already exists in container ${CT_ID}." 8 40
  else
    pct exec ${CT_ID} -- groupadd -g 10000 lxc_shares
    dialog --msgbox "Group 'lxc_shares' created in container ${CT_ID}." 8 40
  fi
}

# Add or create users in the lxc_shares group in the container
function add_users_to_group {
  # Prefill the username with the container's hostname
  CONTAINER_HOSTNAME=$(pct exec ${CT_ID} -- hostname)
  
  while true; do
    USERS=$(dialog --inputbox "Enter the username(s) in the container you wish to add to the lxc_shares group (comma-separated, pre-filled with container hostname or type 'exit' to quit):" 8 60 "${CONTAINER_HOSTNAME}" 3>&1 1>&2 2>&3)

    # Exit option
    if [[ "${USERS}" == "exit" ]]; then
      dialog --msgbox "Exiting script..." 8 40
      exit 1
    fi

    IFS=',' read -r -a USER_ARRAY <<< "$USERS"
    for USER in "${USER_ARRAY[@]}"; do
      if pct exec ${CT_ID} -- id -u "${USER}" &>/dev/null; then
        pct exec ${CT_ID} -- usermod -aG lxc_shares "${USER}"
        dialog --msgbox "${USER} added to 'lxc_shares' group in container ${CT_ID}." 8 40
      else
        # Ask if the user should be created
        if (dialog --yesno "User ${USER} does not exist in container ${CT_ID}. Create user?" 8 40); then
          # Create the user with a home directory and default shell
          pct exec ${CT_ID} -- useradd -m -s /bin/bash "${USER}"
          pct exec ${CT_ID} -- usermod -aG lxc_shares "${USER}"
          dialog --msgbox "User ${USER} created and added to 'lxc_shares' group in container ${CT_ID}." 8 40
        else
          # Skip user creation
          dialog --msgbox "User ${USER} was not created. Let's try again." 8 40
        fi
      fi
    done
    break  # All users valid, move on
  done
}

# Set ownership and permissions on the host directory
function set_host_directory_permissions {
  chown -R 100000:110000 ${HOST_DIR}
  chmod 0770 ${HOST_DIR}
  dialog --msgbox "Ownership set to UID 100000 and GID 110000, permissions set to 770." 8 40
}

# Add the bind mount to the LXC configuration, replacing mp0 or lxc
