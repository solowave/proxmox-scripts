#!/usr/bin/env bash

# Function to display header
function header_info {
clear
cat <<"EOF"
   _____                 __    _            
  / ___/__  ______  _____/ /_  (_)___  ____ _
  \__ \/ / / / __ \/ ___/ __ \/ / __ \/ __ `/
 ___/ / /_/ / / / / /__/ / / / / / / / /_/ / 
/____/\__, /_/ /_/\___/_/ /_/_/_/ /_/\__, /  
     /____/                          /____/   
                                     
EOF
}

# Prompt for container details and paths
function prompt_for_input {
  read -rp "Enter the ID of the LXC container you wish to bind the mount point to: " CT_ID
  if [[ ! -f /etc/pve/lxc/${CT_ID}.conf ]]; then
    echo "Container with ID ${CT_ID} does not exist. Please try again."
    exit 1
  fi

  read -rp "Enter the full path of the host directory to bind mount (e.g., /mnt/lxc_shares/my_data): " HOST_DIR
  if [[ ! -d "${HOST_DIR}" ]]; then
    read -rp "${HOST_DIR} does not exist. Create it? (y/n): " CONFIRM
    if [[ "${CONFIRM}" == "y" ]]; then
      mkdir -p "${HOST_DIR}"
    else
      echo "Host directory does not exist. Exiting."
      exit 1
    fi
  fi

  read -rp "Enter the full path inside the container for the mount (e.g., /mnt/my_data): " CONTAINER_DIR
  if ! pct exec ${CT_ID} -- ls "${CONTAINER_DIR}" &>/dev/null; then
    read -rp "Directory ${CONTAINER_DIR} does not exist in container. Create it? (y/n): " CONFIRM
    if [[ "${CONFIRM}" == "y" ]]; then
      pct exec ${CT_ID} -- mkdir -p "${CONTAINER_DIR}"
    else
      echo "Exiting."
      exit 1
    fi
  fi
}

# Function to create the group if it doesn't exist in the container
function create_group_in_container {
  if pct exec ${CT_ID} -- getent group lxc_shares &>/dev/null; then
    echo "Group 'lxc_shares' already exists in container ${CT_ID}."
  else
    echo "Creating group 'lxc_shares' with GID 10000 in container ${CT_ID}..."
    pct exec ${CT_ID} -- groupadd -g 10000 lxc_shares
    echo "Group 'lxc_shares' created."
  fi
}

# Function to add users to the lxc_shares group in the container
function add_users_to_group {
  read -rp "Enter the username(s) in the container you wish to add to the lxc_shares group (comma-separated, e.g., jellyfin,plex): " USERS
  IFS=',' read -r -a USER_ARRAY <<< "$USERS"
  
  for USER in "${USER_ARRAY[@]}"; do
    echo "Adding ${USER} to the 'lxc_shares' group in container ${CT_ID}..."
    pct exec ${CT_ID} -- usermod -aG lxc_shares ${USER}
    echo "${USER} added to 'lxc_shares' group."
  done
}

# Function to set ownership and permissions on the host directory
function set_host_directory_permissions {
  echo "Setting ownership and permissions for the host directory ${HOST_DIR}..."
  chown -R 100000:110000 ${HOST_DIR}
  chmod 0770 ${HOST_DIR}
  echo "Ownership set to UID 100000 and GID 110000, permissions set to 770."
}

# Function to add the bind mount to the LXC configuration
function update_lxc_config {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"

  if grep -q "mp0:" "${CONFIG_FILE}"; then
    echo "Bind mount already exists in the configuration for container ${CT_ID}. Exiting."
    exit 1
  else
    echo "Adding bind mount point to the container configuration."
    echo "mp0: ${HOST_DIR},mp=${CONTAINER_DIR}" >> ${CONFIG_FILE}
    echo "Bind mount point added to ${CONFIG_FILE}."
  fi
}

# Function to restart the container
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  echo "Container ${CT_ID} restarted with bind mount applied."
}

# Main script execution
header_info
prompt_for_input
create_group_in_container
add_users_to_group
set_host_directory_permissions
update_lxc_config
restart_container
echo "Script complete! Container ${CT_ID} is now configured with the bind mount."
