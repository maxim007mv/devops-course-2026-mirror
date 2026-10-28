#!/usr/bin/env bash
# Host-only network analogous to VirtualBox vboxnet0: 192.168.56.0/24, host = .1, DHCP .101-.254, no Internet (no NAT/forwarding)
set -e
ip link show hostonly0 >/dev/null 2>&1 || ip link add hostonly0 type bridge
ip addr replace 192.168.56.1/24 dev hostonly0
ip link set hostonly0 up
ip link show tap-devops >/dev/null 2>&1 || ip tuntap add dev tap-devops mode tap
ip link set tap-devops master hostonly0 up
pgrep -f "dnsmasq.*hostonly0" >/dev/null || dnsmasq --interface=hostonly0 --bind-interfaces --except-interface=lo \
  --dhcp-range=192.168.56.101,192.168.56.254,255.255.255.0,12h --dhcp-option=3 --dhcp-option=6 \
  --dhcp-host=52:54:00:12:34:02,192.168.56.101 --port=0 --pid-file=/run/dnsmasq-hostonly0.pid \
  --dhcp-leasefile=/var/lib/misc/dnsmasq-hostonly0.leases
