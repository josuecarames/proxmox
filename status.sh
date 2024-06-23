#!/bin/bash

# Ensure PATH includes /usr/sbin
export PATH=$PATH:/usr/sbin

# Full path to qm and pct commands
QM_CMD="/usr/sbin/qm"
PCT_CMD="/usr/sbin/pct"

# List of VM and LXC IDs to monitor
VM_IDS=($(seq 100 118))
LXC_IDS=(119)

# Function to check if VM is frozen by monitoring guest agent response
is_vm_frozen() {
  local vm_id=$1
  local agent_status=$($QM_CMD agent $vm_id ping 2>&1)
  if [[ "$agent_status" == *"QEMU guest agent is not running"* ]]; then
    return 0  # VM is frozen
  else
    return 1  # VM is not frozen
  fi
}

# Function to check VM status and reboot if needed
check_and_reboot_vm() {
  local vm_id=$1
  local conf_file="/etc/pve/nodes/$(hostname)/qemu-server/${vm_id}.conf"
  if [ -f "$conf_file" ]; then
    local status=$($QM_CMD status $vm_id | grep 'status:' | awk '{print $2}')
    if [ "$status" != "running" ]; then
      echo "VM $vm_id is not running. Rebooting..."
      $QM_CMD stop $vm_id
      sleep 5  # Wait a few seconds before starting again
      $QM_CMD start $vm_id
    else
      if is_vm_frozen $vm_id; then
        echo "VM $vm_id is frozen. Rebooting..."
        $QM_CMD stop $vm_id
        sleep 5  # Wait a few seconds before starting again
        $QM_CMD start $vm_id
      else
        echo "VM $vm_id is running and not frozen."
      fi
    fi
  else
    echo "Configuration file '$conf_file' does not exist. Skipping reboot for VM $vm_id."
  fi
}

# Function to check LXC status and reboot if needed
check_and_reboot_lxc() {
  local lxc_id=$1
  local conf_file="/etc/pve/nodes/$(hostname)/lxc/${lxc_id}/config"
  if [ -f "$conf_file" ]; then
    local status=$($PCT_CMD status $lxc_id | grep 'status:' | awk '{print $2}')
    if [ "$status" != "running" ]; then
      echo "LXC $lxc_id is not running. Rebooting..."
      $PCT_CMD stop $lxc_id
      sleep 5  # Wait a few seconds before starting again
      $PCT_CMD start $lxc_id
    else
      echo "LXC $lxc_id is running."
    fi
  else
    echo "Configuration file '$conf_file' does not exist. Skipping reboot for LXC $lxc_id."
  fi
}

# Check and reboot VMs
for vm_id in "${VM_IDS[@]}"; do
  check_and_reboot_vm $vm_id
done

# Check and reboot LXCs
for lxc_id in "${LXC_IDS[@]}"; do
  check_and_reboot_lxc $lxc_id
done