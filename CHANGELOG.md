# Changelog

## [0.11.0](https://github.com/msavdert/homelab/compare/v0.10.0...v0.11.0) (2026-11-17)


### Features

* **observability:** victoria-metrics-k8s-stack with Grafana behind Keycloak realm lab (D42, D43) ([#47](https://github.com/msavdert/homelab/issues/47)) ([f72e66c](https://github.com/msavdert/homelab/commit/f72e66cc71b92e558020b16add6742c58c3bec46))


### Documentation

* close phase 10, Monitoring guide ([#48](https://github.com/msavdert/homelab/issues/48)) ([e7df60b](https://github.com/msavdert/homelab/commit/e7df60b75a92e32717cd4490176edd76d4ded504))
* open phase 10, monitoring with victoria-metrics-k8s-stack (D42, D43) ([#45](https://github.com/msavdert/homelab/issues/45)) ([b802644](https://github.com/msavdert/homelab/commit/b8026448b2c5de4339d22e71eafdaf7bbf405153))

## [0.10.0](https://github.com/msavdert/homelab/compare/v0.9.0...v0.10.0) (2026-11-17)


### Features

* **homepage:** Homepage behind Keycloak realm lab (D41) ([#42](https://github.com/msavdert/homelab/issues/42)) ([4e473ff](https://github.com/msavdert/homelab/commit/4e473ffe3b141853c83f7628cab66514188892da))


### Bug fixes

* **homepage:** mount proxmox.yaml so the read-only root does not crash /api/validate ([#43](https://github.com/msavdert/homelab/issues/43)) ([b833884](https://github.com/msavdert/homelab/commit/b833884a1a8b18a20b432861515096b98aa416e3))


### Documentation

* close phase 9, Homepage guide ([#44](https://github.com/msavdert/homelab/issues/44)) ([1f9b54a](https://github.com/msavdert/homelab/commit/1f9b54a28443083951556d6f87cb63a6e9f56009))
* open phase 9, the start page: Homepage behind Keycloak realm lab (D41) ([#40](https://github.com/msavdert/homelab/issues/40)) ([42e9b03](https://github.com/msavdert/homelab/commit/42e9b036bc78c0483537518cae367f683c913737))

## [0.9.0](https://github.com/msavdert/homelab/compare/v0.8.0...v0.9.0) (2026-11-17)


### Features

* **keycloak:** Keycloak Operator, cluster keycloak-db and Keycloak behind the gateway ([#36](https://github.com/msavdert/homelab/issues/36)) ([cbb2556](https://github.com/msavdert/homelab/commit/cbb2556249d58c381289b3bbea938a51e59d20f7))
* **keycloak:** request 1 GiB of memory, keep the 2 GiB limit (D40) ([#37](https://github.com/msavdert/homelab/issues/37)) ([e6ff256](https://github.com/msavdert/homelab/commit/e6ff256088aaa9775e08172a8ef7563029ae4cda))


### Documentation

* close phase 8, Keycloak guide ([#38](https://github.com/msavdert/homelab/issues/38)) ([93a494a](https://github.com/msavdert/homelab/commit/93a494a4d03955d7b0226b150bd39b5f46513da2))
* open phase 8 with Keycloak, one database cluster per application (D38, D39) ([#34](https://github.com/msavdert/homelab/issues/34)) ([9dc56a2](https://github.com/msavdert/homelab/commit/9dc56a2c30f3d3bd9a2fa387db0fb1a62c9d25d6))

## [0.8.0](https://github.com/msavdert/homelab/compare/v0.7.0...v0.8.0) (2026-11-16)


### Features

* **database:** CloudNativePG operator, Barman Cloud Plugin and cluster postgres ([#30](https://github.com/msavdert/homelab/issues/30)) ([adf2a8e](https://github.com/msavdert/homelab/commit/adf2a8e3675f1bcf7bfb7e7667375dc7204f5303))


### Documentation

* close phase 7, split retention gate step 6 (D37) ([#33](https://github.com/msavdert/homelab/issues/33)) ([f084646](https://github.com/msavdert/homelab/commit/f084646588eb4c2ad2611b7bbd5d2595f7aefe2b))
* database guide for phase 7, gate steps 1 to 5 ([#32](https://github.com/msavdert/homelab/issues/32)) ([458b2d1](https://github.com/msavdert/homelab/commit/458b2d198252e991cd7d077e18c72e4c96be7f2a))
* record the bucket-limited object-storage key for the cluster ([#27](https://github.com/msavdert/homelab/issues/27)) ([b223f4c](https://github.com/msavdert/homelab/commit/b223f4c83a6a04274576ad1b5f44d50ec631dc43))
* rewrite the README, add the MIT license and a contributing note ([#29](https://github.com/msavdert/homelab/issues/29)) ([b31127d](https://github.com/msavdert/homelab/commit/b31127d3f8882a723f325221969aa4ed57e46548))

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
