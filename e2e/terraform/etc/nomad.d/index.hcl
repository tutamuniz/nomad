


# Enable the client
client {
  enabled = true

  meta {
    "rack" = "r1"
  }
  host_volume "shared_data" {
    path = "/srv/data"
  }

}
