#!/usr/bin/env bash

# Trap Ctrl+C and exit gracefully
trap ctrl_c INT
function ctrl_c() {
    whiptail --msgbox "Script interrupted. Exiting now!" 8 40
    exit 1
}

# Display ASCII art header
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

# Show welcome message using whiptail
function show_welcome {
  whiptail --title "LXC Setup Script" --msgbox "Welcome to the LXC Bind Mount Setup Script!" 8 60
}

# Function to check if a mount point exists in the config file and pre-fill paths
function check_existing_mount {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"
  
  if grep -q "mp0:" "${CONFIG_FILE}"; then
    # Extract existing mp0 paths for host and container, remove mp0
    EXISTING_HOST_DIR=$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 1 | cut -d ':' -f 2)
    EXISTING_CONTAINER_DIR="/$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 2 | cut -d '=' -f 2)"  # Add leading slash back for user input
    sed -i "/mp0:/d" "${CONFIG_FILE}"  # Remove mp0 entry
  elif grep -q "lxc.mount.entry:" "${CONFIG_FILE}"; then
    # Extract existing lxc.mount.entry paths, ensure leading slash is shown in the input
    EXISTING_HOST_DIR=$(grep "lxc.mount.entry:" "${CONFIG_FILE}" | cut -d ' ' -f 2)
    EXISTING_CONTAINER_DIR="/$(grep "lxc.mount.entry:" "${CONFIG_FILE}" | cut -d ' ' -f 3)"  # Add leading slash back for user input
  else
    # Default paths if no existing mount point is found
    EXISTING_HOST_DIR="/tank/data"
    EXISTING_CONTAINER_DIR="/mnt/my_data"
  fi
}

# Get the container ID and verify if it exists
function get_container_id {
  while true; do
    CT_ID=$(whiptail --inputbox "Enter the ID of the LXC container you wish to bind the mount point to (or type 'exit' to quit):" 8 60 3>&1 1>&2 2>&3)
    
    # Exit option
    [[ "${CT_ID}" == "exit" ]] && whiptail --msgbox "Exiting script..." 8 40 && exit 1
    
    [[ -f /etc/pve/lxc/${CT_ID}.conf ]] && break  # Valid container ID, move on
    whiptail --msgbox "Container with ID ${CT_ID} does not exist. Please try again." 8 60
  done
}

# Manually input host directory (pre-filled default)
function get_host_directory {
  HOST_DIR=$(whiptail --inputbox "Enter the full path of the host directory to bind mount (default: /tank/data):" 8 78 "${EXISTING_HOST_DIR}" 3>&1 1>&2 2>&3)
  
  # Exit if no input
  [[ -z "$HOST_DIR" ]] && whiptail --msgbox "No directory selected. Exiting..." 8 40 && exit 1
}

# Manually input container directory, check if it exists, and create if necessary
function get_container_directory {
  while true; do
    CONTAINER_DIR=$(whiptail --inputbox "Enter the full path inside the container for the bind mount (e.g., /mnt/host-data):" 8 78 "${EXISTING_CONTAINER_DIR}" 3>&1 1>&2 2>&3)

    # Exit if no input
    [[ -z "$CONTAINER_DIR" ]] && whiptail --msgbox "No directory selected. Exiting..." 8 40 && exit 1
    
    # Check if the directory exists in the container
    if pct exec "${CT_ID}" -- [ -d "${CONTAINER_DIR}" ]; then
      break  # Directory exists, proceed
    else
      # Ask if the user wants to create the directory
      if whiptail --yesno "The directory ${CONTAINER_DIR} does not exist in the container. Do you want to create it?" 8 60; then
        pct exec "${CT_ID}" -- mkdir -p "${CONTAINER_DIR}"  # Create the directory
        whiptail --msgbox "Directory ${CONTAINER_DIR} created in container ${CT_ID}." 8 40
        break  # Directory created, proceed
      else
        whiptail --msgbox "Please enter a valid directory path." 8 40
      fi
    fi
  done
}

