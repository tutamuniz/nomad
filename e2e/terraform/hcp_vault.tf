# Note: the test environment must have the following values set:
# export HCP_CLIENT_ID=
# export HCP_CLIENT_SECRET=
# export VAULT_TOKEN=
# export VAULT_ADDR=

data "hcp_vault_cluster" "e2e_shared_vault" {
  cluster_id = var.hcp_vault_cluster_id
}

# Nomad servers configuration for Vault

resource "vault_policy" "nomad" {
  name   = "nomad"
  policy = data.local_file.vault_policy_for_nomad.content
}

data "local_file" "vault_policy_for_nomad" {
  filename = "${path.root}/etc/acls/vault/nomad-policy.hcl"
}

resource "vault_token_auth_backend_role" "nomad_cluster" {
  role_name        = "nomad-cluster"
  allowed_policies = [vault_policy.nomad.name]
  orphan           = true
  token_period     = "259200"
  renewable        = true
  token_max_ttl    = "0"
}

resource "vault_token" "nomad" {
  role_name = vault_token_auth_backend_role.nomad_cluster.role_name
  policies  = [vault_policy.nomad.name]
  no_parent = true
  renewable = true
  ttl       = "72h"
}

resource "local_file" "nomad_config_for_vault" {
  sensitive_content = templatefile("etc/nomad.d/vault.hcl", {
    token = vault_token.nomad.client_token
    url   = data.hcp_vault_cluster.e2e_shared_vault.vault_private_endpoint_url
  })
  filename        = "uploads/shared/nomad.d/vault.hcl"
  file_permission = "0700"
}
