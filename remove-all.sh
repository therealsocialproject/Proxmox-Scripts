#!/bin/bash

# WARNING: This script will stop all VMs and containers and remove their configs on your Proxmox host.

# Function to prompt for confirmation
function prompt_confirmation {
    read -p "$1 [y/N]: " choice
    case "$choice" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# Prompt the user to specify instance IDs to keep as exceptions
read -p "Enter the instance IDs to keep as exceptions (comma-separated): " exceptions_input

# Convert the user input into an array of exceptions
IFS=',' read -ra exceptions <<< "$exceptions_input"

# Stop all VMs
for vmid in $(qm list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
    echo "Stopping VM ID $vmid"
    qm stop $vmid --timeout 0
done

# Stop all containers
for ctid in $(pct list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
    echo "Stopping container ID $ctid"
    pct stop $ctid
done

# Arrays to store instances to remove
vms_to_remove=()
containers_to_remove=()

# Check if an instance ID is in the exceptions list
function is_exception {
    local id=$1
    for exception in "${exceptions[@]}"; do
        if [ "$id" -eq "$exception" ]; then
            return 0
        fi
    done
    return 1
}

# Prompt for instance IDs and add them to the list of instances to remove
for vmid in $(qm list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
    if ! is_exception "$vmid"; then
        if prompt_confirmation "Remove VM ID $vmid?"; then
            vms_to_remove+=("$vmid")
        else
            echo "Skipped VM ID $vmid removal"
        fi
    else
        echo "Skipping VM ID $vmid removal (Exception)"
    fi
done

for ctid in $(pct list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
    if ! is_exception "$ctid"; then
        if prompt_confirmation "Remove container ID $ctid?"; then
            containers_to_remove+=("$ctid")
        else
            echo "Skipped container ID $ctid removal"
        fi
    else
        echo "Skipping container ID $ctid removal (Exception)"
    fi
done

# Remove the VMs
for vmid in "${vms_to_remove[@]}"; do
    echo "Removing VM ID $vmid"
    qm destroy $vmid
done

# Remove the containers
for ctid in "${containers_to_remove[@]}"; do
    echo "Removing container ID $ctid"
    pct destroy $ctid
    echo "Removing container configuration ID $ctid"
    rm -f /etc/pve/lxc/$ctid.conf
done
