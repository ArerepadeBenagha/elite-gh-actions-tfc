terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.26.0"
    }
  }
  required_version = ">= 0.14"

  backend "remote" {
    organization = "EliteSolutionsIT"

    workspaces {
      name = "elite-gh-actions-test-autoscale"
    }
  }
}
terraform {
  required_version = ">=0.12"
}
provider "aws" {
  region = "us-east-1"
}
