output "resource-group-name" {
  value = "${var.prefix}-rg"
}

output "environment-tag" {
  value = "${var.prefix}-env"
}

output "vnet-name" {
  value = "${var.prefix}-vnet"
}

output "bosh-default-storage-name" {
  value = replace(lower(var.prefix), "/[^0-9a-z]/", "")
}

output "bosh-subnet-name" {
  value = "${var.prefix}-bosh-subnet"
}

output "bosh-sg-name" {
  value = "${var.prefix}-bosh-sg"
}
