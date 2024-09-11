#!/usr/bin/env bash

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

# Prompt for container details and paths
function prompt_for_input {
  read -rp "Enter the ID of the LXC container you wish to bind the mount point to: " CT_ID
  if [[ ! -f /etc/pve/lxc/${CT_ID}.conf ]]; then
    echo "Container with ID ${CT_ID} does not exist. Please try again."
    exit 1
  fi

  read -rp "Enter the full path of the host directory to bind mount (e.g., /tank/data): " HOST_DIR
  if [[ ! -d "${HOST_DIR}" ]]; then
    read -rp "${HOST_DIR} does not exist. Create it? (y/n): " CONFIRM
    if [[ "${CONFIRM}" == "y" ]]; then
      mkdir -p "${HOST_DIR}"
    else
      echo "Host directory does not exist. Exiting."
      exit 1
    fi
  fi

  read -rp "Enter the full path inside the container for the mount (e.g., /mnt/host-data): " CONTAINER_DIR
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

# Set the container's high-mapped GID to match the containershare group
function add_high_mapped_gid_to_group {
  # Get the high-mapped GID for the container (e.g., 100000, 101000, etc.)
  HIGH_MAPPED_GID=$(( 100000 + ${CT_ID} ))

  # Ensure the containershare group exists on the host
  if ! getent group containershare &> /dev/null; then
    echo "Error: Group 'containershare' does not exist on the host. Exiting."
    exit 1
  fi

  # Apply group ownership on the container side (inside /Downloads)
  echo "Setting GID ${HIGH_MAPPED_GID} inside container ${CT_ID} on ${CONTAINER_DIR}."
  pct exec ${CT_ID} -- chown :containershare "${CONTAINER_DIR}" -R
  pct exec ${CT_ID} -- chmod g+rwxs "${CONTAINER_DIR}"

  # Ensure all new files created inside the directory inherit the containershare GID
  pct exec ${CT_ID} -- chmod g+s "${CONTAINER_DIR}"
  
  echo "Group ownership updated for container ${CT_ID} on ${CONTAINER_DIR}."
}

# Update LXC configuration to bind the directory
function update_lxc_config {
  echo "Adding bind mount point to the container configuration."
  echo "mp0: ${HOST_DIR},mp=${CONTAINER_DIR}" >> /etc/pve/lxc/${CT_ID}.conf
}

# Create symbolic link for easier access on host (optional)
function create_symlink {
  read -rp "Do you want to create a symbolic link for easy access to ${HOST_DIR}? (y/n): " CONFIRM_LINK
  if [[ "${CONFIRM_LINK}" == "y" ]]; then
    read -rp "Enter the path for the symbolic link (default: /mnt/container-${CT_ID}-data): " SYMLINK_PATH
    SYMLINK_PATH=${SYMLINK_PATH:-/mnt/container-${CT_ID}-data}
    ln -s ${HOST_DIR} ${SYMLINK_PATH}
    echo "Created symbolic link at ${SYMLINK_PATH} pointing to ${HOST_DIR}."
  else
    echo "Skipping symbolic link creation."
  fi
}

# Restart the container and verify setup
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  echo "Verifying the bind mount inside the container..."
  pct exec ${CT_ID} -- ls -la ${CONTAINER_DIR}
}

header_info
prompt_for_input
add_high_mapped_gid_to_group
update_lxc_config
create_symlink
restart_container
echo "Post-install script complete! Container ${CT_ID} is now configured."
