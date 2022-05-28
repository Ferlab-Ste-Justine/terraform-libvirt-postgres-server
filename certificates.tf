resource "tls_private_key" "pg_key" {
  algorithm   = "RSA"
  rsa_bits = var.postgres.certificate.key_length
}

resource "tls_cert_request" "pg_request" {
  private_key_pem = tls_private_key.pg_key.private_key_pem

  subject {
    common_name  = "postgres"
    organization = var.postgres.certificate.organization
  }

  dns_names = distinct(concat(var.postgres.certificate.domains, ["localhost"]))
  ip_addresses = distinct(concat(local.ips, ["127.0.0.1"]))
}

resource "tls_locally_signed_cert" "pg_certificate" {
  cert_request_pem   = tls_cert_request.pg_request.cert_request_pem
  ca_private_key_pem = var.postgres.ca.key
  ca_cert_pem        = var.postgres.ca.certificate

  validity_period_hours = var.postgres.certificate.validity_period
  early_renewal_hours = var.postgres.certificate.early_renewal_period

  allowed_uses = [
    "server_auth",
  ]

  is_ca_certificate = false
}

resource "tls_private_key" "patroni_client_key" {
  algorithm   = "RSA"
  rsa_bits = var.postgres.certificate.key_length
}

resource "tls_cert_request" "patroni_client_request" {
  private_key_pem = tls_private_key.patroni_client_key.private_key_pem

  subject {
    common_name  = "patroni-client"
    organization = var.postgres.certificate.organization
  }
}

resource "tls_locally_signed_cert" "patroni_client_certificate" {
  cert_request_pem   = tls_cert_request.patroni_client_request.cert_request_pem
  ca_private_key_pem = var.postgres.ca.key
  ca_cert_pem        = var.postgres.ca.certificate

  validity_period_hours = var.postgres.certificate.validity_period
  early_renewal_hours = var.postgres.certificate.early_renewal_period

  allowed_uses = [
    "client_auth",
  ]

  is_ca_certificate = false
}