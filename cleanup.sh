#!/bin/bash

# WARNING: This script will stop all VMs and containers and remove their configs on your Proxmox host.

# Stop all VMs
for vmid in $(qm list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Stopping VM ID $vmid"
  qm stop $vmid --timeout 0
done

# Stop all containers and remove their configuration files
for ctid in $(pct list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Stopping container ID $ctid"
  pct stop $ctid --timeout 0
  echo "Removing container configuration ID $ctid"
  rm -f /etc/pve/lxc/$ctid.conf
done

# Attempt to remove all VMs
for vmid in $(qm list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Removing VM ID $vmid"
  qm destroy $vmid
done

# Attempt to remove all containers
for ctid in $(pct list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Removing container ID $ctid"
  pct destroy $ctid
done
