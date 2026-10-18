# Bedrock Voice Chat server config.
# Reference: https://www.bedrockvoicechat.com/wiki/reference/configuration/
# Values come from .env via ${env.VAR}. If a referenced variable is unset, the server will not start.
# The server reads this file only at startup: `docker compose restart` after editing.

server {
    port      = 443
    quic_port = 28280

    # No peering with other BVC servers, so UDP 28284 can stay closed.
    peering = false

    tls {
        names = ["${env.BVC_DOMAIN}"]

        # Option 1 (default): Let's Encrypt via Cloudflare DNS-01. No port 80 needed.
        acme {
            email     = "${env.BVC_ACME_EMAIL}"
            provider  = "cloudflare"
            api_token = "${env.CF_API_TOKEN}"
            # Uncomment while testing to avoid Let's Encrypt rate limits:
            # directory = "https://acme-staging-v02.api.letsencrypt.org/directory"
        }

        # Option 2: acme-dns (DNS not on Cloudflare). Remove the acme block above and use:
        # acme {
        #     email      = "${env.BVC_ACME_EMAIL}"
        #     provider   = "acme-dns"
        #     server_url = "https://auth.acme-dns.io"
        #     username   = "${env.ACME_DNS_USERNAME}"
        #     password   = "${env.ACME_DNS_PASSWORD}"
        #     subdomain  = "${env.ACME_DNS_SUBDOMAIN}"
        # }

        # Option 3: your own certificate (full chain!). Remove the acme block, put the
        # files in ./data/tls/ and use:
        # certificate = "/data/tls/fullchain.pem"
        # key         = "/data/tls/privkey.pem"
    }

    # Required by the server. A Realm (no-net addon) never uses it; it only matters
    # if you later move to your own BDS / Java server with the HTTP addon or mod.
    minecraft {
        access_token = "${env.BVC_ACCESS_TOKEN}"
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
        broadcast_range = 48.0
    }
}

log {
    level = "info"
    path  = "./logs"
}
