variable "prefix" {
  type = "string"
}

variable "location" {
  type    = "string"
  default = "westus"
}

variable "network_cidr" {
  default = "10.0.0.0/16"
}
