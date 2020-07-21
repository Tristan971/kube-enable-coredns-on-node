# Add CoreDNS to a k8s' node's DNS servers

#### WARNING: 
    I DO NOT RECOMMEND USING THIS ON YOUR PRODUCTION CLUSTER
    
    THIS IS A WORKAROUND. 
    
    THE KUBERNETES TEAM HAS A VERY FAIR POINT IN THAT DNS 
    SETTINGS ARE NOT SOMETHING SETTABLE IN A PORTABLE WAY
    
    IT MOST LIKELY WON'T BREAK YOUR CLUSTER, BUT THAT DOES
    NOT MEAN IT'S NECESSARILY A GOOD IDEA EITHER

This little docker image, when ran on a node, will escape its container, and edit the node's `/etc/systemd/resolved.conf` 
to enable CoreDNS usage on the node itself.

As per: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/#known-issues
> Kubernetes installs do not configure the nodes' resolv.conf files to use the cluster DNS by default, 
> because that process is inherently distribution-specific. 
>
> This should probably be implemented eventually.

## Why

This is a cumbersome limitation because you might need to reference a service at the node level.

As an example, one situation where this is an issue with NFS-backed PersistentVolumes:
- Assuming you run an NFS server on a StatefulSet
- And that NFS server container is exported as `nfs-service`

Then you can't readily mount an NFS-type PersistentVolume that uses `nfs-service` for provision.

Indeed, the node is the one to mount the volume, not the pod. So the node will be the one trying to
communicate with `nfs-server`, and pathetically fail with `cannot resolve nfs-service.svc.cluster.local`

## How this works

### Executing commands on the node from a container

Using [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html), you can move across namespaces, and
thus escape your container's into the host's.

This solution is heavily inspired by [alexei-led/nsenter](https://github.com/alexei-led/nsenter), and basically
uses this, along with a privileged container spec, to execute commands directly on its host, the node.

### Adding CoreDNS to the host

TL;DR:

The container does the following on start:
- gets its ip from its `/etc/resolv.conf`
- gets the host's `/etc/systemd/resolv.conf`, and checks that it's not using CoreDNS already
- edits the host's `/etc/systemd/resolv.conf` to use CoreDNS
- runs `systemctl daemon-reload` followed by `systemctl restart systemd-resolved` to make systemd pick up the change
- then idles forever

#### Why does it do that though?

I noticed, that on [my cloud provider's host](https://scaleway.com/), DNS was managed externally, in a way
that I don't know the specifics of. Bummer.

However, when you add a DNS to `/etc/systemd/resolved.conf`, it ends up as part of the generated
`/etc/resolv.conf` and is used.

It just turns out that some config also happens 2 others in there, but that's not a problem. 
The more DNS servers the merrier... or something?

Anyway, this script does exactly that, it just replaces `#DNS=` with `DNS=<coredns ip>`.

Finally, to get the IP of coredns is not exactly difficult, as every pod uses it as its
only `nameserver` in `/etc/resolv.conf` (busybox ones do anyway).


### Running on all nodes

Following this, inspired this time by [Itay Shakury's DaemonSet single execution](http://blog.itaysk.com/2017/12/26/the-single-use-daemonset-pattern-and-prepulling-images-in-kubernetes)
we deploy this as a daemonset within our cluster, which makes it execute on every single node, past and future.

Now while the approach was originally that of the single-run, for various reasons (in case my cloud provider ever does
it automatically for example) it seemed easy enough to instead run a never-ending container (a-la `gcr/pause`)
by having it idle on finish instead. 

Of course, it is also "smart" enough to not indefinitely apply itself and instead
skip execution if it isn't needed (like if you manually restarted it for example).

I still mention the single-exec DaemonSet here because it was quite interesting of a pattern for future similar
workarounds, and might still be the right solution long-term for this.

## Usage

There's only one flag, `DRY_RUN`. 
- Unless it is defined, and has value `false`, the run will only print the resulting
`/etc/systemd/resolved.conf` that it would have written.
- If it is set to `true` the run will backup `/etc/systemd/resolved.conf` to `/etc/systemd/resolved.conf-<unix timestamp of run>-bak`

Here's a sample DaemonSet

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  namespace: kube-system
  name: node-coredns-enable
spec:
  selector:
    matchLabels:
      name: node-coredns-enable-ds
  template:
    metadata:
      labels:
        name: node-coredns-enable-ds
    spec:
      hostPID: true
      containers:
        - name: enable-coredns-on-node
          image: tristandeloche/kube-enable-coredns-on-node:0.1.0
          securityContext:
            privileged: true
          env:
            # please try true first, see if it doesn't seem to blow up your cluster, 
            # then use false if it seems to make sense with its output
            - name: 'DRY_RUN'
              value: 'true'
```
