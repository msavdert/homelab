# Changelog

## [0.7.0](https://github.com/msavdert/homelab/compare/v0.6.0...v0.7.0) (2026-11-16)


### Features

* **storage:** local-path-provisioner on a Talos user volume ([#24](https://github.com/msavdert/homelab/issues/24)) ([4145f3a](https://github.com/msavdert/homelab/commit/4145f3a474698320be99a9edeb3ff953c35cae07))


### Documentation

* add the storage guide and close phase 6 ([#26](https://github.com/msavdert/homelab/issues/26)) ([77eadac](https://github.com/msavdert/homelab/commit/77eadacd1c67c7661d59742c6b1a290b05b6bbe3))

## [0.6.0](https://github.com/msavdert/homelab/compare/v0.5.0...v0.6.0) (2026-11-16)


### Features

* **network:** serve the lab over Envoy Gateway with a Let's Encrypt wildcard ([#21](https://github.com/msavdert/homelab/issues/21)) ([8dea0f5](https://github.com/msavdert/homelab/commit/8dea0f509831eeb154e9ef0c0e2db7978ddf99d0))


### Documentation

* add the ingress guide and close phase 5 ([#23](https://github.com/msavdert/homelab/issues/23)) ([cb84fba](https://github.com/msavdert/homelab/commit/cb84fba675e8c83824264f2da418eda65754e54f))

## [0.5.0](https://github.com/msavdert/homelab/compare/v0.4.0...v0.5.0) (2026-11-15)


### Features

* **external-secrets:** read vault homelab-cluster with External Secrets ([#18](https://github.com/msavdert/homelab/issues/18)) ([84a84f4](https://github.com/msavdert/homelab/commit/84a84f407d97885b6e4590b075e13b37f1465413))


### Documentation

* add the secrets guide and close phase 4 ([#20](https://github.com/msavdert/homelab/issues/20)) ([d65f99c](https://github.com/msavdert/homelab/commit/d65f99cb3d3c7cd61ed78ec7a0fb7d91bf177db3))

## [0.4.0](https://github.com/msavdert/homelab/compare/v0.3.0...v0.4.0) (2026-11-15)


### Features

* **cilium:** annotate the agent pods as managed by Flux ([#16](https://github.com/msavdert/homelab/issues/16)) ([671c856](https://github.com/msavdert/homelab/commit/671c856df4ec50bfec90bb1816d5361564b3e11e))
* **flux:** reconcile the cluster from kubernetes/apps with Flux Operator ([#13](https://github.com/msavdert/homelab/issues/13)) ([519bbc0](https://github.com/msavdert/homelab/commit/519bbc07607de2ce43d8d20aa50e86ca8564c3e7))


### Bug fixes

* **flux:** stop helm-controller from appending the chart digest ([#15](https://github.com/msavdert/homelab/issues/15)) ([409e499](https://github.com/msavdert/homelab/commit/409e499ed8c729f9a45bdf2df8e63f0129a94b2e))


### Documentation

* add the Flux guide and close phase 3 ([#17](https://github.com/msavdert/homelab/issues/17)) ([59a8ea4](https://github.com/msavdert/homelab/commit/59a8ea49cd05c72396693c2729658e72de9233e8))

## [0.3.0](https://github.com/msavdert/homelab/compare/v0.2.0...v0.3.0) (2026-11-15)


### Features

* **talos:** build the cluster with Talos and Cilium ([#11](https://github.com/msavdert/homelab/issues/11)) ([b125224](https://github.com/msavdert/homelab/commit/b12522479f2692d975ed81f55e29839aac250c61))

## [0.2.0](https://github.com/msavdert/homelab/compare/v0.1.0...v0.2.0) (2026-11-15)


### Features

* **infra:** create the three Talos nodes with OpenTofu ([#9](https://github.com/msavdert/homelab/issues/9)) ([f299813](https://github.com/msavdert/homelab/commit/f299813d9a981ad0c41a998b64f0411eeddb04fe))

## 0.1.0 (2026-11-15)


### Features

* design, rules and host preparation for the lab ([3622216](https://github.com/msavdert/homelab/commit/362221651d096019ca9ce28844040353e6742e11))


### Documentation

* add the repository guide and close phase 0 ([#8](https://github.com/msavdert/homelab/issues/8)) ([1f1a72d](https://github.com/msavdert/homelab/commit/1f1a72da018d7bc9443f5afb2871acf34c1655a7))
* record the tailnet reachability test from the owner's device ([#1](https://github.com/msavdert/homelab/issues/1)) ([2a3a663](https://github.com/msavdert/homelab/commit/2a3a6631e8a9efe33b9077a558bfcda19f3b7f75))
