#!/bin/bash

# This script automatically converts ubuntu cloud image to proxmox template
# dependencies: wget, libguestfs-tools
# local-lvm - nvme-cached lvm thin pool

# Exit on fail. Prevents overwriting of VM parameters if it already exists.
set -e
set -o pipefail

#Ask for VMID
echo "Type VMID (from 100 to $VMID$VMID$VMID) and press [ENTER]:"
read VMID

# Delete image if older than 2 days
find . -name focal-server-cloudimg-amd64.img -mtime +2 -type f -delete

# Download image if it was deleted or doesn't exists. Install qemu guest agent to it and truncate to zero machine-id
if [ ! -f focal-server-cloudimg-amd64.img ]; then
    wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
    virt-customize -a focal-server-cloudimg-amd64.img --install qemu-guest-agent --truncate /etc/machine-id
fi

# Create a VM
qm create $VMID --name ubuntu2004-templ --memory 2048 --cores 2 --cpu cputype=IvyBridge,flags=+aes\;+pcid --agent enabled=1,fstrim_cloned_disks=1

# Enable hotplug for memory, ubuntu cloud image supports it
qm set $VMID --numa 1 --hotplug network,disk,memory,usb

# Attach network device
qm set $VMID --net0 virtio,bridge=vmbr0

# Import the disk in raw format (as unused disk)
qm importdisk $VMID focal-server-cloudimg-amd64.img local-lvm --format raw

# Attach the disk to the vm using VirtIO SCSI
qm set $VMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$VMID-disk-0,cache=unsafe,discard=on,ssd=1

# Attach cloudinit disk
qm set $VMID --ide2 local-lvm:cloudinit --boot c --bootdisk scsi0

# Console interfaces. Serial used for "qm serial $VMID"
qm set $VMID --serial0 socket --vga std

# The initial disk is only 2GB, thus we make it larger
lvextend /dev/pve/vm-$VMID-disk-0 -L+48G

# Using a  dhcp server on vmbr1 or use static IP
qm set $VMID --ipconfig0 ip=dhcp

# user authentication for 'ubuntu' user (optional password)
# qm set $VMID --ciuser ubuntu --cipassword 123

# check the cloud-init config
#qm cloudinit dump $VMID user

qm template $VMID
