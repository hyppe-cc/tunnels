cask "tunnels" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/hyppe-cc/tunnels/releases/download/v#{version}/Tunnels.zip"
  name "Tunnels"
  desc "Share local projects on your own domain through Cloudflare tunnels"
  homepage "https://github.com/hyppe-cc/tunnels"

  depends_on macos: :tahoe
  depends_on formula: "cloudflared"

  app "Tunnels.app"
  binary "#{appdir}/Tunnels.app/Contents/MacOS/tunnel"

  uninstall quit: "cc.hyppe.tunnels"

  zap trash: [
    "~/.config/tunnel",
    "~/Library/Logs/tunnel",
  ]

  caveats <<~EOS
    Log in to Cloudflare once:  cloudflared tunnel login
    Set your domain:            tunnel domain example.com
    Running tunnels keep going after uninstalling; run `tunnel clean` first to remove them.
  EOS
end
