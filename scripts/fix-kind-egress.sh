#!/usr/bin/env bash
# Kind's bridge is dropped by iptables-legacy FORWARD (policy DROP) on some
# Docker hosts, even when nftables already ACCEPTs it. Safe to re-run.
set -euo pipefail

BR_NAME="$(ip -o link show | awk -F': ' '/br-/{print $2}' | while read -r n; do
  addr="$(ip -4 addr show "$n" 2>/dev/null | awk '/inet /{print $2}')"
  [[ "$addr" == 172.18.* ]] && echo "$n" && break
done)"
if [[ -z "${BR_NAME:-}" ]]; then
  echo "kind bridge not found" >&2
  exit 1
fi

echo "Fixing legacy FORWARD for $BR_NAME"
sudo iptables-legacy -C DOCKER-FORWARD -i "$BR_NAME" -j ACCEPT 2>/dev/null \
  || sudo iptables-legacy -I DOCKER-FORWARD -i "$BR_NAME" -j ACCEPT
sudo iptables-legacy -C DOCKER-CT -o "$BR_NAME" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || sudo iptables-legacy -I DOCKER-CT -o "$BR_NAME" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables-legacy -t nat -C POSTROUTING -s 172.18.0.0/16 ! -o "$BR_NAME" -j MASQUERADE 2>/dev/null \
  || sudo iptables-legacy -t nat -A POSTROUTING -s 172.18.0.0/16 ! -o "$BR_NAME" -j MASQUERADE
echo "Kind egress fix applied"
