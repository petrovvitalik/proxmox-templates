#!/bin/bash

# This script automatically converts Centos 9 Stream cloud image to proxmox template
# dependencies: wget, libguestfs-tools
# local-lvm - nvme-cached lvm thin pool

# Exit on fail. Prevents overwriting of VM parameters if it already exists.
set -e
set -o pipefail

# Set fonts

BOLDRED='\033[1;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NORMAL='\033[0m'
DBOLD='\033[2m'

# Delete image if older than 2 days
find . -name CentOS-Stream-GenericCloud-9-* -mtime +2 -type f -delete

# Download image if it was deleted or doesn't exists. Install qemu guest agent to it and truncate to zero machine-id
if [ ! -f CentOS-Stream-GenericCloud-9-* ]; then
    echo -e "${DBOLD}Please download the latest Generic Cloud .qcow2 image manually from https://cloud.centos.org/centos/9-stream/x86_64/images/?C=M;O=D${NORMAL}"
    echo -e "${DBOLD}Then execute ${YELLOW}\"virt-customize -a CentOS-Stream-GenericCloud-9-* --install qemu-guest-agent --truncate /etc/machine-id\"${NORMAL}"
    echo -e "${DBOLD}And run this script again${NORMAL}"
    exit 1
fi

#Ask for VMID
echo -e "${BOLD}Type ${BOLDRED}VMID${NORMAL} ${BOLD}(from 100 to 999999) and press [ENTER]:${NORMAL}"
read VMID

# Create a VM
qm create $VMID --name Centos9Stream-templ --memory 2048 --cores 2 --cpu cputype=IvyBridge,flags=+aes\;+pcid --agent enabled=1,fstrim_cloned_disks=1

# Enable hotplug for memory, centos cloud image supports it
qm set $VMID --numa 1 --hotplug network,disk,memory,usb

# Attach network device
qm set $VMID --net0 virtio,bridge=vmbr0

# Import the disk in raw format (as unused disk)
qm importdisk $VMID CentOS-Stream-GenericCloud-9-* local-lvm --format raw

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

# user authentication for 'centos' user (optional password)
# qm set $VMID --ciuser centos --cipassword 123

# check the cloud-init config
#qm cloudinit dump $VMID user

qm template $VMID
