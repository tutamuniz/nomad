locals {
  provision_script = var.arch == "windows_amd64" ? "powershell C:/opt/provision.ps1" : "/opt/provision.sh"

  config_path = dirname("${path.root}/config/")

  config_files = compact(setunion(
    fileset(local.config_path, "**"),
  ))

  update_config_command = var.arch == "windows_amd64" ? "powershell -Command \"& { if (test-path /opt/config) { Remove-Item -Path /opt/config -Force -Recurse }; cp -r C:/tmp/config /opt/config }\"" : "sudo rm -rf /opt/config; sudo mv /tmp/config /opt/config"

  # abstract-away platform-specific parameter expectations
  _arg = var.arch == "windows_amd64" ? "-" : "--"

  tls_role = var.role
}

resource "null_resource" "provision_nomad" {

  depends_on = [
    null_resource.upload_configs,
    null_resource.upload_nomad_binary,
    null_resource.generate_instance_tls_certs
  ]

  # no need to re-run if nothing changes
  triggers = {
    script = data.template_file.provision_script.rendered
  }


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
    inline = [data.template_file.provision_script.rendered]
  }

}

data "template_file" "provision_script" {
  template = "${local.provision_script}${data.template_file.arg_nomad_url.rendered}${data.template_file.arg_nomad_sha.rendered}${data.template_file.arg_nomad_version.rendered}${data.template_file.arg_nomad_binary.rendered}${data.template_file.arg_nomad_enterprise.rendered}${data.template_file.arg_nomad_license.rendered}${data.template_file.arg_nomad_acls.rendered}${data.template_file.arg_nomad_tls.rendered}${data.template_file.arg_profile.rendered}${data.template_file.arg_role.rendered}${data.template_file.arg_index.rendered}${data.template_file.autojoin_tag.rendered}"
}

data "template_file" "arg_nomad_sha" {
  template = var.nomad_sha != "" && var.nomad_local_binary == "" && var.nomad_url == "" ? " ${local._arg}nomad_sha ${var.nomad_sha}" : ""
}

data "template_file" "arg_nomad_version" {
  template = var.nomad_version != "" && var.nomad_sha == "" && var.nomad_url == "" && var.nomad_local_binary == "" ? " ${local._arg}nomad_version ${var.nomad_version}" : ""
}

data "template_file" "arg_nomad_url" {
  template = var.nomad_url != "" && var.nomad_local_binary == "" ? " ${local._arg}nomad_url '${var.nomad_url}'" : ""
}

data "template_file" "arg_nomad_binary" {
  template = var.nomad_local_binary != "" ? " ${local._arg}nomad_binary /tmp/nomad" : ""
}

data "template_file" "arg_nomad_enterprise" {
  template = var.nomad_enterprise ? " ${local._arg}enterprise" : ""
}

data "template_file" "arg_nomad_license" {
  template = var.nomad_license != "" ? " ${local._arg}nomad_license ${var.nomad_license}" : ""
}

data "template_file" "arg_nomad_acls" {
  template = var.nomad_acls ? " ${local._arg}nomad_acls" : ""
}

data "template_file" "arg_nomad_tls" {
  template = var.tls ? " ${local._arg}tls" : ""
}

data "template_file" "arg_profile" {
  template = var.profile != "" ? " ${local._arg}config_profile ${var.profile}" : ""
}

data "template_file" "arg_role" {
  template = var.role != "" ? " ${local._arg}role ${var.role}_${var.platform}" : ""
}

data "template_file" "arg_index" {
  template = var.index != "" ? " ${local._arg}index ${var.index}" : ""
}

data "template_file" "autojoin_tag" {
  template = var.cluster_name != "" ? " ${local._arg}autojoin auto-join-${var.cluster_name}" : ""
}

resource "null_resource" "upload_nomad_binary" {

  count      = var.nomad_local_binary != "" ? 1 : 0
  depends_on = [null_resource.upload_configs]
  triggers = {
    nomad_binary_sha = filemd5(var.nomad_local_binary)
  }

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = var.arch == "windows_amd64" ? "windows" : "unix"
    timeout         = "15m"
  }

  provisioner "file" {
    source      = var.nomad_local_binary
    destination = "/tmp/nomad"
  }
}

resource "null_resource" "upload_configs" {

  triggers = {
    hashes = join(",", [for file in local.config_files : filemd5("${local.config_path}/${file}")])
  }

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = var.arch == "windows_amd64" ? "windows" : "unix"
    timeout         = "15m"
  }

  provisioner "file" {
    source      = local.config_path
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [local.update_config_command]
  }

}

