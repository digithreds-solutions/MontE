cask "monte" do
  version "2.9.0"
  sha256 "ee5bce9b1a277121524e381b29bb260644a9782b95fe6f6f1c70fc11327e5883"

  url "https://github.com/digithreds-solutions/MontE/releases/download/v#{version}/Monte-#{version}.dmg"
  name "Mont-E"
  desc "Native macOS hardware telemetry, battery preservation, and system performance cockpit"
  homepage "https://github.com/digithreds-solutions/MontE"

  depends_on macos: ">= :ventura"

  app "Monte.app"

  uninstall quit: "com.digithreads.monte"

  zap trash: [
    "~/Library/Application Support/com.digithreads.monte",
    "~/Library/Caches/com.digithreads.monte",
    "~/Library/Preferences/com.digithreads.monte.plist",
    "~/Library/LaunchAgents/com.digithreads.monte.plist",
  ]
end
