#!/bin/bash

# Define Proxmox commands
QM_CMD="/usr/sbin/qm"
PCT_CMD="/usr/sbin/pct"

# Configurable delay for stopping and starting
SLEEP_DELAY=5

# Log file in the same directory as the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_FILE="$SCRIPT_DIR/status.log"

# Function to prepend timestamp to log messages
log_with_timestamp() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Check if required commands are available
required_commands=("$QM_CMD" "$PCT_CMD" "awk" "seq" "realpath")
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: Command $cmd is required but not installed. Exiting." | tee -a "$LOG_FILE"
    exit 1
  }
done

# Dynamically fetch list of VM and LXC IDs
VM_IDS=($($QM_CMD list | awk 'NR>1 {print $1}'))
LXC_IDS=($($PCT_CMD list | awk 'NR>1 {print $1}'))

# Function to check VM status and reboot if needed
check_and_reboot_vm() {
  local vm_id=$1
  local conf_file="/etc/pve/nodes/$(hostname)/qemu-server/${vm_id}.conf"
  
  if [ -f "$conf_file" ]; then
    local status=$($QM_CMD status $vm_id | grep 'status:' | awk '{print $2}')
    log_with_timestamp "VM $vm_id current status: $status"
    
    if [ "$status" == "starting" ]; then
      log_with_timestamp "VM $vm_id is in the 'starting' state. Waiting for it to transition to 'running'."
      for attempt in {1..5}; do
        sleep 5  # Wait 5 seconds between checks
        status=$($QM_CMD status $vm_id | grep 'status:' | awk '{print $2}')
        if [ "$status" == "running" ]; then
          log_with_timestamp "VM $vm_id has transitioned to 'running'."
          return 0
        fi
        log_with_timestamp "VM $vm_id still in 'starting' state. Attempt $attempt of 5."
      done
      log_with_timestamp "VM $vm_id failed to transition to 'running' after multiple attempts."
    fi

    if [ "$status" != "running" ]; then
      log_with_timestamp "VM $vm_id is not running. Rebooting..."
      if ! $QM_CMD stop $vm_id; then
        log_with_timestamp "Error: Failed to stop VM $vm_id."
        return 1
      fi
      sleep $SLEEP_DELAY
      if ! $QM_CMD start $vm_id; then
        log_with_timestamp "Error: Failed to start VM $vm_id."
        return 1
      fi
    else
      local agent_status=$($QM_CMD agent $vm_id ping 2>&1)
      if [ $? -ne 0 ]; then
        log_with_timestamp "Guest agent is not responding for VM $vm_id. Rebooting..."
        if ! $QM_CMD stop $vm_id; then
          log_with_timestamp "Error: Failed to stop VM $vm_id."
          return 1
        fi
        sleep $SLEEP_DELAY
        if ! $QM_CMD start $vm_id; then
          log_with_timestamp "Error: Failed to start VM $vm_id."
          return 1
        fi
      else
        log_with_timestamp "VM $vm_id is running and guest agent is responsive."
      fi
    fi
  else
    log_with_timestamp "Configuration file '$conf_file' does not exist. Skipping VM $vm_id."
  fi
}

# Function to check LXC status and reboot if needed
check_and_reboot_lxc() {
  local lxc_id=$1
  local conf_file="/etc/pve/nodes/$(hostname)/lxc/${lxc_id}/config"
  
  if [ -f "$conf_file" ]; then
    local status=$($PCT_CMD status $lxc_id | grep 'status:' | awk '{print $2}')
    log_with_timestamp "LXC $lxc_id current status: $status"

    if [ "$status" == "starting" ]; then
      log_with_timestamp "LXC $lxc_id is in the 'starting' state. Waiting for it to transition to 'running'."
      for attempt in {1..5}; do
        sleep 5  # Wait 5 seconds between checks
        status=$($PCT_CMD status $lxc_id | grep 'status:' | awk '{print $2}')
        if [ "$status" == "running" ]; then
          log_with_timestamp "LXC $lxc_id has transitioned to 'running'."
          return 0
        fi
        log_with_timestamp "LXC $lxc_id still in 'starting' state. Attempt $attempt of 5."
      done
      log_with_timestamp "LXC $lxc_id failed to transition to 'running' after multiple attempts."
    fi

    if [ "$status" != "running" ]; then
      log_with_timestamp "LXC $lxc_id is not running. Rebooting..."
      if ! $PCT_CMD stop $lxc_id; then
        log_with_timestamp "Error: Failed to stop LXC $lxc_id."
        return 1
      fi
      sleep $SLEEP_DELAY
      if ! $PCT_CMD start $lxc_id; then
        log_with_timestamp "Error: Failed to start LXC $lxc_id."
        return 1
      fi
    else
      log_with_timestamp "LXC $lxc_id is running."
    fi
  else
    log_with_timestamp "Configuration file '$conf_file' does not exist. Skipping LXC $lxc_id."
  fi
}

# Check and reboot VMs in parallel
for vm_id in "${VM_IDS[@]}"; do
  check_and_reboot_vm $vm_id &
done
wait  # Wait for all VM checks to complete

# Check and reboot LXCs in parallel
for lxc_id in "${LXC_IDS[@]}"; do
  check_and_reboot_lxc $lxc_id &
done
wait  # Wait for all LXC checks to complete