# Function to create `lxc_shares` group if it doesn't exist in the container
function create_group_in_container {
  if pct exec "${CT_ID}" -- getent group lxc_shares &>/dev/null; then
    whiptail --msgbox "Group 'lxc_shares' already exists in container ${CT_ID}." 8 40
  else
    pct exec "${CT_ID}" -- groupadd -g 10000 lxc_shares
    whiptail --msgbox "Group 'lxc_shares' created in container ${CT_ID}." 8 40
  fi
}

# Function to add or create users in the `lxc_shares` group in the container
function add_users_to_group {
  CONTAINER_HOSTNAME=$(pct exec "${CT_ID}" -- hostname)  # Prefill hostname
  
  while true; do
    USERS=$(whiptail --inputbox "Enter the username(s) to add to the lxc_shares group (comma-separated, pre-filled with container's hostname):" 8 60 "${CONTAINER_HOSTNAME}" 3>&1 1>&2 2>&3)

    # Exit option
    [[ "${USERS}" == "exit" ]] && whiptail --msgbox "Exiting script..." 8 40 && exit 1

    # Split into an array and loop
    IFS=',' read -r -a USER_ARRAY <<< "$USERS"
    for USER in "${USER_ARRAY[@]}"; do
      if pct exec "${CT_ID}" -- id -u "${USER}" &>/dev/null; then
        pct exec "${CT_ID}" -- usermod -aG lxc_shares "${USER}"  # Add to group
        whiptail --msgbox "${USER} added to 'lxc_shares' group in container ${CT_ID}." 8 40
      else
        # Ask if the user should be created
        if whiptail --yesno "User ${USER} does not exist in container ${CT_ID}. Create user?" 8 40; then
          pct exec "${CT_ID}" -- useradd -m -s /bin/bash "${USER}"  # Create the user
          pct exec "${CT_ID}" -- usermod -aG lxc_shares "${USER}"  # Add to group
          whiptail --msgbox "User ${USER} created and added to 'lxc_shares' group in container ${CT_ID}." 8 40
        else
          whiptail --msgbox "User ${USER} was not created. Let's try again." 8 40
        fi
      fi
    done
    break  # All users handled, move on
  done
}

# Set permissions and ownership for the host directory
function set_host_directory_permissions {
  chown -R 100000:110000 "${HOST_DIR}"  # Set ownership for UID 100000 (container root) and GID 110000 (`lxc_shares` group)
  chmod 0770 "${HOST_DIR}"              # Set permissions to rwx for owner and group, no access for others
  whiptail --msgbox "Ownership set to UID 100000 and GID 110000, permissions set to 770." 8 40
}

# Add the bind mount to the LXC configuration (omit leading slash for snapshots)
function update_lxc_config {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"
  
  # Strip leading slash for LXC configuration entry
  CONTAINER_DIR_CLEAN="${CONTAINER_DIR#/}"
  
  # Remove mp0 or lxc.mount.entry, if they exist, then add the new entry without the leading slash
  if grep -q "mp0:" "${CONFIG_FILE}"; then
    sed -i "/mp0:/d" "${CONFIG_FILE}"
  fi
  
  if grep -q "lxc.mount.entry:" "${CONFIG_FILE}"; then
    sed -i "s|lxc.mount.entry: .*|lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR_CLEAN} none bind 0 0|" "${CONFIG_FILE}"
    whiptail --msgbox "Existing lxc.mount.entry updated with new paths in container ${CT_ID}." 8 40
  else
    echo "lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR_CLEAN} none bind 0 0" >> "${CONFIG_FILE}"
    whiptail --msgbox "Bind mount entry added to ${CONFIG_FILE} for container ${CT_ID}." 8 40
  fi
}

# Restart the container
function restart_container {
  pct stop "${CT_ID}"
  pct start "${CT_ID}"
  whiptail --msgbox "Container ${CT_ID} restarted with bind mount applied." 8 40
}

# Main execution flow
header_info
show_welcome
get_container_id
check_existing_mount  # Check existing mount points and prefill paths if necessary
get_host_directory    # Input host directory with defaults
get_container_directory  # Input container directory (with leading slash) and handle creation
create_group_in_container
add_users_to_group  # Add or create users for lxc_shares group
set_host_directory_permissions
update_lxc_config   # Strip leading slash for config file
restart_container    # Restart the container to apply changes
whiptail --msgbox "Script complete! Container ${CT_ID} is now configured with the bind mount." 8 40
