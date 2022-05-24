locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_config = templatefile(
    "${path.module}/files/network_config.yaml.tpl", 
    {
      macvtap_interfaces = var.macvtap_interfaces
    }
  )
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_id = var.libvirt_network.network_id
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_id = null
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
  ips = length(var.macvtap_interfaces) == 0 ? [
    var.libvirt_network.ip
  ] : [
    for macvtap_interface in var.macvtap_interfaces: macvtap_interface.ip
  ]
  /*patroni = defaults(var.patroni, {
    ttl = 60
    loop_wait = 5
    retry_timeout = 10
    master_start_timeout = 300
    master_stop_timeout = 300
    watchdog_safety_margin = -1
    synchronous_node_count = 1
  })*/
  fluentd_conf = templatefile(
    "${path.module}/files/fluentd.conf.tpl", 
    {
      fluentd = var.fluentd
    }
  )
  patroni_conf = templatefile(
    "${path.module}/files/patroni.yml.tpl", 
    {
      patroni = var.patroni
      postgres = var.postgres
      etcd = var.etcd
    }
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        node_name = var.name
        ssh_admin_public_key = var.ssh_admin_public_key
        ssh_admin_user = var.ssh_admin_user
        admin_user_password = var.admin_user_password
        chrony = var.chrony
        fluentd = var.fluentd
        fluentd_conf = local.fluentd_conf
        patroni_conf = local.patroni_conf
        tls_pg_key = tls_private_key.pg_key.private_key_pem
        tls_pg_cert = "${tls_locally_signed_cert.pg_certificate.cert_pem}\n${var.postgres.ca.certificate}"
        tls_pg_ca_cert = var.postgres.ca.certificate
        tls_patroni_client_key = tls_private_key.patroni_client_key.private_key_pem
        tls_patroni_client_cert = tls_locally_signed_cert.patroni_client_certificate.cert_pem
        tls_etcd_ca_cert = var.etcd.ca_cert
      }
    )
  }
}

resource "libvirt_cloudinit_disk" "postgres" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? local.network_config : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "postgres" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
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