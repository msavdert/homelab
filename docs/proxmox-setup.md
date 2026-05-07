# Level 0: Proxmox VE Installation Guide (Hetzner Dedicated)

This guide details the "Level 0" setup of our homelab: installing Proxmox VE 9.x on a Hetzner dedicated server with a single public IP, using ZFS for storage and Software-Defined Networking (SDN) for virtualized networking.

## Overview

Since Hetzner dedicated servers typically come with a single public IP and no built-in KVM/IPMI (unless requested), we use the **QEMU Rescue System Trick** to install Proxmox remotely via a VNC session.

### Key Technologies
- **Hypervisor**: Proxmox VE 9.x (Debian 12 based)
- **Storage**: ZFS RAID0/1 (depending on disk count)
- **Networking**: Proxmox SDN (Simple Zone + SNAT)
- **Access**: Tailscale (for secure management)

---

## Phase 1: Prerequisites & Preparation

1.  **Boot into Rescue System**: In the Hetzner Robot panel, activate the **64-bit Debian Rescue System** and reboot your server.
2.  **SSH into Rescue**:
    ```bash
    ssh root@<YOUR_SERVER_IP>
    ```
3.  **Gather Network Information**: You will need these details for the Proxmox installation.
    ```bash
    # Identify the primary network interface
    INTERFACE_NAME=$(udevadm info -q property /sys/class/net/eth0 | grep "ID_NET_NAME_PATH=" | cut -d'=' -f2)
    # Get IP, Gateway, and CIDR
    IP_CIDR=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}')
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    IP_ADDRESS=$(echo "$IP_CIDR" | cut -d'/' -f1)
    CIDR=$(echo "$IP_CIDR" | cut -d'/' -f2)

    echo "Interface: $INTERFACE_NAME"
    echo "IP/CIDR: $IP_CIDR"
    echo "Gateway: $GATEWAY"
    ```

---

## Phase 2: Proxmox Installation via QEMU

We run the Proxmox installer inside a QEMU virtual machine that uses the physical host's disks.

### 1. Download Proxmox ISO
```bash
ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso" # Update to latest
curl -L $ISO_URL -o /tmp/proxmox-ve.iso
```

### 2. Launch QEMU for Installation
Install `ovmf` for UEFI support and start QEMU:
```bash
apt-get update && apt-get install -y ovmf

# Identify target disks (assuming /dev/sda and /dev/sdb)
PRIMARY_DISK=$(lsblk -dn -o NAME,SIZE,TYPE | grep disk | sed -n 1p | awk '{print $1}')
SECONDARY_DISK=$(lsblk -dn -o NAME,SIZE,TYPE | grep disk | sed -n 2p | awk '{print $1}')

qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
  -drive file=/dev/$PRIMARY_DISK,format=raw,media=disk,if=virtio,id=pdisk \
  -drive file=/dev/$SECONDARY_DISK,format=raw,media=disk,if=virtio,id=sdisk \
  -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,readonly=on \
  -drive file=/usr/share/OVMF/OVMF_VARS.fd,if=pflash,format=raw \
  -cdrom /tmp/proxmox-ve.iso -boot d \
  -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait

# Set VNC Password
echo "change vnc password YOUR_SECURE_PASSWORD" | nc -q 1 127.0.0.1 4444
```

### 3. Connect via VNC
On your local machine, open your VNC client (e.g., Finder > Connect to Server on macOS):
`vnc://<YOUR_SERVER_IP>:5900`

### 4. GUI Installation Steps
- **Target**: ZFS (RAID0 for performance or RAID1 for redundancy).
- **Hostname**: `pve.lan` (or your choice).
- **IP Address**: Use the public IP and gateway gathered in Phase 1.
- **Finish**: Uncheck "Automatically reboot" and click **Install**.

---

## Phase 3: Initial Configuration (Post-Install)

Once the installer finishes, **do not reboot yet**. We need to fix the networking so you don't lose access.

### 1. Close the Installation QEMU
```bash
printf "quit\n" | nc 127.0.0.1 4444
```

### 2. Boot the installed OS via QEMU
```bash
qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
  -drive file=/dev/$PRIMARY_DISK,format=raw,media=disk,if=virtio \
  -drive file=/dev/$SECONDARY_DISK,format=raw,media=disk,if=virtio \
  -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,readonly=on \
  -drive file=/usr/share/OVMF/OVMF_VARS.fd,if=pflash,format=raw \
  -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait \
  -net user,hostfwd=tcp::2222-:22 -net nic
```

### 3. Sync Network Config
From the Rescue System, transfer the correct interface configuration to the VM:
```bash
apt-get install -y sshpass

cat > /tmp/interfaces << EOF
auto lo
iface lo inet loopback
iface $INTERFACE_NAME inet manual

auto vmbr0
iface vmbr0 inet static
  address $IP_ADDRESS/$CIDR
  gateway $GATEWAY
  bridge_ports $INTERFACE_NAME
  bridge_stp off
  bridge_fd 0
EOF

sshpass -p "YOUR_ROOT_PASSWORD" scp -o StrictHostKeyChecking=no -P 2222 /tmp/interfaces root@localhost:/etc/network/interfaces
```

### 4. Final Reboot
Power down QEMU and reboot the physical server:
```bash
printf "system_powerdown\n" | nc 127.0.0.1 4444
shutdown -r now
```

---

## Phase 4: Proxmox SDN & Networking

After the server reboots, access the Proxmox UI at `https://<YOUR_SERVER_IP>:8006`.

### 1. Enable IP Forwarding
Crucial for NAT to work on Hetzner:
```bash
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forwarding.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-ip-forwarding.conf
sysctl -p /etc/sysctl.d/99-ip-forwarding.conf
```

### 2. Configure SDN (Simple NAT)
1.  **Zones**: Datacenter > SDN > Zones > Add **Simple**.
    - ID: `localnat`
    - IPAM: `pve`
    - DHCP: **Enabled**
2.  **VNets**: Datacenter > SDN > VNets > Add.
    - Name: `vnet0`
    - Zone: `localnat`
3.  **Subnets**: Select `vnet0` > Subnets > Create.
    - Subnet: `10.0.0.0/24`
    - Gateway: `10.0.0.1`
    - **SNAT**: **Checked** (Enables outbound internet access).
4.  **Apply**: Go to Datacenter > SDN and click **Apply**.

---

## Phase 5: Tailscale for Remote Management

To avoid exposing Proxmox to the public internet, we use Tailscale.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --advertise-routes=10.0.0.0/24
```

**Note**: Ensure UDP GRO is optimized for the bridge:
```bash
ethtool -K vmbr0 rx-udp-gro-forwarding on rx-gro-list off
```

---

## Summary of Results
- Proxmox is installed on Bare Metal via Rescue System.
- Networking is managed via SDN `vnet0` with 10.0.0.0/24 range.
- Outbound traffic is NATed through the host's public IP.
- Secure access is provided via Tailscale.
