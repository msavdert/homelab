# 05 Ingress

## What this adds

A service in the cluster can be reached by name over HTTPS from any device
on the tailnet. `https://<name>.lab.savdert.com` resolves in public DNS to
10.0.6.20, an address on the lab network that Cilium answers for on layer 2.
Behind it, Envoy Gateway 1.10.0 terminates TLS with a Let's Encrypt
wildcard certificate that cert-manager v1.21.3 renews by DNS-01 against
Cloudflare. From the internet the name still resolves, but nothing
routes to the address. Besides the tailnet, guests on the Proxmox host's
`vnet0` can reach it through the host (D21).

```
device on the tailnet
  -> DNS: *.lab.savdert.com = 10.0.6.20 (Cloudflare, not proxied)
  -> Tailscale subnet router -> Proxmox VNet 10.0.6.0/24
  -> the node holding the L2 lease answers ARP for 10.0.6.20 (Cilium)
  -> Service envoy-network-lab-* (LoadBalancer, externalTrafficPolicy Cluster)
  -> Envoy proxy (2 pods, different nodes), TLS with *.lab.savdert.com
  -> HTTPRoute -> the application's Service
```

## Before you start

- [04 Secrets](04-secrets.md): External Secrets reads vault
  `homelab-cluster`.
- Item `cloudflare-dns`, field `credential`, in vault `homelab-cluster`
  (for cert-manager) and in vault `homelab` (for `mise run dns:apply`). The
  token can edit DNS in zone `savdert.com` only (checked 2026-11-15).
- The tailnet routes 10.0.6.0/24 to the lab (see
  [Handoff](../handoff.md), "Tailscale").
- Addresses 10.0.6.20 to 10.0.6.29 are free on the VNet. The Proxmox DHCP
  range is 10.0.6.200 to 10.0.6.250.

## Steps

### 1. The layout

```
kubernetes/apps/
  kube-system/cilium/
    app/values.yaml          l2announcements.enabled: true
    config/                  Kustomization cilium-config
      ippool.yaml            CiliumLoadBalancerIPPool lab, 10.0.6.20-29
      l2policy.yaml          CiliumL2AnnouncementPolicy lab, eth0
  cert-manager/cert-manager/
    app/                     Kustomization cert-manager (chart, CRDs)
    issuers/                 Kustomization cert-manager-issuers
      cloudflare-dns.yaml    ExternalSecret -> Secret cloudflare-dns
      letsencrypt.yaml       ClusterIssuer letsencrypt (DNS-01)
  network/envoy-gateway/
    app/                     Kustomization envoy-gateway (chart, CRDs)
    gateway/                 Kustomization envoy-gateway-gateway
      certificate.yaml       *.lab.savdert.com -> Secret lab-savdert-com-tls
      envoyproxy.yaml        proxy Deployment and Service settings
      gatewayclass.yaml      GatewayClass envoy
      gateway.yaml           Gateway lab, HTTPS on 443
infra/dns/apply.py           the DNS record (mise run dns:apply)
```

Order on a new cluster, expressed with `dependsOn`: `cilium-config` after
`cilium`; `cert-manager-issuers` after `cert-manager` and
`external-secrets-stores`; `envoy-gateway-gateway` after `envoy-gateway`,
`cert-manager-issuers` and `cilium-config`. The last one is Ready only when
the Certificate is Ready and the Gateway is Programmed, so it can take a few
minutes (timeout 10 minutes).

### 2. Layer-2 addresses (Cilium)

LB IPAM is always on in Cilium and wakes up when the first pool exists; it
needs no Helm value. Layer-2 announcements do:
`l2announcements.enabled: true` in the Cilium values. Changing it restarts
the Cilium agents (D26).

The policy selects interface `^eth0$` (read from `talosctl get links` and
`cilium-dbg status`) and has no node selector. The example in the Cilium
documentation excludes control-plane nodes; here all three nodes are
control-plane nodes, so that example would leave no node to announce.

One node at a time holds a Lease per Service
(`kubectl -n kube-system get lease | grep l2announce`) and answers ARP for
the address. With the default lease timings (15 s duration, 5 s renew
deadline) a lost node is replaced in 10 to 20 seconds, according to the
Cilium documentation. The client rate limit stays at its default: the
documented formula, Services divided by the renew deadline, gives 0.2
requests per second for one Service.

### 3. Certificates (cert-manager)

