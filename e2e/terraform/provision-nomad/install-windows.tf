resource "null_resource" "install_nomad_binary_windows" {
  count    = var.platform == "windows" ? 1 : 0
  triggers = { nomad_binary_sha = filemd5(var.nomad_local_binary) }

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "windows"
    timeout         = "10m"
  }

  provisioner "file" {
    source      = var.nomad_local_binary
    destination = "C://tmp/nomad"
  }
  provisioner "remote-exec" {
    inline = [
      "powershell Move-Item -Force -Path C://tmp/nomad -Destination C:/opt/nomad.exe",
    ]
  }
}

resource "null_resource" "install_consul_configs_windows" {
  count = var.platform == "windows" ? 1 : 0

  depends_on = [
    null_resource.upload_consul_configs,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "windows"
    timeout         = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell Remove-Item -Force -Recurse -Path C://opt/consul.d",
      "powershell New-Item -Force -Path C:// -Name consul.d -ItemType directory",
      "powershell Move-Item -Force -Path C://tmp/consul_ca.pem -Destination C://opt/consul.d/ca.pem",
      "powershell Move-Item -Force -Path C://tmp/consul_ca.pem C://opt/consul.d/ca.pem",
      "powershell Move-Item -Force -Path C://tmp/consul_client_acl.json C://opt/consul.d/acl.json",
      "powershell Move-Item -Force -Path C://tmp/consul_client.json C://opt/consul.d/consul_client.json",
      "powershell Move-Item -Force -Path C://tmp/consul_client_base.json C://opt/consul.d/consul_client_base.json",
      "powershell Move-Item -Force -Path C://tmp/consul.service C://opt/systemd/system/consul.service",
    ]
  }
}

# TODO
resource "null_resource" "install_vault_configs_windows" {
  count = var.platform == "windows" ? 1 : 0

  depends_on = [
    null_resource.upload_vault_configs,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "windows"
    timeout         = "5m"
  }
}

resource "null_resource" "install_nomad_configs_windows" {
  count = var.platform == "windows" ? 1 : 0

  depends_on = [
    null_resource.upload_nomad_configs,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "windows"
    timeout         = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell Remove-Item -Force -Recurse -Path C://opt/nomad.d",
      "powershell New-Item -Force -Path C://opt/ -Name nomad.d -ItemType directory",
      "powershell New-Item -Force -Path C://opt/ -Name nomad -ItemType directory",
      "powershell New-Item -Force -Path C://opt/nomad -Name data -ItemType directory",
      "powershell Move-Item -Force -Path C://tmp/consul.hcl C://opt/nomad.d/consul.hcl",
      "powershell Move-Item -Force -Path C://tmp/vault.hcl C://opt/nomad.d/vault.hcl",
      "powershell Move-Item -Force -Path C://tmp/base.hcl C://opt/nomad.d/base.hcl",
      "powershell Move-Item -Force -Path C://tmp/${var.role}-${var.platform}.hcl C://opt/nomad.d/${var.role}-${var.platform}.hcl",
      "powershell Move-Item -Force -Path C://tmp/${var.role}-${var.platform}-${var.index}.hcl C://opt/nomad.d/${var.role}-${var.platform}-${var.index}.hcl",

      # TLS
      "powershell New-Item -Force -Path C://opt/nomad.d -Name tls -ItemType directory",
      "powershell Move-Item -Force -Path C://tmp/tls.hcl C://opt/nomad.d/tls.hcl",
      "powershell Move-Item -Force -Path C://tmp/agent-${var.instance.public_ip}.key C://opt/nomad.d/tls/agent.key",
      "powershell Move-Item -Force -Path C://tmp/agent-${var.instance.public_ip}.crt C://opt/nomad.d/tls/agent.crt",
      "powershell Move-Item -Force -Path C://tmp/ca.crt C://opt/nomad.d/tls/ca.crt",
    ]
  }
}

resource "null_resource" "restart_windows_services" {
  count = var.platform == "windows" ? 1 : 0

  depends_on = [
    null_resource.install_nomad_binary_windows,
    null_resource.install_consul_configs_windows,
    # null_resource.install_vault_configs_windows,
    null_resource.install_nomad_configs_windows,
  ]

  connection {
    type            = "ssh"
    user            = var.connection.user
    host            = var.instance.public_ip
    port            = var.connection.port
    private_key     = file(var.connection.private_key)
    target_platform = "windows"
    timeout         = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "powershell Restart-Service Consul",
      "powershell Restart-Service Nomad"
    ]
  }
}
