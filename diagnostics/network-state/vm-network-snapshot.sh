#!/bin/bash
echo "===== BRIDGES ====="
ip link show type bridge
echo
echo "===== VIRTUAL INTERFACES ====="
ip link | grep -E 'vnet|virbr|vmnet'
echo
echo "===== NAT TABLE ====="
sudo nft list ruleset
