locals {
  upload_dir = "uploads/${var.instance.public_ip}"
}

resource "local_file" "nomad_base_config" {
  sensitive_content = templatefile("etc/nomad.d/base.hcl", {})
  filename          = "${local.upload_dir}/nomad.d/base.hcl"
  file_permission   = "0700"
}

resource "local_file" "nomad_role_config" {
  sensitive_content = templatefile("etc/nomad.d/${var.role}-${var.platform}.hcl", {})
  filename          = "${local.upload_dir}/nomad.d/${var.role}.hcl"
  file_permission   = "0700"
}

# TODO: make this select from index file, if available
resource "local_file" "nomad_indexed_config" {
  sensitive_content = templatefile("etc/nomad.d/index.hcl", {})
  filename          = "${local.upload_dir}/nomad.d/${var.role}-${var.platform}-${var.index}.hcl"
  file_permission   = "0700"
}

resource "local_file" "nomad_tls_config" {
  sensitive_content = templatefile("etc/nomad.d/tls.hcl", {})
  filename          = "${local.upload_dir}/nomad.d/tls.hcl"
  file_permission   = "0700"
}

resource "null_resource" "upload_consul_configs" {

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = var.arch == "windows_amd64" ? "windows" : "unix"
    timeout         = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/consul.d",
    ]
  }
  provisioner "file" {
    source      = "uploads/consul.d/ca.pem"
    destination = "/tmp/consul_ca.pem"
  }
  provisioner "file" {
    source      = "uploads/consul.d/consul_client.json"
    destination = "/tmp/consul_client.json"
  }
  provisioner "file" {
    source      = "uploads/consul.d/client_acl.json"
    destination = "/tmp/consul_client_acl.json"
  }
  provisioner "file" {
    source      = "uploads/consul.d/consul_client_base.json"
    destination = "/tmp/consul_client_base.json"
  }
  provisioner "file" {
    source      = "uploads/consul.d/consul.service"
    destination = "/tmp/consul.service"
  }
}

# TODO
resource "null_resource" "upload_vault_configs" {

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = var.arch == "windows_amd64" ? "windows" : "unix"
    timeout         = "15m"
  }
}

resource "null_resource" "upload_nomad_configs" {

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = var.arch == "windows_amd64" ? "windows" : "unix"
    timeout         = "15m"
  }

  # created in hcp_consul.tf
  provisioner "file" {
    source      = "uploads/shared/nomad.d/${var.role}-consul.hcl"
    destination = "/tmp/${var.role}-consul.hcl"
  }
  # created in hcp_vault.tf
  provisioner "file" {
    source      = "uploads/shared/nomad.d/${var.role}-vault.hcl"
    destination = "/tmp/${var.role}-vault.hcl"
  }

  provisioner "file" {
    source      = local_file.nomad_base_config.filename
    destination = "/tmp/base.hcl"
  }
  provisioner "file" {
    source      = local_file.nomad_role_config.filename
    destination = "/tmp/${var.role}-${var.platform}.hcl"
  }
  provisioner "file" {
    source      = local_file.nomad_indexed_config.filename
    destination = "/tmp/${var.role}-${var.platform}-${var.index}.hcl"
  }
  provisioner "file" {
    source      = local_file.nomad_tls_config.filename
    destination = "/tmp/tls.hcl"
  }
  provisioner "file" {
    source      = local_file.nomad_systemd_unit_file.filename
    destination = "/tmp/nomad.service"
  }
  provisioner "file" {
    source      = local_file.nomad_client_key.filename
    destination = "/tmp/agent-${var.instance.public_ip}.key"
  }
  provisioner "file" {
    source      = local_file.nomad_client_cert.filename
    destination = "/tmp/agent-${var.instance.public_ip}.crt"
  }
  provisioner "file" {
    source      = var.tls_ca_cert
    destination = "/tmp/ca.crt"
  }
}
