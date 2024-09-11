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
}

# Apply ACL to grant container's high-mapped UID/GID access to the host directory
function apply_acls {
  # Calculate high-mapped UID/GID for the container (root UID is 0, high-mapped is 100000 + CT_ID)
  HIGH_MAPPED_UID=$(( 100000 + ${CT_ID} ))
  
  # Apply ACL to grant the container's high-mapped UID access to the host directory
  echo "Granting ACL permissions to UID ${HIGH_MAPPED_UID} for ${HOST_DIR}."
  setfacl -m u:${HIGH_MAPPED_UID}:rwx ${HOST_DIR}
  echo "ACL permissions set for container ${CT_ID} (UID ${HIGH_MAPPED_UID}) on ${HOST_DIR}."
}

# Update LXC container configuration to bind the directory
function update_lxc_config {
  echo "Adding bind mount point to the container configuration."
  echo "mp0: ${HOST_DIR},mp=${CONTAINER_DIR}" >> /etc/pve/lxc/${CT_ID}.conf
  echo "Bind mount point added to /etc/pve/lxc/${CT_ID}.conf"
}

# Optionally create non-root user inside the container
function create_non_root_user {
  read -rp "Do you want to create a non-root user to access the mounted directory? (y/n): " CONFIRM_USER
  if [[ "${CONFIRM_USER}" == "y" ]]; then
    read -rp "Enter the username (default: binduser): " USERNAME
    USERNAME=${USERNAME:-binduser}
    pct exec ${CT_ID} -- useradd -u 1000 -m -s /usr/bin/bash ${USERNAME}
    echo "Created non-root user ${USERNAME} with UID/GID 1000 in container ${CT_ID}."
  else
    echo "Proceeding without creating a non-root user."
  fi
}

# Optionally assign group to existing user
function assign_user_to_group {
  read -rp "Do you want to assign an existing user to the directory group? (y/n): " CONFIRM_GROUP
  if [[ "${CONFIRM_GROUP}" == "y" ]]; then
    read -rp "Enter the existing username (e.g., www-data): " EXISTING_USER
    pct exec ${CT_ID} -- addgroup --gid 1000 host-data
    pct exec ${CT_ID} -- usermod -aG host-data ${EXISTING_USER}
    echo "Added ${EXISTING_USER} to group host-data in container ${CT_ID}."
  else
    echo "Proceeding without assigning a user to the group."
  fi
}

# Restart the container to apply changes
function restart_container {
  pct stop ${CT_ID}
  pct start ${CT_ID}
  echo "Container ${CT_ID} restarted and bind mount applied."
}

header_info
prompt_for_input
apply_acls
update_lxc_config
create_non_root_user
assign_user_to_group
restart_container
echo "Post-install script complete! Container ${CT_ID} is now configured."
