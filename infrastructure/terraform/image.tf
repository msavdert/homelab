# Downloads the Debian 12 (bookworm) generic cloud image directly into
# Proxmox storage via the API, so the base image is code-provisioned rather
# than manually staged. See ADR-0002 for why this image and this pattern
# were chosen over a Packer-built custom template, and ADR-0004 for why
# Terraform authenticates as `root@pam` (needed for this resource to work
# at all against a Proxmox permission-check quirk on non-root tokens).
resource "proxmox_download_file" "debian_12_cloudimg" {
  content_type = "import"
  datastore_id = var.image_storage
  node_name    = var.proxmox_node
  file_name    = var.debian_image_file_name
  url          = var.debian_image_url
  overwrite    = false

  # `url` isn't stored server-side, so a freshly imported resource (e.g.
  # after state loss on a new machine, see infrastructure/terraform/README.md)
  # always shows it as a spurious forces-replacement diff on the next plan.
  lifecycle {
    ignore_changes = [url]
  }
}
