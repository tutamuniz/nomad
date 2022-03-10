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

  # TODO: fix uploads to windows. These are failing with weird errors:
  # 2022-03-10T14:34:02.499-0500 [ERROR] scp stderr: "At line:1 char:7\r\n+ \"scp\" -vt C:/tmp\r\n+       ~~~\r\nUnexpected token '-vt' in expression or statement.\r\nAt line:1 char:11\r\n+ \"scp\" -vt C:/tmp\r\n+           ~~~~~~\r\nUnexpected token '/tmp' in expression or statement.\r\n    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx \r\n   ception\r\n    + FullyQualifiedErrorId : UnexpectedToken\r\n \r\n"

  provisioner "file" {
    source      = var.nomad_local_binary
    destination = "/tmp/nomad"
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
