+++
title = 'Running Amazon Linux 2023 on KVM'
date = 2024-09-16T20:06:34+01:00
draft = false
tags = ['Libvirt', 'Amazon Linux 2023']
+++

# Overview

Running Amazon Linux 2023 on Linux KVM offers a flexible and efficient way to utilize Amazon Linux in a virtualized lab environment. This guide will walk you through the setup and configuration process using KVM with Cloud-init.

## 1. Prerequisites

1.1 Install the virtualization hypervisor packages.

```
dnf install qemu-kvm libvirt virt-install virt-viewer
```

1.2 Start the virtualization services:

```
for drv in qemu network nodedev nwfilter secret storage interface; do systemctl start virt${drv}d{,-ro,-admin}.socket; done
```

1.3 Verification

```
virt-host-validate
  QEMU: Checking for hardware virtualization                                 : PASS
  QEMU: Checking if device /dev/kvm exists                                   : PASS
  QEMU: Checking if device /dev/kvm is accessible                            : PASS
  QEMU: Checking if device /dev/vhost-net exists                             : PASS
  QEMU: Checking if device /dev/net/tun exists                               : PASS
  QEMU: Checking for cgroup 'cpu' controller support                         : PASS
  QEMU: Checking for cgroup 'cpuacct' controller support                     : PASS
  QEMU: Checking for cgroup 'cpuset' controller support                      : PASS
  QEMU: Checking for cgroup 'memory' controller support                      : PASS
  QEMU: Checking for cgroup 'devices' controller support                     : PASS
  QEMU: Checking for cgroup 'blkio' controller support                       : PASS
  QEMU: Checking for device assignment IOMMU support                         : PASS
  QEMU: Checking if IOMMU is enabled by kernel                               : WARN (IOMMU appears to be disabled in kernel. Add intel_iommu=on to kernel cmdline arguments)
  QEMU: Checking for secure guest support                                    : WARN (Unknown if this platform has Secure Guest support)
```

## 2 Configuring a network bridge by using nmcli 

The default network created when libvirt is used is called “default” and uses NAT (Network Address Translation) and packet forwarding to connect the emulated systems with the “outside” world (both the host system and the internet). 
With bridged networking, the virtual network adapter in the virtual machine connects to a physical network adapter in the host system. The host network adapter enables the virtual machine to connect to the LAN that the host system uses.

2.1 Create bridge interface

```
nmcli connection add type bridge con-name bridge0 ifname bridge0
```

2.2 Connect ethernet port **eno1** to the bridge

```
nmcli connection add type ethernet port-type bridge con-name bridge0-port1 ifname eno1 controller bridge0
```

2.3 To set a static IPv4 address, network mask, default gateway, and DNS server to the bridge0 connection, enter:

```
nmcli connection modify bridge0 ipv4.addresses '192.168.88.254/24' ipv4.gateway '192.168.88.1' ipv4.dns '192.168.88.100' ipv4.method manual
```

2.4 Activate the connection:

```
nmcli connection up bridge0
```

2.5 Verify that the ports are connected, and the CONNECTION column displays the port’s connection name:

```
nmcli device
DEVICE    TYPE      STATE                   CONNECTION
bridge0   bridge    connected               bridge0
eno1      ethernet  connected               bridge0-port1
lo        loopback  connected (externally)  lo
virbr0    bridge    connected (externally)  virbr0
vnet0     tun       connected (externally)  vnet0
vnet5     tun       connected (externally)  vnet5
enp1s0f0  ethernet  disconnected            --
enp1s0f1  ethernet  disconnected            --
```

## 3. Downloading Amazon Linux 2023 KVM cloud image

To create an Amazon Linux 2023 libvirt virtual machine, we need to download the KVM (qcow2) file provided by AWS. You can find the download link below: https://cdn.amazonlinux.com/al2023/os-images/latest/

3.1 Choose kvm or kvm-arm64 

3.2 Download latest Amazon Linux 2023 KVM (qcow2) cloud image.

```
mkdir -p /data/var/lib/libvirt/templates
curl https://cdn.amazonlinux.com/al2023/os-images/2023.5.20240903.0/kvm/al2023-kvm-2023.5.20240903.0-kernel-6.1-x86_64.xfs.gpt.qcow2 \
-o /data/var/lib/libvirt/templates/al2023-kvm.qcow2
```

3.3 Creating a qcow2 disk image 

