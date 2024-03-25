terraform {
  required_version = "~> 1.7.0"
  required_providers {
    aws = {
      version = "~> 5.42.0"
    }
    tls = {
      version = "~> 4.0.5"
    }
    local = {
      version = "~> 2.5.0"
    }
  }
}