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

# TODO: need one for Windows too
resource "null_resource" "install_nomad_binary_linux" {
  count = var.platform == "linux" ? 1 : 0

  triggers = {
    nomad_binary_sha = filemd5(var.nomad_local_binary)
  }

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "unix"
    timeout         = "15m"
  }

  provisioner "file" {
    source      = var.nomad_local_binary
    destination = "/tmp/nomad"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/nomad /usr/local/bin/nomad",
    ]
  }

}

resource "tls_private_key" "nomad" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "nomad" {
  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.api_client.private_key_pem
  ip_addresses    = ["${var.instance.public_ip}", "${var.instance.private_ip}", "127.0.0.1"]
  dns_names       = ["${var.role}.global.nomad"]

  subject {
    common_name = "${var.role}.global.nomad"
  }
}

resource "tls_locally_signed_cert" "nomad" {
  cert_request_pem   = tls_cert_request.api_client.cert_request_pem
  ca_key_algorithm   = tls_private_key.ca.algorithm
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 720

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
    "server_auth",
  ]
}

resource "local_file" "nomad_client_key" {
  sensitive_content = tls_private_key.api_client.private_key_pem
  filename          = "keys/agent-${var.instance.public_ip}.key"
}

resource "local_file" "nomad_client_cert" {
  sensitive_content = tls_locally_signed_cert.api_client.cert_pem
  filename          = "keys/agent-${var.instance.public_ip}.crt"
}


# // TODO: Create separate certs.
# // This creates one set of certs to manage Nomad, Consul, and Vault and therefore
# // puts all the required SAN entries to enable sharing certs. This is an anti-pattern
# // that we should clean up.
# resource "null_resource" "generate_instance_tls_certs" {
#   count = var.tls ? 1 : 0
#   #depends_on = [null_resource.upload_configs]

#   connection {
#     type        = "ssh"
#     user        = var.connection.user
#     host        = var.instance.public_ip
#     port        = var.connection.port
#     private_key = file(var.connection.private_key)
#     timeout     = "15m"
#   }

#   provisioner "local-exec" {
#     command = <<EOF
# set -e

# cat <<'EOT' > keys/ca.crt
# ${var.tls_ca_cert}
# EOT

# cat <<'EOT' > keys/ca.key
# ${var.tls_ca_key}
# EOT

# openssl req -newkey rsa:2048 -nodes \
# 	-subj "/CN=${local.role}.global.nomad" \
# 	-keyout keys/agent-${var.instance.public_ip}.key \
# 	-out keys/agent-${var.instance.public_ip}.csr

# cat <<'NEOY' > keys/agent-${var.instance.public_ip}.conf

# subjectAltName=DNS:${local.role}.global.nomad,DNS:${local.role}.dc1.consul,DNS:localhost,DNS:${var.instance.public_dns},DNS:vault.service.consul,DNS:active.vault.service.consul,IP:127.0.0.1,IP:${var.instance.private_ip},IP:${var.instance.public_ip}
# extendedKeyUsage = serverAuth, clientAuth
# basicConstraints = CA:FALSE
# keyUsage = digitalSignature, keyEncipherment
# NEOY

# openssl x509 -req -CAcreateserial \
# 	-extfile ./keys/agent-${var.instance.public_ip}.conf \
# 	-days 365 \
#   -sha256 \
# 	-CA keys/ca.crt \
# 	-CAkey keys/ca.key \
# 	-in keys/agent-${var.instance.public_ip}.csr \
# 	-out keys/agent-${var.instance.public_ip}.crt

# EOF
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "mkdir -p /tmp/nomad-tls",
#     ]
#   }
#   provisioner "file" {
#     source      = "keys/ca.crt"
#     destination = "/tmp/nomad-tls/ca.crt"
#   }
#   provisioner "file" {
#     source      = "keys/agent-${var.instance.public_ip}.crt"
#     destination = "/tmp/nomad-tls/agent.crt"
#   }
#   provisioner "file" {
#     source      = "keys/agent-${var.instance.public_ip}.key"
#     destination = "/tmp/nomad-tls/agent.key"
#   }
#   # workaround to avoid updating packer
#   provisioner "file" {
#     source      = "packer/ubuntu-bionic-amd64/provision.sh"
#     destination = "/opt/provision.sh"
#   }
#   provisioner "file" {
#     source      = "config"
#     destination = "/tmp/config"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/nomad/tls",
#       "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/consul/tls",
#       "sudo cp -r /tmp/nomad-tls /opt/config/${var.profile}/vault/tls",

