#!/usr/bin/env bash

# Trap Ctrl+C for graceful exit
trap ctrl_c INT
function ctrl_c() {
    echo -e "\nScript interrupted. Exiting..."
    exit 1
}

# Display header
function header_info {
    clear
    cat <<"EOF"
    ____       _       __     __                      
   /  _/___   (_)___ _/ /_   / /_____  ____ _____  ____ 
   / // __ \ / / __ `/ __/  / __/ __ \/ __ `/ __ \/ __ \
 _/ // / / // / /_/ / /_   / /_/ /_/ / /_/ / / / / /_/ /
/___/_/ /_//_/\__,_/\__/   \__/\____/\__,_/_/ /_/ .___/ 
                                              /_/      

Enabling Intel Hardware Acceleration for Unprivileged LXC Containers

EOF
}

# Step 1: Verify Intel GPU presence
function check_intel_gpu_support {
    echo "Verifying Intel GPU support on the Proxmox host..."
    if ! lspci | grep -i "vga" | grep -i "intel" > /dev/null; then
        echo "ERROR: No Intel GPU detected on the Proxmox host."
        echo "Please ensure you have an Intel GPU before running this script."
        exit 1
    fi

    echo "Intel GPU detected."
    echo "Checking for relevant /dev/dri files..."
    
    if [[ ! -e /dev/dri/card0 || ! -e /dev/dri/renderD128 ]]; then
        echo "ERROR: /dev/dri files are missing. Please ensure Intel drivers are installed on the Proxmox host."
        echo "Install drivers with: apt install i965-va-driver intel-media-va-driver vainfo"
        exit 1
    fi

    echo "/dev/dri is properly configured on the host."
}

# Step 2: Prompt for container ID
function get_container_id {
    while true; do
        read -rp "Enter the ID of the LXC container you wish to configure: " CT_ID
        if [[ -f /etc/pve/lxc/${CT_ID}.conf ]]; then
            echo "Container ID ${CT_ID} found."
            break
        else
            echo "ERROR: No container configuration found for ID ${CT_ID}."
        fi
    done
}

# Step 3: Configure /dev/dri access in the container
function configure_dri_access {
    echo "Configuring /dev/dri access for container ${CT_ID}..."

    CONFIG_FILE="/etc/pve/lxc/${CT_ID}.conf"

    # Check if /dev/dri is already configured
    if grep -q "/dev/dri" "$CONFIG_FILE"; then
        echo "INFO: /dev/dri already configured in ${CONFIG_FILE}."
    else
        echo "Adding /dev/dri to the container configuration..."
        echo "lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir" >> "$CONFIG_FILE"
    fi
}

# Step 4: Verify and adjust /dev/dri permissions on the host
function set_host_permissions {
    echo "Ensuring proper permissions on /dev/dri..."
    # Change group of renderD128 to video
    chgrp video /dev/dri/renderD128
    chmod 660 /dev/dri/renderD128

    echo "Permissions for /dev/dri adjusted (group: video, mode: 660)."
}

# Step 5: Install necessary drivers and tools in the container
function install_drivers_in_container {
    echo "Installing Intel drivers and tools inside container ${CT_ID}..."
    pct exec "${CT_ID}" -- apt update
    pct exec "${CT_ID}" -- apt install -y vainfo intel-media-va-driver i965-va-driver
    echo "Intel drivers and tools installed inside container ${CT_ID}."
}

# Step 6: Verify hardware acceleration inside the container
function verify_in_container {
    echo "Verifying hardware acceleration inside container ${CT_ID}..."
    pct exec "${CT_ID}" -- vainfo
}

# Main Execution
header_info
check_intel_gpu_support
get_container_id
configure_dri_access
set_host_permissions
install_drivers_in_container

echo "Configuration complete. Restart the container for changes to take effect."
read -rp "Would you like to restart the container now? [y/N]: " RESTART_CONFIRM
if [[ "${RESTART_CONFIRM,,}" == "y" ]]; then
    pct restart "${CT_ID}"
    echo "Container ${CT_ID} restarted."
fi

echo "To verify hardware acceleration, log into the container and run 'vainfo'."