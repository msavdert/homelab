# The Debian 12 (bookworm) generic cloud image is staged on Proxmox storage
# out-of-band (root-run `wget` into the `import` content path of the `local`
# storage), not downloaded by this Terraform config.
#
# Why: Proxmox VE 9.2.5's `/nodes/{node}/query-url-metadata` endpoint (used
# by the `proxmox_download_file` resource to fetch the image server-side)
# rejects API-token authentication with a bare "Permission check failed",
# even for a token holding `Sys.Audit` at `/` — the exact permission its own
# source (`PVE::API2::Nodes`) declares sufficient. This reproduces
# identically against the raw API with `curl`, so it isn't a Terraform
# provider bug. Ticket-based (interactive login) auth isn't an option either
# since `terraform@pve` is a token-only PVE-realm user by design (see
# ADR-0003/README) with no settable password. Root-cause is presumed to be a
# PVE-side gap in token support for this specific route; revisit if/when a
# future PVE point release fixes it, and switch back to
# `proxmox_download_file` at that point (it remains the ADR-0002-preferred
# mechanism).
#
# The image was staged once with:
#   ssh root@pve 'wget -O /var/lib/vz/import/debian-12-generic-amd64.qcow2 \
#     https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2'
#
# `template.tf` references it directly via the `local:import/...` volume ID
# below — Terraform still owns creating the template *from* this file, just
# not the download step itself.
locals {
  debian_image_volume_id = "${var.image_storage}:import/${var.debian_image_file_name}"
}
