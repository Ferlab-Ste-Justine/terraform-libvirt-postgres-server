resource "random_string" "postgres_password" {
  count = var.postgres_password != "" ? 0 : 1
  length = 20
  special = false
}

locals {
  postgres_password = var.postgres_password != "" ? var.postgres_password : random_string.postgres_password.0.result
  postgres_params = "-c ssl=on -c ssl_cert_file=/opt/pg.pem -c ssl_key_file=/opt/pg.key ${var.postgres_params}"
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_config = templatefile(
    "${path.module}/files/network_config.yaml.tpl", 
    {
      interface_name_match = var.macvtap_vm_interface_name_match
      subnet_prefix_length = var.macvtap_subnet_prefix_length
      vm_ip = var.ip
      gateway_ip = var.macvtap_gateway_ip
      dns_servers = var.macvtap_dns_servers
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
        postgres_orchestration  = templatefile(
            "${path.module}/files/docker-compose.yml.tpl",
            {
                image = var.postgres_image
                params = local.postgres_params
                user = var.postgres_user
                password = local.postgres_password
                database = var.postgres_database
            }
        )
        tls_key = tls_private_key.key.private_key_pem
        tls_certificate = "${tls_locally_signed_cert.certificate.cert_pem}\n${var.ca.certificate}"
        postgres_image = var.postgres_image
      }
    )
  }
}

resource "libvirt_cloudinit_disk" "postgres" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = var.macvtap_interface != "" ? local.network_config : null
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

  network_interface {
    network_id = var.network_id != "" ? var.network_id : null
    macvtap = var.macvtap_interface != "" ? var.macvtap_interface : null
    addresses = var.network_id != "" ? [var.ip] : null
    mac = var.mac != "" ? var.mac : null
    hostname = var.network_id != "" ? var.name : null
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