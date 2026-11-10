output "chart_version" {
  value = helm_release.this.version
}

output "role_name" {
  value = module.identity.role_name
}
