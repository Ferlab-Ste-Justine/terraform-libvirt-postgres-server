locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_interfaces = concat(
    [for libvirt_network in var.libvirt_networks: {
      network_name = libvirt_network.network_name != "" ? libvirt_network.network_name : null
      network_id = libvirt_network.network_id != "" ? libvirt_network.network_id : null
      macvtap = null
      addresses = null
      mac = libvirt_network.mac
      hostname = null
    }],
    [for macvtap_interface in var.macvtap_interfaces: {
      network_name = null
      network_id = null
      macvtap = macvtap_interface.interface
      addresses = null
      mac = macvtap_interface.mac
      hostname = null
    }]
  )
  ips = concat(
    [for libvirt_network in var.libvirt_networks: libvirt_network.ip],
    [for macvtap_interface in var.macvtap_interfaces: macvtap_interface.ip]
  )
  volumes = var.data_volume_id != "" ? [var.volume_id, var.data_volume_id] : [var.volume_id]
  fluentbit_updater_etcd = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "etcd"
  fluentbit_updater_git = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "git"
}

module "network_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//network?ref=v0.29.0"
  network_interfaces = concat(
    [for idx, libvirt_network in var.libvirt_networks: {
      ip = libvirt_network.ip
      gateway = libvirt_network.gateway
      prefix_length = libvirt_network.prefix_length
      interface = "libvirt${idx}"
      mac = libvirt_network.mac
      dns_servers = libvirt_network.dns_servers
    }],
    [for idx, macvtap_interface in var.macvtap_interfaces: {
      ip = macvtap_interface.ip
      gateway = macvtap_interface.gateway
      prefix_length = macvtap_interface.prefix_length
      interface = "macvtap${idx}"
      mac = macvtap_interface.mac
      dns_servers = macvtap_interface.dns_servers
    }]
  )
}

module "postgres_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//postgres?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  advertise_ip = local.ips.0
  etcd = var.etcd
  postgres = {
    replicator_password = var.postgres.replicator_password
    superuser_password  = var.postgres.superuser_password
    ca_cert             = var.postgres.ca.certificate
    server_cert         = "${tls_locally_signed_cert.pg_certificate.cert_pem}\n${var.postgres.ca.certificate}"
    server_key          = tls_private_key.pg_key.private_key_pem
    params              = var.postgres.params
  }
  patroni = {
    scope                  = var.patroni.scope
    namespace              = var.patroni.namespace
    name                   = var.patroni.name
    ttl                    = var.patroni.ttl
    loop_wait              = var.patroni.loop_wait
    retry_timeout          = var.patroni.retry_timeout
    master_start_timeout   = var.patroni.master_start_timeout
    master_stop_timeout    = var.patroni.master_stop_timeout
    watchdog_safety_margin = var.patroni.watchdog_safety_margin
    is_synchronous         = var.patroni.is_synchronous
    synchronous_settings   = var.patroni.synchronous_settings
    asynchronous_settings  = var.patroni.asynchronous_settings
    api                    = {
      ca_cert       = var.postgres.ca.certificate
      server_cert   = "${tls_locally_signed_cert.pg_certificate.cert_pem}\n${var.postgres.ca.certificate}"
      server_key    = tls_private_key.pg_key.private_key_pem
      client_cert   = tls_private_key.patroni_client_key.private_key_pem
      client_key    = tls_locally_signed_cert.patroni_client_certificate.cert_pem
    }
  }
  patroni_version = "4.0.4"   
}

module "prometheus_node_exporter_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=v0.29.0"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "fluentbit_updater_etcd_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//configurations-auto-updater?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path = "/etc/fluent-bit-customization/dynamic-config"
    files_permission = "700"
    directories_permission = "700"
  }
  etcd = {
    key_prefix = var.fluentbit_dynamic_config.etcd.key_prefix
    endpoints = var.fluentbit_dynamic_config.etcd.endpoints
    connection_timeout = "60s"
    request_timeout = "60s"
    retry_interval = "4s"
    retries = 15
    auth = {
      ca_certificate = var.fluentbit_dynamic_config.etcd.ca_certificate
      client_certificate = var.fluentbit_dynamic_config.etcd.client.certificate
      client_key = var.fluentbit_dynamic_config.etcd.client.key
      username = var.fluentbit_dynamic_config.etcd.client.username
      password = var.fluentbit_dynamic_config.etcd.client.password
    }
  }
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
  vault_agent = {
    etcd_auth = {
        enabled = var.fluentbit_dynamic_config.etcd.vault_agent_secret_path != ""
        secret_path = var.fluentbit_dynamic_config.etcd.vault_agent_secret_path
    }
  }
}

module "fluentbit_updater_git_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//gitsync?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path = "/etc/fluent-bit-customization/dynamic-config"
    files_permission = "700"
    directories_permission = "700"
  }
  git = var.fluentbit_dynamic_config.git
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
}

module "fluentbit_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluent-bit?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  fluentbit = {
    metrics = var.fluentbit.metrics
    systemd_services = [
      {
        tag     = var.fluentbit.patroni_tag
        service = "patroni.service"
      },
      {
        tag     = var.fluentbit.node_exporter_tag
        service = "node-exporter.service"
      }
    ]
    forward = var.fluentbit.forward
  }
  dynamic_config = {
    enabled = var.fluentbit_dynamic_config.enabled
    entrypoint_path = "/etc/fluent-bit-customization/dynamic-config/index.conf"
  }
}

module "vault_agent_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//vault-agent?ref=v0.29.0"
  install_dependencies = var.install_dependencies
  vault_agent = {
    auth_method = var.vault_agent.auth_method
    vault_address = var.vault_agent.vault_address
    vault_ca_cert = var.vault_agent.vault_ca_cert
    extra_config = ""
  }
}

module "data_volume_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//data-volumes?ref=v0.29.0"
  volumes = [{
    label         = "postgres_data"
    device        = "vdb"
    filesystem    = "ext4"
    mount_path    = "/var/lib/postgresql"
    mount_options = "defaults"
  }]
}

locals {
  cloudinit_templates = concat([
      {
        filename     = "base.cfg"
        content_type = "text/cloud-config"
        content = templatefile(
          "${path.module}/files/user_data.yaml.tpl", 
          {
            hostname = var.name
            ssh_admin_public_key = var.ssh_admin_public_key
            ssh_admin_user = var.ssh_admin_user
            admin_user_password = var.admin_user_password
          }
        )
      },
      {
        filename     = "postgres.cfg"
        content_type = "text/cloud-config"
        content      = module.postgres_configs.configuration
      },
      {
        filename     = "node_exporter.cfg"
        content_type = "text/cloud-config"
        content      = module.prometheus_node_exporter_configs.configuration
      }
    ],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    local.fluentbit_updater_etcd ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_etcd_configs.configuration
    }] : [],
    local.fluentbit_updater_git ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_git_configs.configuration
    }] : [],
    var.fluentbit.enabled ? [{
      filename     = "fluent_bit.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_configs.configuration
    }] : [],
    var.vault_agent.enabled ? [{
      filename     = "vault_agent.cfg"
      content_type = "text/cloud-config"
      content      = module.vault_agent_configs.configuration
    }] : [],
    var.data_volume_id != "" ? [{
      filename     = "data_volume.cfg"
      content_type = "text/cloud-config"
      content      = module.data_volume_configs.configuration
    }]: []
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "libvirt_cloudinit_disk" "postgres" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = module.network_configs.configuration
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "postgres" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  dynamic "disk" {
    for_each = local.volumes
    content {
      volume_id = disk.value
    }
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      network_name = network_interface.value["network_name"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.postgres.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}