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

# Use ACLs to grant access to the host directory for the container's high-mapped UID
function set_permissions_via_acl {
  # Get the high-mapped UID for the container (e.g., 100000, 101000, etc.)
  HIGH_MAPPED_UID=$(( 100000 + ${CT_ID} ))
  
  # Apply ACL to grant the container's high-mapped UID access to the host directory
  echo "Granting ACL permissions to UID ${HIGH_MAPPED_UID} for ${HOST_DIR}."
  setfacl -m u:${HIGH_MAPPED_UID}:rwx ${HOST_DIR}
  echo "ACL permissions set for container ${CT_ID} (UID ${HIGH_MAPPED_UID}) on ${HOST_DIR}."
}

# Check if setfacl is installed in the container, install it if missing
function install_acl_if_missing {
  if ! pct exec ${CT_ID} -- which setfacl &> /dev/null; then
    echo "setfacl is not installed. Installing acl package inside the container..."
    pct exec ${CT_ID} -- apt update
    pct exec ${CT_ID} -- apt install -y acl
    echo "ACL package installed."
  fi
}

# Use ACL to assign access to the directory for a non-root user (optional)
function set_acl_permissions {
  if [[ -n "${NON_ROOT_USER}" ]]; then
    install_acl_if_missing
    echo "Setting ACL permissions for ${NON_ROOT_USER} on ${CONTAINER_DIR}."
    pct exec ${CT_ID} -- setfacl -m u:${NON_ROOT_USER}:rwx ${CONTAINER_DIR}
    echo "ACL set successfully. User ${NON_ROOT_USER} now has access to ${CONTAINER_DIR}."
  fi
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
set_permissions_via_acl
set_acl_permissions
update_lxc_config
create_symlink
restart_container
echo "Post-install script complete! Container ${CT_ID} is now configured."
