#!/bin/env sh

DNS_SOURCE=/etc/systemd/resolved.conf
DNS_GENERATED=/etc/resolv.conf

COREDNS_IP=$(grep nameserver $DNS_GENERATED | head -n1 | cut -d' ' -f2)
echo "Using this IP for CoreDNS: $COREDNS_IP"
echo ""

# escape from container
run_on_host() {
  if [ -n "$2" ]; then
    echo "Executing blobs, pass them as string! Received: [$*]"
    exit 1
  fi

  nsenter -m -u -n -i -p -t 1 -- sh -c "set -x; $1"
}

idle() {
  true
}

HOST_ORIGINAL_SRC="$(run_on_host "cat $DNS_SOURCE")"
echo "Original host's $DNS_SOURCE:"
echo "---"
echo ""

echo "$HOST_ORIGINAL_SRC"

echo ""
echo "---"
echo ""

echo "Checking if the host doesn't already have CoreDNS ($COREDNS_IP) set..."
if echo "$HOST_ORIGINAL_SRC" | grep -o "$COREDNS_IP"; then
  echo "Already had $COREDNS_IP in host sources! Skipping straight to idling mode."
  idle
else
  echo "It does not. Proceeding."
fi
echo ""
echo "---"
echo ""

echo "Will prepend $COREDNS_IP to the DNS=... values on host"
PRE="^#?DNS=\(.*\)$"
POST="DNS=$COREDNS_IP,\\\1"
run_on_host "sed -E s/$PRE/$POST/g $DNS_SOURCE"

echo ""
echo "---"
echo ""

echo "Reloading systemd daemon"
run_on_host "systemctl daemon-reload"

echo "Restarting systemd-resolved"
run_on_host "systemctl restart systemd-resolved"

echo ""
echo "---"
echo ""

echo "Done applying DNS change. Now idling."
idle
