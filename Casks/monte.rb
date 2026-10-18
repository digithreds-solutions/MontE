cask "monte" do
  version "2.7.0"
  sha256 "f3c43fca4180e2307a27f1d48d5cf522df584a653d2bc5e6573caf6260bec54c"

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
