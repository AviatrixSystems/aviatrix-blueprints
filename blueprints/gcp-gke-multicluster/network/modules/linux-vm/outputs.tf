output "vm_private_ip" {
  description = "Private IP of the test VM"
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "vm_name" {
  description = "Compute instance name"
  value       = google_compute_instance.this.name
}