The chart installs its CRDs as templates (`crds.enabled: true`), so they
move with the chart. The ExternalSecret copies `cloudflare-dns/credential`
into Secret `cloudflare-dns`, key `api-token`; the ClusterIssuer
`letsencrypt` uses it for DNS-01 in zone `savdert.com`, against the Let's
Encrypt production endpoint.

cert-manager does not use Gateway API (D34). The wildcard certificate is an
ordinary `Certificate`; the Gateway names its Secret.

### 4. The gateway (Envoy Gateway)

The chart `gateway-helm` installs the Gateway API CRDs (experimental
channel, bundle version 1.6.1) and its own CRDs from the `crds/` directory
of a subchart. Helm installs such files but never upgrades them, so the
HelmRelease sets `install.crds` and `upgrade.crds` to `CreateReplace`
(D34): a Renovate update moves CRDs and controller together.

The `EnvoyProxy` named `lab` shapes what Envoy Gateway creates for the
Gateway:

- `externalTrafficPolicy: Cluster`. The default is `Local`, which does not
  work with layer-2 announcements: the announcing node drops traffic when
  no proxy runs on it. In the gate, k8s-3 announced while the proxies ran
  on k8s-1 and k8s-2.
- annotation `lbipam.cilium.io/ips: "10.0.6.20"`, the fixed address.
- two proxy replicas with required anti-affinity on label `app: envoy-lab`,
  so a node reboot leaves one proxy running.

The Gateway `lab` has one listener, HTTPS on 443 for `*.lab.savdert.com`,
and accepts routes from every namespace. There is no HTTP listener.

### 5. The DNS record

One static record, `*.lab.savdert.com` A 10.0.6.20, not proxied, kept by
`infra/dns/apply.py`:

```
mise run dns:apply --check   # read-only: exists / missing / differs, exit 1 unless correct
mise run dns:apply           # create or correct it; a second run says "exists"
```

The task takes the read-write token of vault `homelab` from vault
`dotfiles` for this one command and injects `op://homelab/cloudflare-dns/credential`
with `op run`. The script prints what it did, never the token.

## Check

Run on 2026-11-15, UTC. Pull request #21 was merged at 18:49:22; after
`flux reconcile kustomization flux-system --with-source` every
Kustomization was Ready at 18:52:33, the Cilium agents had rolled, and the
certificate was issued. Its `notBefore` lies one hour before issuance;
assumption, not checked in the Let's Encrypt documentation: Let's Encrypt
backdates it against clock skew.

```
$ kubectl -n network get certificate,gateway
NAME                                          READY   SECRET                AGE
certificate.cert-manager.io/lab-savdert-com   True    lab-savdert-com-tls   100s

NAME                                    CLASS   ADDRESS     PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/lab   envoy   10.0.6.20   True         100s

$ kubectl -n network get secret lab-savdert-com-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -subject -dates
issuer=C = US, O = Let's Encrypt, CN = YR1
subject=CN = *.lab.savdert.com
notBefore=Nov 15 17:53:46 2026 GMT
notAfter=Feb 13 17:53:45 2027 GMT

$ mise run dns:apply
created  A *.lab.savdert.com -> 10.0.6.20
$ mise run dns:apply --check
exists   A *.lab.savdert.com -> 10.0.6.20
```

From the agent box, which reaches the VNet through the host. The echo
fixture used here was removed after phase 8; repeat these checks against
`keycloak.lab.savdert.com`:

```
$ curl -sS -m 10 https://echo.lab.savdert.com/ -o /dev/null -w '%{http_code} %{ssl_verify_result}\n'
200 0
```

From the owner's Mac on the tailnet, then with Tailscale switched off:

```
$ curl -sS -m 10 https://echo.lab.savdert.com/ -o /dev/null -w '%{http_code} %{ssl_verify_result}\n'
200 0
$ curl -sS --connect-timeout 5 https://echo.lab.savdert.com/; echo "exit $?"
curl: (28) Failed to connect to echo.lab.savdert.com port 443 after 5003 ms: Timeout was reached
exit 28
```

Exit 28 rather than 6: the name resolves without the tailnet and only the
route is missing. The home router passes a public answer with a private
address, so no nameserver override in the tailnet's DNS settings was
needed.

Address failover, from the agent box. k8s-3 held the lease; a request
every second ran while it rebooted:

```
$ kubectl -n kube-system get lease | grep l2announce
cilium-l2announce-network-envoy-network-lab-fc186300   k8s-3   53s
$ talosctl -n 10.0.6.13 reboot --wait=false            # 18:53:20
$ kubectl wait --for=condition=Ready nodes --all --timeout=10m
$ awk '{print $2}' lb.log | sort | uniq -c             # 18:53:10 to 18:54:46
     89 200
$ kubectl -n kube-system get lease | grep l2announce
cilium-l2announce-network-envoy-network-lab-fc186300   k8s-2   2m29s
```

