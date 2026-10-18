# Bedrock Voice Chat server config.
# Reference: https://www.bedrockvoicechat.com/wiki/reference/configuration/
#
# The certificate source is NOT set here. It comes from .env, so you can switch
# options without editing this file (environment overrides config, empty = unset):
#   Option A, free DuckDNS subdomain:  BVC_TLS_CERTIFICATE + BVC_TLS_KEY (files made by cert.sh)
#   Option B, own domain on Cloudflare: BVC_ACME_PROVIDER + BVC_ACME_EMAIL + BVC_ACME_API_TOKEN
# Use exactly one; the server refuses to start with both.
#
# The server reads this file only at startup: `docker compose restart` after editing.

server {
    port      = 443
    quic_port = 28280
    # If you change quic_port, also set the ports clients are told to use (default [28280]):
    # advertised_quic_ports = [28280]

    # No peering with other BVC servers, so UDP 28284 stays closed.
    peering = false

    tls {
        # The hostname players type into the app. Must match the certificate.
        names = ["${env.BVC_DOMAIN}"]
    }

    # Optional: extra server list shown in the BVC app (Bedrock Voice Chat Connect).
    # Not needed for Realms (players pick the Realm in the app). Use addon_mode = "no_net"
    # for Aternos-style hosts, "net" for your own BDS / Java server.
    # bedrock {
    #     servers = [
    #         {
    #             name       = "My SMP"
    #             host       = "play.example.com"
    #             port       = 19132
    #             addon_mode = "net"
    #         }
    #     ]
    # }
}

voice {
    spatial_audio {
        # How far (in blocks) voices carry.
        broadcast_range = 48.0
    }
}

log {
    level = "info"
    path  = "./logs"
}
