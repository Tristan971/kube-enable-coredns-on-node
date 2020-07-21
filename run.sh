#!/bin/env sh

COREDNS=$(grep nameserver /etc/resolv.conf | head -n1 | cut -d' ' -f2)
echo "Using this IP for CoreDNS: $COREDNS"
echo ""
echo ""

# escape from container
# execute shell command
# edit host systemd/resolved.conf to prepend coredns' ip to the list of main DNS=...
# reload systemd daemon
# restart resolved service to regenerate /etc/resolv.conf
# print final result
nsenter -m -u -n -i -p -t 1 -- sh -c "\
\
sed -E \"s/^#?DNS=(.*)/DNS=$COREDNS,\1/g\" \"/etc/systemd/resolved.conf\" &&\
\
systemctl daemon-reload
systemctl restart systemd-resolved
\
echo \"\" && echo \"--- DONE. Result follows ---\" && echo \"\" &&\
\
cat /etc/resolv.conf &&\
\
echo \"\" && echo \"Now pausing.\" &&\
tail -f /dev/null"
