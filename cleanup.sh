#!/bin/bash

# WARNING: This script will stop and remove all VMs and containers on your Proxmox host.

# Stop and remove all VMs
for vmid in $(qm list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Stopping VM ID $vmid"
  qm stop $vmid --timeout 0
  sleep 2
  echo "Removing VM ID $vmid"
  qm destroy $vmid
done

# Stop and remove all containers
for ctid in $(pct list | awk '{print $1}' | grep -o '[0-9]*' | grep -v '^$'); do
  echo "Stopping container ID $ctid"
  pct stop $ctid --timeout 0
  sleep 2
  echo "Removing container ID $ctid"
  pct destroy $ctid
done
