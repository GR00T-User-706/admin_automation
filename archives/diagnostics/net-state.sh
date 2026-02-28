#!/bin/bash
func() {
	[[ -z "$1" ]] && { echo "Missing argument."; exit 1; }
	echo "$TODAY"
	echo "===== INTERFACES ====="
	ip -brief addr
	echo
	echo "===== ROUTES ====="
	ip route show
	echo
	echo "===== RULES ====="
	ip rule show
	echo
	echo "===== ARP ====="
	ip neigh show
	echo
	echo "===== NETWORKMANAGER DEVICES ====="
	nmcli device status
	nmcli connection show "$1"
}
func "$@"