The node really went down: its kernel booted at 18:54:06 (`talosctl dmesg`)
and Kubernetes recorded a `Rebooted` event with a new boot id. The longest
interval between two log lines was 2 seconds, so there was no gap. The
explanation, an assumption not proven here: a Talos reboot shuts down
cleanly, the Cilium agent gives up its lease as it stops, and another node
takes over at once. A hard
failure (power cut, hung VM) waits for the lease to expire, 15 seconds by
default; that case was not tested.

## Day-two tasks

- **Expose a service.**
  1. Next to the application, add an HTTPRoute; the Service and port are
     the application's own:

     ```yaml
     apiVersion: gateway.networking.k8s.io/v1
     kind: HTTPRoute
     metadata:
       name: <app>
       namespace: <ns>
     spec:
       parentRefs:
         - name: lab
           namespace: network
           sectionName: https
       hostnames:
         - <app>.lab.savdert.com
       rules:
         - backendRefs:
             - name: <service>
               port: <port>
     ```

  2. Merge. No DNS change and no new certificate are needed: the wildcard
     covers every `<name>.lab.savdert.com`. Names one level deeper
     (`a.b.lab.savdert.com`) are not covered.
  3. Check: `kubectl -n <ns> get httproute <app>` shows the parent
     `Accepted`, and `curl https://<app>.lab.savdert.com/` answers from a
     tailnet device.
- **Another LoadBalancer Service.** Any Service of type LoadBalancer gets
  the next free address of the pool and is announced the same way. Pick
  one with `lbipam.cilium.io/ips`. Use `externalTrafficPolicy: Cluster`.
- **Upgrade.** Renovate proposes the chart tags in the two
  `ocirepository.yaml` files. Envoy Gateway's CRDs move with the chart;
  read its upgrade notes for a Gateway API version change first.

## When it goes wrong

- **Gateway has no address or is not Programmed.** `kubectl -n network
  get svc` shows the proxy Service; `EXTERNAL-IP` pending means LB IPAM
  did not allocate: `kubectl get ciliumloadbalancerippool lab` must show
  free addresses and no conflict.
- **The address does not answer ARP.** There is no `l2announce` lease for
  the Service: check `l2announcements.enabled` in the Cilium ConfigMap
  (`enable-l2-announcements: "true"`) and that the policy's interface
  matches the node's (`talosctl get links`).
- **Connections hang on one node only.** The proxy Service uses
  `externalTrafficPolicy: Local`; it must be `Cluster` (EnvoyProxy
  `lab`).
- **Certificate stays not Ready.** `kubectl -n network describe
  certificate lab-savdert-com`, then the `Challenge` objects in that
  namespace. A Cloudflare error points at the token or Secret
  `cert-manager/cloudflare-dns`; `kubectl -n cert-manager get
  externalsecret cloudflare-dns` must show `SecretSynced`.
- **The name does not resolve on a device (`curl` exit 6).** The local
  router drops answers with private addresses. Set a global nameserver
  such as 1.1.1.1 in the tailnet's DNS settings.

## Sources

- Cilium 1.20, "LoadBalancer IP Address Management (LB IPAM)":
  https://docs.cilium.io/en/v1.20/network/lb-ipam/
- Cilium 1.20, "L2 Announcements / L2 Aware LB":
  https://docs.cilium.io/en/v1.20/network/l2-announcements/
- Envoy Gateway, "Install with Helm" and "Customize EnvoyProxy":
  https://gateway.envoyproxy.io/latest/install/install-helm/ and
  https://gateway.envoyproxy.io/latest/tasks/operations/customize-envoyproxy/
- Envoy Gateway v1.10.0 release notes:
  https://github.com/envoyproxy/gateway/releases/tag/v1.10.0
- `gateway-helm` 1.10.0 itself (pulled and read): `Chart.yaml`, the
  subchart `crds`, the EnvoyProxy CRD schema (`externalTrafficPolicy`
  default `Local`).
- cert-manager, "Gateway API" and "Cloudflare" DNS-01:
  https://cert-manager.io/docs/usage/gateway/ and
  https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/
- Reference: onedr0p/home-ops, `kubernetes/apps/network/envoy-gateway/` and
  `kubernetes/apps/cert-manager/`.
- Decision D34 in [Decisions](../decisions.md).
