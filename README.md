# Add CoreDNS to a k8s' node DNS servers

This works around not being able to reference service by DNS name at
the node level, like when binding an NFS volume hoster on the cluster
for another node.

It works by getting a hold of the CoreDNS IP within the container,
escaping its container through `nsenter`, setting CoreDNS in the
standard `systemd-resolved` source (`/etc/systemd/resolved.conf`),
and then reloading the `systemd-resolved` service.

This should print the final (hopefully regenerated with CoreDNS' cluster ip) 
`/etc/resolv.conf`, and then pause forever (by tailing `/dev/null`).
