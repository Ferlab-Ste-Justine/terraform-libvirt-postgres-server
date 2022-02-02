variable "name" {
  description = "Name to give to the vm."
  type        = string
}

variable "vcpus" {
  description = "Number of vcpus to assign to the vm"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MiB"
  type        = number
  default     = 8192
}

variable "volume_id" {
  description = "Id of the disk volume to attach to the vm"
  type        = string
}

variable "network_id" {
  description = "Id of the libvirt network to connect the vm to if you plan on connecting the vm to a libvirt network"
  type        = string
  default     = ""
}

variable "macvtap_interface" {
  description = "Interface that you plan to connect your vm to via a lower macvtap interface. Note that either this or network_id should be set, but not both."
  type        = string
  default     = ""
}

variable "macvtap_vm_interface_name_match" {
  description = "Expected pattern of the network interface name in the vm."
  type        = string
  //https://github.com/systemd/systemd/blob/main/src/udev/udev-builtin-net_id.c#L932
  default     = "en*"
}

variable "macvtap_subnet_prefix_length" {
  description = "Length of the subnet prefix (ie, the yy in xxx.xxx.xxx.xxx/yy). Used for macvtap only."
  type        = string
  default     = ""
}

variable "macvtap_gateway_ip" {
  description = "Ip of the physical network's gateway. Used for macvtap only."
  type        = string
  default     = ""
}

variable "macvtap_dns_servers" {
  description = "Ip of dns servers to setup on the vm, useful mostly during the initial cloud-init bootstraping to resolve domain of installables. Used for macvtap only."
  type        = list(string)
  default     = []
}

variable "ip" {
  description = "Ip address of the vm"
  type        = string
}

variable "mac" {
  description = "Mac address of the vm"
  type        = string
  default     = ""
}

variable "cloud_init_volume_pool" {
  description = "Name of the volume pool that will contain the cloud init volume"
  type        = string
}

variable "cloud_init_volume_name" {
  description = "Name of the cloud init volume"
  type        = string
  default = ""
}

variable "ssh_admin_user" { 
  description = "Pre-existing ssh admin user of the image"
  type        = string
  default     = "ubuntu"
}

variable "admin_user_password" { 
  description = "Optional password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_admin_public_key" {
  description = "Public ssh part of the ssh key the admin will be able to login as"
  type        = string
}


variable "postgres_image" {
  description = "Name of the docker image that will be used to provision postgres"
  type = string
}

variable "postgres_params" {
  description = "Extra parameters to pass to the postgres binary"
  type = string
  default = ""
}

variable "postgres_user" {
  description = "User that will access the database"
  type = string
}

variable "postgres_database" {
  description = "Name of the database that will be generated"
  type = string
}

variable "postgres_password" {
  description = "Password of the user who will access the database. If no value is provided, a random value will be generated"
  type = string
  default = ""
}

variable "ca" {
  description = "The ca that will sign the db's certificate. Should have the following keys: key, key_algorithm, certificate"
  type = any
}

variable "domains" {
  description = "Domains of the database, which will be used for the certificate"
  type = list(string)
}

variable "organization" {
  description = "The organization of the postgres certificate"
  type = string
  default = "Ferlab"
}

variable "certificate_validity_period" {
  description = "The postgres' certificate's validity period in hours"
  type = number
  default = 100*365*24
}

variable "certificate_early_renewal_period" {
  description = "The postgres' certificate's early renewal period in hours"
  type = number
  default = 365*24
}

variable "key_length" {
  description = "The key length of the certificate's private key"
  type = number
  default = 4096
}