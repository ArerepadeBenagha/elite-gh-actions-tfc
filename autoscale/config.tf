terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.70.0"
    }
  }

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
  region = "ap-southeast-1"
}
