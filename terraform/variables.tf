variable "vpc-cidr" {
  default = "10.0.0.0/16"
  description = "The VPC CIDR range for the internal network"
}

variable "azs" {
  description = "Availability zones"
  type        = map(string)
  default = {
    "1" = "ca-central-1a"
    "2" = "ca-central-1b"
  }

}
