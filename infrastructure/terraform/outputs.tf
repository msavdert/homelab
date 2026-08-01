output "debian_12_template_vm_id" {
  description = "VM ID of the Debian 12 cloud-init template, for later modules to clone from."
  value       = proxmox_virtual_environment_vm.debian_12_template.vm_id
}

output "debian_12_template_name" {
  description = "Name of the Debian 12 cloud-init template."
  value       = proxmox_virtual_environment_vm.debian_12_template.name
}