#       # more workaround
#       "sudo rm -rf /opt/config",
#       "sudo mv /tmp/config /opt/config"
#     ]
#   }

# }




resource "null_resource" "install_hcp_consul_config" {

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
    ]
  }

}


# TODO: temporary


resource "local_file" "nomad_base_config" {
  sensitive_content = templatefile("etc/nomad.d/base.hcl", {})
  filename          = "uploads/nomad.d/base.hcl"
  file_permission   = "0700"
}

resource "local_file" "nomad_role_config" {
  sensitive_content = templatefile("etc/nomad.d/${var.role}-${var.platform}.hcl", {})
  filename          = "uploads/nomad.d/${var.role}.hcl"
  file_permission   = "0700"
}

# TODO: make this select from index file, if available
resource "local_file" "nomad_indexed_config" {
  sensitive_content = templatefile("etc/nomad.d/index.hcl", {})
  filename          = "uploads/nomad.d/${var.role}-${var.platform}-${var.index}.hcl"
  file_permission   = "0700"
}

resource "local_file" "nomad_tls_config" {
  sensitive_content = templatefile("etc/nomad.d/tls.hcl", {})
  filename          = "uploads/nomad.d/tls.hcl"
  file_permission   = "0700"
}

resource "local_file" "nomad_systemd_unit_file" {
  sensitive_content = templatefile("etc/nomad.d/nomad-${var.role}.service", {})
  filename          = "uploads/nomad.d/nomad-${var.role}.service"
  file_permission   = "0700"
}

resource "null_resource" "upload_nomad_configs" {
  # TODO: maybe don't need this manual depends_on if we use the right resources
  # depends_on = [
  #   #null_resource.generate_instance_tls_certs,
  # ]

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
      "mkdir -p /etc/nomad.d",
      "mkdir -p /opt/nomad/data",
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
  provisioner "file" {
    source = local_file.nomad_client_key.filename
    destination = "/tmp/agent-${var.instance.public_ip}.key"
  }
  provisioner "file" {
    source = local_file.nomad_client_cert.filename
    destination = "/tmp/agent-${var.instance.public_ip}.crt"
  }
  provisioner "file" {
    source = "keys/ca.crt" # TODO: get from rsource
    destination = "/tmp/ca.crt"
  }
}

# TODO: need this for Windows too
resource "null_resource" "install_nomad_configs_linux" {
  count = var.platform == "linux" ? 1 : 0

  depends_on = [
    null_resource.upload_nomad_configs,
    #null_resource.generate_instance_tls_certs,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "unix"
    timeout         = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /etc/nomad.d/*",
      "sudo mv /tmp/${var.role}-consul.hcl /etc/nomad.d/${var.role}-consul.hcl",
      "sudo mv /tmp/${var.role}-vault.hcl /etc/nomad.d/${var.role}-vault.hcl",
      "sudo mv /tmp/base.hcl /etc/nomad.d/base.hcl",
      "sudo mv /tmp/${var.role}-${var.platform}.hcl /etc/nomad.d/${var.role}-${var.platform}.hcl",
      "sudo mv /tmp/${var.role}-${var.platform}-${var.index}.hcl /etc/nomad.d/${var.role}-${var.platform}-${var.index}.hcl",

      # TLS
      "sudo mkdir /etc/nomad.d/tls",
      "sudo mv /tmp/tls.hcl /etc/nomad.d/tls.hcl",
      "sudo mv /tmp/agent-${var.instance.public_ip}.key /etc/nomad.d/tls/agent.key"
      "sudo mv /tmp/agent-${var.instance.public_ip}.crt /etc/nomad.d/tls/agent.crt"
      "sudo mv /tmp/ca.crt /etc/nomad.d/tls/ca.crt"

      "sudo mv /tmp/nomad.service /etc/systemd/system/nomad.service",
    ]
  }

}

# TODO: need this for Windows too
resource "null_resource" "restart_linux_services" {
  count = var.platform == "linux" ? 1 : 0

  depends_on = [
    null_resource.install_nomad_binary_linux,
    null_resource.install_hcp_consul_config,
    # null_resource.install_hcp_vault_config,
    null_resource.install_nomad_configs_linux,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "unix"
    timeout         = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable consul",
      "sudo systemctl restart consul",
      "sudo systemctl enable nomad",
      "sudo systemctl restart nomad",
    ]
  }

}
