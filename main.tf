##############################################################################
# IBM Cloud Provider
##############################################################################
terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
      version = "~> 1.35.0"
    }
  }
}


/*
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  generation       = 2
  region           = var.VPC_Region
  ibmcloud_timeout = 300
  resource_group   = var.Resource_Group
}
*/

##############################################################################
# Variable block - See each variable description
##############################################################################

variable "VPC_Region" {
  default     = ""
  description = "The region where the VPC, networks, and Check Point VSI will be provisioned."
}

variable "Resource_Group" {
  default     = ""
  description = "The resource group that will be used when provisioning the Check Point VSI. If left unspecififed, the account's default resource group will be used."
}

variable "VPC_Name" {
  default     = ""
  description = "The VPC where the Check Point VSI will be provisioned."
}

variable "External_Subnet_ID" {
  default     = ""
  description = "The ID of the subnet that exists in front of the Check Point Security Gateway that will be provisioned (the 'external' network)."
}

variable "SSH_Key" {
  default     = ""
  description = "The pubic SSH Key that will be used when provisioning the Check Point VSI."
}

variable "VNF_CP-GW_Instance1" {
  default     = "checkpoint-gateway-1"
  description = "The name of the Check Point Security Gatewat that will be provisioned."
}

variable "VNF_CP-GW_Instance2" {
  default     = "checkpoint-gateway-2"
  description = "The name of the Check Point Security Gatewat that will be provisioned."
}

variable "VNF_Security_Group" {
  default     = ""
  description = "The name of the security group assigned to the Check Point VSI."
}

variable "VNF_Profile" {
  default     = "cx2-8x16"
  description = "The VNF profile that defines the CPU and memory resources. This will be used when provisioning the Check Point VSI."
}

variable "CP_Version" {
  default     = "R81"
  description = "The version of Check Point to deploy. R8040, R81"
}

variable "CP_Type" {
  default     = "Gateway"
  description = "(HIDDEN) Gateway or Management"
}

variable "vnf_license" {
  default     = ""
  description = "(HIDDEN) Optional. The BYOL license key that you want your cp virtual server in a VPC to be used by registration flow during cloud-init."
}

variable "ibmcloud_endpoint" {
  default     = "cloud.ibm.com"
  description = "(HIDDEN) The IBM Cloud environmental variable 'cloud.ibm.com' or 'test.cloud.ibm.com'"
}

variable "delete_custom_image_confirmation" {
  default     = ""
  description = "(HIDDEN) This variable is to get the confirmation from customers that they will delete the custom image manually, post successful installation of VNF instances. Customer should enter 'Yes' to proceed further with the installation."
}

variable "ibmcloud_api_key" {
  default     = ""
  description = "(HIDDEN) holds the user api key"
}

variable "TF_VERSION" {
 default = "0.12"
 description = "terraform engine version to be used in schematics"
}

variable tags {
  default = []
  type = list(string)
  description = "Tags to insert into deployed resources."
}

##############################################################################
# Data block 
##############################################################################

data "ibm_is_subnet" "cp_subnet" {
  identifier = var.External_Subnet_ID
}

data "ibm_is_ssh_key" "cp_ssh_pub_key" {
  name = var.SSH_Key
}

data "ibm_is_instance_profile" "vnf_profile" {
  name = var.VNF_Profile
}

data "ibm_is_region" "region" {
  name = var.VPC_Region
}

data "ibm_is_vpc" "cp_vpc" {
  name = var.VPC_Name
}

data "ibm_resource_group" "rg" {
  name = var.Resource_Group
}


##############################################################################
# Create Security Group
##############################################################################

resource "ibm_is_security_group" "ckp_security_group" {
  name           = var.VNF_Security_Group
  vpc            = data.ibm_is_vpc.cp_vpc.id
  resource_group = data.ibm_resource_group.rg.id
  tags = var.tags
}

#Egress All Ports
resource "ibm_is_security_group_rule" "allow_egress_all" {
  depends_on = [ibm_is_security_group.ckp_security_group]
  group      = ibm_is_security_group.ckp_security_group.id
  direction  = "outbound"
  remote     = "0.0.0.0/0"
}

#Ingress All Ports
resource "ibm_is_security_group_rule" "allow_ingress_all" {
  depends_on = [ibm_is_security_group.ckp_security_group]
  group      = ibm_is_security_group.ckp_security_group.id
  direction  = "inbound"
  remote     = "0.0.0.0/0"
}

locals {
  image_name = "${var.CP_Version}-${var.CP_Type}"
  image_id = lookup(local.image_map[local.image_name], var.VPC_Region)
}

##############################################################################
# Create Check Point Gateway 1
##############################################################################

resource "ibm_is_instance" "cp_gw_vsi_1" {
  depends_on     = [ibm_is_security_group_rule.allow_ingress_all]
  name           = var.VNF_CP-GW_Instance1
  image          = local.image_id
  profile        = data.ibm_is_instance_profile.vnf_profile.name
  resource_group = data.ibm_resource_group.rg.id

  #eth0
  primary_network_interface {
    name            = "eth0"
    subnet          = data.ibm_is_subnet.cp_subnet.id
    security_groups = [ibm_is_security_group.ckp_security_group.id]
    allow_ip_spoofing = true
  }

  tags = var.tags

  vpc  = data.ibm_is_vpc.cp_vpc.id
  zone = data.ibm_is_subnet.cp_subnet.zone
  keys = [data.ibm_is_ssh_key.cp_ssh_pub_key.id]

  #Custom UserData
  user_data = ""
  //user_data = file("user_data_gw1")

  timeouts {
    create = "15m"
    delete = "15m"
  }

  provisioner "local-exec" {
    command = "sleep 30"
  }
}

##############################################################################
# Create Check Point Gateway 2
##############################################################################

resource "ibm_is_instance" "cp_gw_vsi_2" {
  depends_on     = [ibm_is_security_group_rule.allow_ingress_all]
  name           = var.VNF_CP-GW_Instance2
  image          = local.image_id
  profile        = data.ibm_is_instance_profile.vnf_profile.name
  resource_group = data.ibm_resource_group.rg.id

  #eth0
  primary_network_interface {
    name            = "eth0"
    subnet          = data.ibm_is_subnet.cp_subnet.id
    security_groups = [ibm_is_security_group.ckp_security_group.id]
    allow_ip_spoofing = true
  }

  tags = var.tags
  
  vpc  = data.ibm_is_vpc.cp_vpc.id
  zone = data.ibm_is_subnet.cp_subnet.zone
  keys = [data.ibm_is_ssh_key.cp_ssh_pub_key.id]

  #Custom UserData
  user_data = ""
  //user_data = file("user_data_gw2")

  timeouts {
    create = "15m"
    delete = "15m"
  }

  provisioner "local-exec" {
    command = "sleep 30"
  }
}

output firewall_instance_ids {
  value = [ibm_is_instance.cp_gw_vsi_1.id, ibm_is_instance.cp_gw_vsi_2.id]
}

output firewall_network_ips {
  value = [ibm_is_instance.cp_gw_vsi_1.primary_network_interface[0].primary_ipv4_address, ibm_is_instance.cp_gw_vsi_2.primary_network_interface[0].primary_ipv4_address]
}
