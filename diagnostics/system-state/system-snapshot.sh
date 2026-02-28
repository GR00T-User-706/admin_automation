#!/bin/bash
echo "===== HOSTNAME ====="
hostnamectl
echo
echo "===== KERNEL ====="
uname -a
echo
echo "===== ACTIVE SERVICES ====="
systemctl --failed
echo
echo "===== LISTENING PORTS ====="
ss -tulnp