QCOW uses a disk storage optimization strategy that delays allocation of storage until it is actually needed. This allows smaller file sizes than a raw disk image in cases when the image capacity is not totally used up.

```
export VM_IMAGE_DIR=/data/var/lib/libvirt
export VM=kube-master
mkdir -p ${VM_IMAGE_DIR}/init/${VM}

qemu-img create -b /data/templates/al2023-kvm.qcow2 -f qcow2 -F qcow2 "${VM_IMAGE_DIR}/images/${VM}.qcow2" 60G
```

## 4. Creating Cloud-Init Configuration Files

Cloud-init uses following configuration files:

* **meta-data**
    * This file typically includes the hostname for the virtual machine.
* **user-data**
    * This file typically configures user accounts, their passwords, ssh key pairs, and/or access mechanisms. By default, the Amazon Linux 2023 KVM and VMware images create an ec2-user user account. You can use the user-data configuration file to set the password and/or ssh keys for this default user account.
* **network-config (optional)**
    * This file typically provides a network configuration for the virtual machine which will override the default one. The default configuration is to use DHCP on the first available network interface.

4.1 Create meta-data file

```
cat > "${VM_IMAGE_DIR}/init/${VM}/meta-data" << EOF
local-hostname: kube-master.int.shirwalab.net
EOF
```

4.2 Create user-data file

```
export VM_USER_PASSWD=$(mkpasswd --method=SHA-512 --rounds=4096)
```

```
cat > "${VM_IMAGE_DIR}/init/${VM}/user-data" << EOF
#cloud-config
#vim:syntax=yaml

users:
  - default
  - name: ec2-user
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILo1RAiBWVeo5S8FuFVC0DEdnc6qooRRHDiF3sEn7hQD Home Server
EOF
```

4.3 network-config (optional)

```
cat > "${VM_IMAGE_DIR}/init/${VM}/network-config" << EOF
version: 2
ethernets:
  ens2:
    addresses:
      - 192.168.88.200/24
    gateway4: 192.168.88.1
    nameservers:
      addresses:
        - 194.168.88.100
EOF
```

## 5. Create a new VM from the KVM Guest Image using the virt-install command. 

5.1 To create a VM and start its OS installation, use the virt-install command, along with the following mandatory arguments:

```
virt-install \
    --memory 4096 \
    --vcpus 2 \
    --name ${VM} \
    --disk ${VM_IMAGE_DIR}/images/${VM}.qcow2,device=disk,bus=virtio,format=qcow2 \
    --osinfo detect=on,require=off \
    --network bridge=bridge0 \
    --virt-type kvm \
    --graphics none \
    --autostart \
    --noautoconsole \
    --import \
    --cloud-init user-data="${VM_IMAGE_DIR}/init/${VM}/user-data,meta-data=${VM_IMAGE_DIR}/init/${VM}/meta-data,network-config=${VM_IMAGE_DIR}/init/${VM}/network-config" 
```

5.2 Connect to vm via ssh

After couple of seconds, you can access the vm via SSH using the IP specified in network-config file:

```
ping -c 4 192.168.88.200
PING 192.168.88.200 (192.168.88.200) 56(84) bytes of data.
64 bytes from 192.168.88.200: icmp_seq=1 ttl=127 time=0.408 ms
64 bytes from 192.168.88.200: icmp_seq=2 ttl=127 time=0.246 ms
64 bytes from 192.168.88.200: icmp_seq=3 ttl=127 time=0.273 ms
64 bytes from 192.168.88.200: icmp_seq=4 ttl=127 time=0.235 ms

--- 192.168.88.200 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3098ms
rtt min/avg/max/mdev = 0.235/0.290/0.408/0.069 ms
```

```
ssh ec2@192.168.88.200

The authenticity of host '192.168.88.200 (192.168.88.200)' can't be established.
ED25519 key fingerprint is SHA256:FgA8WEteo2sdIv4r/Bz7yf48zFXqurxrxR6L5+UwPWM.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.88.200' (ED25519) to the list of known hosts.

   ,     #_
   ~\_  ####_        Amazon Linux 2023
  ~~  \_#####\
  ~~     \###|
  ~~       \#/ ___   https://aws.amazon.com/linux/amazon-linux-2023
   ~~       V~' '->
    ~~~         /
      ~~._.   _/
         _/ _/
       _/m/'
[ec2-user@kube-master ~]$
```