// TODO: Create separate certs.
// This creates one set of certs to manage Nomad, Consul, and Vault and therefore
// puts all the required SAN entries to enable sharing certs. This is an anti-pattern
// that we should clean up.
resource "null_resource" "generate_instance_tls_certs" {
  count      = var.tls ? 1 : 0
  depends_on = [null_resource.upload_configs]

  connection {
    type        = "ssh"
    user        = var.connection.user
    host        = var.instance.public_ip
    port        = var.connection.port
    private_key = file(var.connection.private_key)
    timeout     = "15m"
  }

  provisioner "local-exec" {
    command = <<EOF
set -e

cat <<'EOT' > keys/ca.crt
${var.tls_ca_cert}
EOT

cat <<'EOT' > keys/ca.key
${var.tls_ca_key}
EOT

openssl req -newkey rsa:2048 -nodes \
	-subj "/CN=${local.tls_role}.global.nomad" \
	-keyout keys/agent-${var.instance.public_ip}.key \
	-out keys/agent-${var.instance.public_ip}.csr

cat <<'NEOY' > keys/agent-${var.instance.public_ip}.conf

subjectAltName=DNS:${local.tls_role}.global.nomad,DNS:${local.tls_role}.dc1.consul,DNS:localhost,DNS:${var.instance.public_dns},DNS:vault.service.consul,DNS:active.vault.service.consul,IP:127.0.0.1,IP:${var.instance.private_ip},IP:${var.instance.public_ip}
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
NEOY

openssl x509 -req -CAcreateserial \
	-extfile ./keys/agent-${var.instance.public_ip}.conf \
	-days 365 \
  -sha256 \
	-CA keys/ca.crt \
	-CAkey keys/ca.key \
	-in keys/agent-${var.instance.public_ip}.csr \
	-out keys/agent-${var.instance.public_ip}.crt

EOF
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/nomad-tls",
    ]
  }
  provisioner "file" {
    source      = "keys/ca.crt"
    destination = "/tmp/nomad-tls/ca.crt"
  }
  provisioner "file" {
    source      = "keys/agent-${var.instance.public_ip}.crt"
    destination = "/tmp/nomad-tls/agent.crt"
  }
  provisioner "file" {
    source      = "keys/agent-${var.instance.public_ip}.key"
    destination = "/tmp/nomad-tls/agent.key"
  }
  # workaround to avoid updating packer
  provisioner "file" {
    source      = "packer/ubuntu-bionic-amd64/provision.sh"
    destination = "/opt/provision.sh"
  }
  provisioner "file" {
    source      = "config"
    destination = "/tmp/config"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/nomad/tls",
      "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/consul/tls",
      "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/vault/tls",

      # more workaround
      "sudo rm -rf /opt/config",
      "sudo mv /tmp/config /opt/config"
    ]
  }

}




resource "null_resource" "install_hcp_consul_config" {
  depends_on = [null_resource.upload_configs]

  connection {
    type        = "ssh"
    user        = var.connection.user
    host        = var.instance.public_ip
    port        = var.connection.port
    private_key = file(var.connection.private_key)
    timeout     = "15m"
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
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /etc/consul.d/*",
      "sudo mv /tmp/consul_ca.pem /etc/consul.d/ca.pem",
      "sudo mv /tmp/consul_client_acl.json /etc/consul.d/acl.json",
      "sudo mv /tmp/consul_client.json /etc/consul.d/consul_client.json",
      "sudo mv /tmp/consul_client_base.json /etc/consul.d/consul_client_base.json",
      "sudo mv /tmp/consul.service /etc/systemd/system/consul.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable consul",
      "sudo systemctl restart consul",
    ]
  }

}


# TODO: temporary


resource "local_file" "nomad_base_config" {
  sensitive_content = templatefile("etc/nomad.d/base.hcl", {})
  filename        = "uploads/nomad.d/base.hcl"
  file_permission = "0700"
}

resource "local_file" "nomad_role_config" {
  sensitive_content = templatefile("etc/nomad.d/${var.role}-${var.platform}.hcl", {})
  filename        = "uploads/nomad.d/${var.role}.hcl"
  file_permission = "0700"
}

# TODO: make this select from index file, if available
resource "local_file" "nomad_indexed_config" {
  sensitive_content = templatefile("etc/nomad.d/index.hcl", {})
  filename        = "uploads/nomad.d/${var.role}-${var.platform}-${var.index}.hcl"
  file_permission = "0700"
}

resource "local_file" "nomad_tls_config" {
  sensitive_content = templatefile("etc/nomad.d/tls.hcl", {})
  filename        = "uploads/nomad.d/tls.hcl"
  file_permission = "0700"
}

resource "local_file" "nomad_systemd_unit_file" {
  sensitive_content = templatefile("etc/nomad.d/nomad-${var.role}.service", {})
  filename        = "uploads/nomad.d/nomad-${var.role}.service"
  file_permission = "0700"
}

resource "null_resource" "install_nomad_config" {
  depends_on = [null_resource.upload_configs]

  connection {
    type        = "ssh"
    user        = var.connection.user
    host        = var.instance.public_ip
    port        = var.connection.port
    private_key = file(var.connection.private_key)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/nomad.d",
      "mkdir -p /var/nomad",
    ]
  }

  # created in hcp_consul.tf
  provisioner "file" {
    source      = "uploads/nomad.d/${var.role}-consul.hcl"
    destination = "/tmp/${var.role}-consul.hcl"
  }
  # created in hcp_vault.tf
  provisioner "file" {
    source      = "uploads/nomad.d/${var.role}-vault.hcl"
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

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /etc/nomad.d/*",
      "sudo mv /tmp/${var.role}-consul.hcl /etc/nomad.d/${var.role}-consul.hcl",
      "sudo mv /tmp/${var.role}-vault.hcl /etc/nomad.d/${var.role}-vault.hcl",
      "sudo mv /tmp/base.hcl /etc/nomad.d/base.hcl",
      "sudo mv /tmp/${var.role}-${var.platform}.hcl /etc/nomad.d/${var.role}-${var.platform}.hcl",
      "sudo mv /tmp/${var.role}-${var.platform}-${var.index}.hcl /etc/nomad.d/${var.role}-${var.platform}-${var.index}.hcl",
      "sudo mv /tmp/tls.hcl /etc/nomad.d/tls.hcl",
      "sudo mv /tmp/nomad.service /etc/systemd/system/nomad.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nomad",
      "sudo systemctl restart nomad",
    ]
  }

}
