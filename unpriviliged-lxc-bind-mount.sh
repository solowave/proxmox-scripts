#!/usr/bin/env bash

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
  whiptail --title "LXC Setup Script" --msgbox "Welcome to the LXC Bind Mount Setup Script!" 8 78
}

# Prompt for container details and paths using whiptail
function prompt_for_input {
  # Get the container ID
  CT_ID=$(whiptail --inputbox "Enter the ID of the LXC container you wish to bind the mount point to:" 8 39 --title "Container ID" 3>&1 1>&2 2>&3)

  # Validate if the container exists
  if [[ ! -f /etc/pve/lxc/${CT_ID}.conf ]]; then
    whiptail --msgbox "Container with ID ${CT_ID} does not exist. Please try again." 8 78
    exit 1
  fi

  # Prefilled with /tank/data for convenience
  HOST_DIR=$(whiptail --inputbox "Enter the full path of the host directory to bind mount [default: /tank/data]:" 8 78 "/tank/data" 3>&1 1>&2 2>&3)

  # Check if the directory exists
  if [[ ! -d "${HOST_DIR}" ]]; then
    if (whiptail --yesno "${HOST_DIR} does not exist. Create it?" 8 78); then
      mkdir -p "${HOST_DIR}"
    else
      whiptail --msgbox "Host directory does not exist. Exiting." 8 78
      exit 1
    fi
  fi

  # Get the container directory
  CONTAINER_DIR=$(whiptail --inputbox "Enter the full path inside the container for the mount (e.g., /mnt/my_data):" 8 78 3>&1 1>&2 2>&3)

  # Check if directory exists in the container
  if ! pct exec ${CT_ID} -- ls "${CONTAINER_DIR}" &>/dev/null; then
    if (whiptail --yesno "Directory ${CONTAINER_DIR} does not exist in container. Create it?" 8 78); then
      pct exec ${CT_ID} -- mkdir -p "${CONTAINER_DIR}"
    else
      whiptail --msgbox "Exiting." 8 78
      exit 1
    fi
  fi
}

# Create the group if it doesn't exist in the container
function create_group_in_container {
  if pct exec ${CT_ID} -- getent group lxc_shares &>/dev/null; then
    whiptail --msgbox "Group 'lxc_shares' already exists in container ${CT_ID}." 8 78
  else
    pct exec ${CT_ID} -- groupadd -g 10000 lxc_shares
    whiptail --msgbox "Group 'lxc_shares' created in container ${CT_ID}." 8 78
  fi
}

# Add users to the lxc_shares group in the container
function add_users_to_group {
  USERS=$(whiptail --inputbox "Enter the username(s) in the container you wish to add to the lxc_shares group (comma-separated, e.g., jellyfin,plex):" 8 78 3>&1 1>&2 2>&3)
  
  IFS=',' read -r -a USER_ARRAY <<< "$USERS"
  for USER in "${USER_ARRAY[@]}"; do
    pct exec ${CT_ID} -- usermod -aG lxc_shares ${USER}
    whiptail --msgbox "${USER} added to 'lxc_shares' group in container ${CT_ID}." 8 78
  done
}

# Set ownership and permissions on the host directory
function set_host_directory_permissions {
  chown -R 100000:110000 ${HOST_DIR}
  chmod 0770 ${HOST_DIR}
  whiptail --msgbox "Ownership set to UID 100000 and GID 110000, permissions set to 770." 8 78
}

# Add the bind mount to the LXC configuration using lxc.mount.entry
function update_lxc_config {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"

  if grep -q "lxc.mount.entry" "${CONFIG_FILE}"; then
    whiptail --msgbox "Bind mount already exists in the configuration for container ${CT_ID}." 8 78
    exit 1
  else
    echo "lxc.mount.entry: ${HOST_DIR} ${CONTAINER_DIR} none bind 0 0" >> ${CONFIG_FILE}
    whiptail --msgbox "Bind mount entry added to ${CONFIG_FILE}." 8 78
  fi
}

# Restart the container
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  whiptail --msgbox "Container ${CT_ID} restarted with bind mount applied." 8 78
}

# Main script execution
header_info
show_welcome
prompt_for_input
create_group_in_container
add_users_to_group
set_host_directory_permissions
update_lxc_config
restart_container
whiptail --msgbox "Script complete! Container ${CT_ID} is now configured with the bind mount." 8 78
