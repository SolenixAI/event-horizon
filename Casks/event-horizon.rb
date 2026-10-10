cask "event-horizon" do
  version "2026.10.8"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/SolenixAI/event-horizon/releases/download/#{version}/Event-Horizon-#{version}.dmg"
  name "Event Horizon"
  desc "Stream games from a PC running Sunshine"
  homepage "https://solenix.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Event Horizon.app"
  binary "#{appdir}/Event Horizon.app/Contents/MacOS/Event Horizon", target: "event-horizon"

  # The helpers are SMAppService items macOS owns. Removing their launchd jobs on
  # every upgrade left the login item broken, so only zap removes them.
  uninstall quit: "dev.solenix.eventhorizon"

  # Legacy io.ugfugl.Glimmer data is removed too: PR #29 moves it once on first
  # launch, but a copy that was never opened under this name is still on the Mac.
  zap launchctl: [
        "dev.solenix.eventhorizon.helper",
        "dev.solenix.eventhorizon.LoginHelper",
        "io.ugfugl.glimmer.helper",
        "io.ugfugl.Glimmer.LoginHelper",
      ],
      trash:     [
        "~/Library/Application Support/Event Horizon",
        "~/Library/Application Support/Glimmer",
        "~/Library/Caches/dev.solenix.eventhorizon",
        "~/Library/Caches/io.ugfugl.Glimmer",
        "~/Library/Containers/io.ugfugl.Glimmer",
        "~/Library/HTTPStorages/dev.solenix.eventhorizon",
        "~/Library/HTTPStorages/io.ugfugl.Glimmer",
        "~/Library/Logs/Event Horizon",
        "~/Library/Logs/Glimmer",
        "~/Library/Preferences/dev.solenix.eventhorizon.plist",
        "~/Library/Preferences/io.ugfugl.Glimmer.plist",
      ]
end
