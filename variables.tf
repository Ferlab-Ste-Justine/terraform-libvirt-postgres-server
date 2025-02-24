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

variable "data_volume_id" {
  description = "Id for an optional separate disk volume to attach to the vm on postgres' data path"
  type        = string
  default     = ""
}

variable "libvirt_networks" {
  description = "Parameters of libvirt network connections if libvirt networks are used."
  type = list(object({
    network_name = optional(string, "")
    network_id = optional(string, "")
    prefix_length = string
    ip = string
    mac = string
    gateway = optional(string, "")
    dns_servers = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for net in var.libvirt_networks: net.prefix_length != "" && net.ip != "" && net.mac != "" && ((net.network_name != "" && net.network_id == "") || (net.network_name == "" && net.network_id != ""))])
    error_message = "Each entry in libvirt_networks must have the following keys defined and not empty: prefix_length, ip, mac, network_name xor network_id"
  }
}

variable "macvtap_interfaces" {
  description = "List of macvtap interfaces."
  type        = list(object({
    interface     = string
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = optional(string, "")
    dns_servers   = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for int in var.macvtap_interfaces: int.interface != "" && int.prefix_length != "" && int.ip != "" && int.mac != ""])
    error_message = "Each entry in macvtap_interfaces must have the following keys defined and not empty: interface, prefix_length, ip, mac"
  }
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

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number,
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0,
      limit = 0
    }
  }
}

variable "fluentbit" {
  description = "Fluent-bit configuration"
  sensitive = true
  type = object({
    enabled = bool
    patroni_tag = string
    node_exporter_tag = string
    metrics = optional(object({
      enabled = bool
      port    = number
    }), {
      enabled = false
      port = 0
    })
    forward = object({
      domain = string
      port = number
      hostname = string
      shared_key = string
      ca_cert = string
    })
  })
  default = {
    enabled = false
    patroni_tag = ""
    node_exporter_tag = ""
    metrics = {
      enabled = false
      port = 0
    }
    forward = {
      domain = ""
      port = 0
      hostname = ""
      shared_key = ""
      ca_cert = ""
    }
  }
}

variable "vault_agent" {
  type = object({
    enabled = bool
    auth_method = object({
      config = object({
        role_id   = string
        secret_id = string
      })
    })
    vault_address   = string
    vault_ca_cert   = string
  })
  default = {
    enabled = false
    auth_method = {
      config = {
        role_id   = ""
        secret_id = ""
      }
    }
    vault_address = ""
    vault_ca_cert = ""
  }
}

variable "fluentbit_dynamic_config" {
  description = "Parameters for fluent-bit dynamic config if it is enabled"
  type = object({
    enabled = bool
    source  = string
    etcd    = optional(object({
      key_prefix     = string
      endpoints      = list(string)
      ca_certificate = string
      client         = object({
        certificate = string
        key         = string
        username    = string
        password    = string
      })
      vault_agent_secret_path = optional(string, "")
    }), {
      key_prefix     = ""
      endpoints      = []
      ca_certificate = ""
      client         = {
        certificate = ""
        key         = ""
        username    = ""
        password    = ""
      }
      vault_agent_secret_path = ""
    })
    git     = optional(object({
      repo             = string
      ref              = string
      path             = string
      trusted_gpg_keys = list(string)
      auth             = object({
        client_ssh_key         = string
        server_ssh_fingerprint = string
      })
    }), {
      repo             = ""
      ref              = ""
      path             = ""
      trusted_gpg_keys = []
      auth             = {
        client_ssh_key         = ""
        server_ssh_fingerprint = ""
      }
    })
  })
  default = {
    enabled = false
    source = "etcd"
    etcd = {
      key_prefix     = ""
      endpoints      = []
      ca_certificate = ""
      client         = {
        certificate = ""
        key         = ""
        username    = ""
        password    = ""
      }
      vault_agent_secret_path = ""
    }
    git  = {
      repo             = ""
      ref              = ""
      path             = ""
      trusted_gpg_keys = []
      auth             = {
        client_ssh_key         = ""
        server_ssh_fingerprint = ""
      }
    }
  }

  validation {
    condition     = contains(["etcd", "git"], var.fluentbit_dynamic_config.source)
    error_message = "fluentbit_dynamic_config.source must be 'etcd' or 'git'."
  }
}

variable "postgres" {
  description = "Postgres configurations"
  sensitive   = true
  type = object({
    params = optional(list(object({
      key = string,
      value = string,
    })), []),
    replicator_password = string,
    superuser_password = string,
    ca_certificate = string,
    server_certificate = string,
    server_key = string,
  })
}

variable "etcd" {
  description = "Etcd configurations"
  sensitive   = true
  type = object({
      endpoints = list(string),
      ca_cert = string,
      username = string,
      password = string,
  })
}

variable "patroni" {
  description = "Patroni configurations"
  sensitive   = true
  type = object({
    scope = string,
    namespace = string,
    name = string,
    ttl = number,
    loop_wait = number,
    retry_timeout = number,
    master_start_timeout = number,
    master_stop_timeout = number,
    watchdog_safety_margin = number,
    is_synchronous         = bool,
    synchronous_settings   = optional(object({
      strict = bool
      synchronous_node_count = number
    }), {
      strict = true
      synchronous_node_count = 1
    }),
    asynchronous_settings  = optional(object({
      maximum_lag_on_failover = number
    }), {
      //1MB
      maximum_lag_on_failover = 1048576
    }),
    client_certificate = string,
    client_key = string,
  })
}

variable "patroni_version" {
  description = "Version of patroni to install"
  type        = string
  default     = "4.0.4"
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type = bool
  default = true
}