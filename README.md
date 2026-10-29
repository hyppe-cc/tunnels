# Tunnels

Share local projects on your own domain through [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), from the menu bar or the terminal.

- **Menu bar**: every tunnel's status, with a switch to start or stop it.
- **App**: create tunnels, rename them, watch their logs, clean everything up.
- **CLI**: `tunnel link` inside a project folder publishes it as `<folder>.<your domain>`.

Each tunnel runs as its own LaunchAgent, so it keeps running when the app is closed and comes back after a reboot.

## Install

```sh
brew install --cask hyppe-cc/tap/tunnels
```

This also installs `cloudflared` and the `tunnel` command. Then, once:

```sh
cloudflared tunnel login        # pick the domain you'll publish on
tunnel domain example.com
```

Requires macOS 26 (Tahoe) or later.

## Use

```sh
cd ~/code/myapp
tunnel link                     # https://myapp.example.com → https://myapp.test (or http)
tunnel link --name api          # https://api.example.com
tunnel link --domain other.dev  # https://myapp.other.dev
tunnel link --port 3000         # → http://127.0.0.1:3000
tunnel link --origin localhost:5173

tunnel                          # status (this folder's tunnel, or all of them)
tunnel stop | start | restart
tunnel rename --name docs       # moves the tunnel and its DNS record
tunnel logs -f
tunnel open
tunnel unlink --delete-tunnel   # removes it here and in Cloudflare
tunnel clean                    # removes every tunnel, DNS record, config and LaunchAgent
```

Run `tunnel help <command>` for details.

## How it works

`tunnel link` creates a named tunnel (`cloudflared tunnel create`), points the hostname at it
(`cloudflared tunnel route dns`), writes `~/.cloudflared/config-<host>.yml` and a LaunchAgent in
`~/Library/LaunchAgents`. Settings and which folder each tunnel belongs to live in
`~/.config/tunnel/settings.json`; logs in `~/Library/Logs/tunnel`.

cloudflared can create DNS records but not delete them, so `unlink --delete-tunnel` and `clean`
remove them through the Cloudflare API with the token `cloudflared tunnel login` saved in
`~/.cloudflared/cert.pem`. Only records that point at the tunnels being deleted are touched.

## Build

```sh
scripts/build.sh            # build/Tunnels.app and build/Tunnels.zip
scripts/build.sh --install  # also installs to ~/Applications and links ~/bin/tunnel
swift test
```

## Release

```sh
scripts/release.sh 1.0.0
```

Pushing the tag makes the GitHub Action sign and notarize the app, create the release and update
the cask in [hyppe-cc/homebrew-tap](https://github.com/hyppe-cc/homebrew-tap).

## License

[MIT](LICENSE)
