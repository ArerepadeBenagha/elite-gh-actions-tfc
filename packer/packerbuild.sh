#!/bin/bash
# ARTIFACT=`packer build -machine-readable packer-example.json |awk -F, '$0 ~/artifact,0,id/ {print $6}'`
ARTIFACT=`packer build -machine-readable packer-example.json
AMI_ID=`echo $ARTIFACT | cut -d ':' -f2`
echo 'variable "AMI_ID" { default = "'${AMI_ID}'" }' > amivar.tf
