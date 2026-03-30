## Media server


### Renewing tailscale

 - Head over to https://eu.infisical.com/login
 - Generate a new auth-key here https://login.tailscale.com/admin/settings/keys
 - Paste it to `tailscale/AUTH_KEY`
 - Force resync of `es` tailscale via annotation
 - Restart tailscale
