#!/usr/bin/env bash
# NOTE: nested KVM on this host faults (kvm_spurious_fault), so TCG (software emulation) is used.
# devops-vm: 2048 MB RAM, 2 vCPU, 25 GB qcow2 (dynamic), NIC1 = NAT (user-mode, hostfwd), NIC2 = host-only (tap on bridge hostonly0)
# GUEST_SSH_PORT: 22 before Task 2, 2222 after (step 2.4)
GUEST_SSH_PORT=${GUEST_SSH_PORT:-2222}
cd "$(dirname "$0")"
exec qemu-system-x86_64 -name devops-vm -machine q35 -accel tcg,thread=multi,tb-size=512 -cpu max -smp 2 -m 2048 \
  -drive file=devops-vm.qcow2,if=virtio,format=qcow2 \
  -drive file=seed.iso,if=virtio,format=raw,readonly=on \
  -netdev user,id=nat,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:2222-:${GUEST_SSH_PORT} \
  -device virtio-net-pci,netdev=nat,mac=52:54:00:12:34:01 \
  -netdev tap,id=hostonly,ifname=tap-devops,script=no,downscript=no \
  -device virtio-net-pci,netdev=hostonly,mac=52:54:00:12:34:02 \
  -monitor unix:/workspace/pr5/vm/monitor.sock,server,nowait \
  -nographic
