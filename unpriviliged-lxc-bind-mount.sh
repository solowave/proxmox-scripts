#!/usr/bin/env bash

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

  read -rp "Enter the full path of the host directory to bind mount (e.g., /mnt/my-data-pool): " HOST_DIR
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

  read -rp "Enter the UID you want to map (e.g., 1005): " CUSTOM_UID
}

# Update the LXC config file to add custom UID/GID mapping
function configure_uid_mapping {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"

  # Check if UID mapping already exists
  if grep -q "lxc.idmap" "${CONFIG_FILE}"; then
    echo "Custom UID mapping already exists for container ${CT_ID}. Exiting."
    exit 1
  fi

  echo "Configuring UID/GID mapping for container ${CT_ID}..."

  # Add custom UID/GID mapping to the LXC config
  echo "lxc.idmap = u 0 100000 ${CUSTOM_UID}" >> ${CONFIG_FILE}
  echo "lxc.idmap = g 0 100000 ${CUSTOM_UID}" >> ${CONFIG_FILE}
  echo "lxc.idmap = u ${CUSTOM_UID} ${CUSTOM_UID} 1" >> ${CONFIG_FILE}
  echo "lxc.idmap = g ${CUSTOM_UID} ${CUSTOM_UID} 1" >> ${CONFIG_FILE}
  echo "lxc.idmap = u $((CUSTOM_UID + 1)) $((100000 + CUSTOM_UID + 1)) $((65535 - CUSTOM_UID))" >> ${CONFIG_FILE}
  echo "lxc.idmap = g $((CUSTOM_UID + 1)) $((100000 + CUSTOM_UID + 1)) $((65535 - CUSTOM_UID))" >> ${CONFIG_FILE}
  
  echo "UID/GID mapping configured in ${CONFIG_FILE}."
}

# Add entry to /etc/subuid and /etc/subgid
function configure_subuid_subgid {
  SUBUID_FILE="/etc/subuid"
  SUBGID_FILE="/etc/subgid"

  # Add entries for UID and GID in /etc/subuid and /etc/subgid
  echo "root:${CUSTOM_UID}:1" >> ${SUBUID_FILE}
  echo "root:${CUSTOM_UID}:1" >> ${SUBGID_FILE}

  echo "Added custom UID/GID to ${SUBUID_FILE} and ${SUBGID_FILE}."
}

# Apply ACL to grant container's high-mapped UID/GID access to the host directory
function apply_acls {
  # Apply ACL to grant the container's high-mapped UID access to the host directory
  echo "Granting ACL permissions to UID ${CUSTOM_UID} for ${HOST_DIR}."
  setfacl -m u:${CUSTOM_UID}:rwx ${HOST_DIR}
  echo "ACL permissions set for UID ${CUSTOM_UID} on ${HOST_DIR}."
}

# Update LXC container configuration to bind the directory
function update_lxc_config {
  CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"
  echo "Adding bind mount point to the container configuration."
  echo "mp0: ${HOST_DIR},mp=${CONTAINER_DIR}" >> ${CONFIG_FILE}
  echo "Bind mount point added to ${CONFIG_FILE}."
}

# Restart the container to apply changes
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  echo "Container ${CT_ID} restarted and bind mount applied."
}

header_info
prompt_for_input
configure_uid_mapping
configure_subuid_subgid
apply_acls
update_lxc_config
restart_container
echo "Post-install script complete! Container ${CT_ID} is now configured."
