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

# Function to check if a mount point exists in the config file and pre-fill the paths
function check_existing_mount {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"
  if grep -q "mp0:" "${CONFIG_FILE}"; then
    # Extract existing mp0 paths for host and container
    EXISTING_HOST_DIR=$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 1 | cut -d ':' -f 2)
    EXISTING_CONTAINER_DIR=$(grep "mp0:" "${CONFIG_FILE}" | cut -d ',' -f 2 | cut -d '=' -f 2)
    # Remove mp0 as we will replace it with lxc.mount.entry
    sed -i "/mp0:/d" "${CONFIG_FILE}"
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
    CT_ID=$(whiptail --inputbox "Enter the ID of the LXC container you wish to bind the mount point to (or type 'exit' to quit):" 8 60 3>&1 1>&2 2>&3)
    
    # Exit option
    if [[ "${CT_ID}" == "exit" ]]; then
      whiptail --msgbox "Exiting script..." 8 40
      exit 1
    fi

    if [[ -f /etc/pve/lxc/${CT_ID}.conf ]]; then
      break  # valid container ID, move on
    else
      whiptail --msgbox "Container with ID ${CT_ID} does not exist. Please try again." 8 60
    fi
  done
}

# Function to manually input host directory with pre-filled value if available
function get_host_directory {
  HOST_DIR=$(whiptail --inputbox "Enter the full path of the host directory to bind mount (default: /tank/data):" 8 78 "${EXISTING_HOST_DIR}" 3>&1 1>&2 2>&3)
  
  if [[ -z "$HOST_DIR" ]]; then
    whiptail --msgbox "No directory selected. Exiting..." 8 40
    exit 1
  fi
}

# Function to manually input container directory with pre-filled value and check if it exists
function get_container_directory {
  while true; do
    CONTAINER_DIR=$(whiptail --inputbox "Enter the full path inside the container for the mount (e.g., /mnt/host-data):" 8 78 "${EXISTING_CONTAINER_DIR}" 3>&1 1>&2 2>&3)

    # If the user cancels or no valid selection is made
    if [[ -z "$CONTAINER_DIR" ]]; then
      whiptail --msgbox "No directory selected. Exiting..." 8 40
      exit 1
    fi

    # Check if the directory exists in the container
    if pct exec ${CT_ID} -- [ -d "${CONTAINER_DIR}" ]; then
      break  # Directory exists, proceed
    else
      # Ask if the user wants to create the directory
      if whiptail --yesno "The directory ${CONTAINER_DIR} does not exist in the container. Do you want to create it?" 8 60; then
        pct exec ${CT_ID} -- mkdir -p "${CONTAINER_DIR}"
        whiptail --msgbox "Directory ${CONTAINER_DIR} created in container ${CT_ID}." 8 40
        break  # Directory created, proceed
      else
        # Ask the user to re-enter the directory
        whiptail --msgbox "Please enter a valid directory path." 8 40
      fi
    fi
  done
}

# Function to create the group if it doesn't exist in the container
function create_group_in_container {
  if pct exec ${CT_ID} -- getent group lxc_shares &>/dev/null; then
    whiptail --msgbox "Group 'lxc_shares' already exists in container ${CT_ID}." 8 40
  else
    pct exec ${CT_ID} -- groupadd -g 10000 lxc_shares
    whiptail --msgbox "Group 'lxc_shares' created in container ${CT_ID}." 8 40
  fi
}

# Add or create users in the lxc_shares group in the container
function add_users_to_group {
  # Prefill the username with the container's hostname
  CONTAINER_HOSTNAME=$(pct exec ${CT_ID} -- hostname)
  
  while true; do
    USERS=$(whiptail --inputbox "Enter the username(s) in the container you wish to add to the lxc_shares group (comma-separated, pre-filled with container hostname or type 'exit' to quit):" 8 60 "${CONTAINER_HOSTNAME}" 3>&1 1>&2 2>&3)

    # Exit option
    if [[ "${USERS}" == "exit" ]]; then
      whiptail --msgbox "Exiting script..." 8 40
      exit 1
    fi

    IFS=',' read -r -a USER_ARRAY <<< "$USERS"
    for USER in "${USER_ARRAY[@]}"; do
      if pct exec ${CT_ID} -- id -u "${USER}" &>/dev/null; then
        pct exec ${CT_ID} -- usermod -aG lxc_shares "${USER}"
        whiptail --msgbox "${USER} added to 'lxc_shares' group in container ${CT_ID}." 8 40
      else
        # Ask if the user should be created
        if (whiptail --yesno "User ${USER} does not exist in container ${CT_ID}. Create user?" 8 40); then
          # Create the user with a home directory and default shell
          pct exec ${CT_ID} -- useradd -m -s /bin/bash "${USER}"
          pct exec ${CT_ID} -- usermod -aG lxc_shares "${USER}"
          whiptail --msgbox "User ${USER} created and added to 'lxc_shares' group in container ${CT_ID}." 8 40
        else
          # Skip user creation
          whiptail --msgbox "User ${USER} was not created. Let's try again." 8 40
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
  whiptail --msgbox "Ownership set to UID 100000 and GID 110000, permissions set to 770." 8 40
}

# Add the bind mount to the LXC configuration, replacing mp0 or lxc.mount.entry if necessary
function update_lxc_config {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"

  # Check if mp0 exists
  if grep -q "mp0:" "${CONFIG_FILE}"; then
    # Remove mp0 and replace it with lxc.mount.entry
    sed -i "/mp0:/d" "${CONFIG_FILE}"
    echo "mp0 entry removed and replaced with lxc.mount.entry."
    echo "lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR} none bind 0 0" >> "${CONFIG_FILE}"
    whiptail --msgbox "mp0 bind mount replaced with lxc.mount.entry in container ${CT_ID}." 8 40

  # Check if lxc.mount.entry exists
  elif grep -q "lxc.mount.entry" "${CONFIG_FILE}"; then
    # Replace the existing lxc.mount.entry with new paths
    sed -i "s|lxc.mount.entry: .*|lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR} none bind 0 0|" "${CONFIG_FILE}"
    whiptail --msgbox "Existing lxc.mount.entry updated with new paths in container ${CT_ID}." 8 40

  # If neither exists, add the new lxc.mount.entry
  else
    echo "lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR} none bind 0 0" >> "${CONFIG_FILE}"
    whiptail --msgbox "Bind mount entry added to ${CONFIG_FILE} for container ${CT_ID}." 8 40
  fi
}

# Restart the container
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  whiptail --msgbox "Container ${CT_ID} restarted with bind mount applied." 8 40
}

# Main script execution
header_info
show_welcome
get_container_id  # Loop back to container ID step if invalid
check_existing_mount  # Check if there are existing mounts and prefill paths
get_host_directory  # Manual host directory input with prefilled paths
get_container_directory  # Manual container directory input with prefilled paths, checks for existence
create_group_in_container
add_users_to_group  # Loop back to username step if invalid; creates missing users
set_host_directory_permissions
update_lxc_config
restart_container
whiptail --msgbox "Script complete! Container ${CT_ID} is now configured with the bind mount." 8 40
