+++
title = 'FreeIPA on RHEL 9 setup'
date = 2024-09-13T11:08:17+01:00
draft = false
tags = ['FreeIPA']
+++

# Overview

Sponsored by RedHat, FreeIPA, – Identity Policy Authentication – is a free and opensource identity and Authentication management solution designed specifically for Linux/Unix environments. FreeIPA is to Linux what Active Directory is to Windows.

FreeIPA provides a centralized solution for authentication and authorization of user accounts in a Linux environment.  It is the Upstream to RedHat’s IdM (Identity Manager) and is built on top of the following opensource components:

* **NTP Server** – Network Time Protocol Server
* **Apache HTTP Server** – A web server that allows you to access and manage FreeIPA from the Web browser.
* **389 Directory Server** – This is an implementation of LDAP and is the main data store that provides a full multi-master LDAPv3 directory infrastructure.
* **Dogtag PKI Certificate Authority** – It provides CA certificate management functions.
* **MIT Kerberos KDC** – This provides a Kerberos database and service for Single-Sign-on authentication.
* **ISC Bind DNS server** – It manages Domain Names
* Python Management framework

# Installation

## VM Install

Download rhel9 cloud image from https://access.redhat.com/downloads/content/rhel

```
export VM_IMAGE_DIR=/data/var/lib/libvirt
export VM=freeipa
export VM_USER_PASSWD=$(mkpasswd --method=SHA-512 --rounds=4096)
mkdir -p ${VM_IMAGE_DIR}/init/${VM}
```

Creating a qcow2 image file ${VM_IMAGE_DIR}/images/${VM}.img that uses the cloud image file.

```
qemu-img create -b /data/templates/rhel-9.4-x86_64-kvm.qcow2 -f qcow2 -F qcow2 "${VM_IMAGE_DIR}/images/${VM}.qcow2" 60G
```

```
cat > "${VM_IMAGE_DIR}/init/${VM}/meta-data" << EOF
local-hostname: idm.int.shirwalab.net
EOF
```

Create user-data file

```
cat > "${VM_IMAGE_DIR}/init/${VM}/user-data" << EOF
#cloud-config
#vim:syntax=yaml

disable_root: true
ssh_pwauth:   false

users:
  - default
  - name: shersi
    passwd: ${VM_USER_PASSWD}
    lock_passwd: false
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILo1RAiBWVeo5S8FuFVC0DEdnc6qooRRHDiF3sEn7hQD Home Server
EOF
```

```
cat > "${VM_IMAGE_DIR}/init/${VM}/network-config" << EOF
version: 2
ethernets:
  eth0:
    addresses:
      - 192.168.88.100/24
    gateway4: 192.168.88.1
    nameservers:
      addresses:
        - 194.168.4.100
        - 194.168.8.100
EOF
```

Create a new VM from the KVM Guest Image using the virt-install command. 

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

List install VM's 

```
virsh list
 Id   Name      State
-------------------------
 7    freeipa   running
```

After couple of seconds you can connect to VM via SSH

```
ssh shersi@192.168.88.100
```

## Post VM install

Use the following command to register a system without immediately attaching a subscription:

```
subscription-manager register
```

Install essential packages

```
yum update -y
yum install -y git vim jq wget net-tools
```

Next, access the /etc/hosts file.

```
echo "192.168.88.100   ${HOSTNAME}" >> /etc/hosts
```

Disable SELINUX

```
grubby --update-kernel ALL --args selinux=0
```

Then reboot the system for the changes to come into effect.


## Install FreeIPA Server on RHEL 9

To install the FreeIPA server on your system run the command

```
yum install -y ipa-server ipa-server-dns
```

To begin the server setup run the following script:

```
ipa-server-install
```

The script prompts to configure an integrated DNS service. Enter yes.

```
This includes:
  * Configure a stand-alone CA (dogtag) for certificate management
  * Configure the NTP client (chronyd)
  * Create and configure an instance of Directory Server
  * Create and configure a Kerberos Key Distribution Center (KDC)
  * Configure Apache (httpd)
  * Configure SID generation
  * Configure the KDC to enable PKINIT

To accept the default shown in brackets, press the Enter key.

Do you want to configure integrated DNS (BIND)? [no]: yes
```

The script prompts for several required settings and offers recommended default values in brackets.

To accept a default value, press Enter.

Shortly after, details of the IPA Master will be displayed. To continue configuring the system, type ‘Yes’

```
The IPA Master Server will be configured with:
Hostname:       idm.int.shirwalab.net
IP address(es): 192.168.88.100
Domain name:    int.shirwalab.net
Realm name:     INT.SHIRWALAB.NET

The CA will be configured with:
Subject DN:   CN=Certificate Authority,O=INT.SHIRWALAB.NET
Subject base: O=INT.SHIRWALAB.NET
Chaining:     self-signed

BIND DNS server will be configured to serve IPA domain with:
Forwarders:       194.168.4.100, 194.168.8.100
Forward policy:   only
Reverse zone(s):  88.168.192.in-addr.arpa.

Continue to configure the system with these values? [no]: yes
```

At the end of the configuration of the IPA server, you will get the following output indicating the ports or services that you need to open and that the configuration and setup of the server were successful.

```
==============================================================================
Setup complete

Next steps:
	1. You must make sure these network ports are open:
		TCP Ports:
		  * 80, 443: HTTP/HTTPS
		  * 389, 636: LDAP/LDAPS
		  * 88, 464: kerberos
		  * 53: bind
		UDP Ports:
		  * 88, 464: kerberos
		  * 53: bind
		  * 123: ntp

	2. You can now obtain a kerberos ticket using the command: 'kinit admin'
	   This ticket will allow you to use the IPA tools (e.g., ipa user-add)
	   and the web user interface.

Be sure to back up the CA certificates stored in /root/cacert.p12
These files are required to create replicas. The password for these
files is the Directory Manager password
The ipa-server-install command was successful
```