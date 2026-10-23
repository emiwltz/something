# The Homebrew formula of something as it goes into the tap emiwltz/homebrew-tap, at Formula/something.rb. Its twin,
# packaging/homebrew/something.rb in https://github.com/emiwltz/something, is the one that repository's CI installs;
# both are the same but for comments and the url and sha256 lines (PackagingTests checks it). A release is in that
# repository's AGENTS.md, "Releasing"; the bottle block is written in the tap by `brew pr-pull` (publish.yml).
class Something < Formula
  desc "Sees every coding agent on your Mac and gives your HTML pages a bridge to them"
  homepage "https://github.com/emiwltz/something"
  url "https://github.com/emiwltz/something/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "88ba2489ded5c448b54730cde4c0ed6effb1006064d158fc0a407ead2c224f43"
  license "MIT"
  head "https://github.com/emiwltz/something.git", branch: "main"

  # No bottle block by hand: publish.yml (brew pr-pull) adds it, with root_url
  # https://github.com/emiwltz/homebrew-tap/releases/download/something-0.2.0 and one sha256 per bottle tag
  # (arm64_tahoe, arm64_sequoia, sequoia). Without a fitting bottle (another prefix, --HEAD, --build-from-source),
  # Homebrew builds from source.

  # macOS 15, as the package and the app's Info.plist say: the oldest macOS on which CI installs this formula
  # (macos-14 runners are removed on 2 November 2026).
  depends_on macos: :sequoia
  # Apple's Command Line Tools are enough; Xcode is not needed. Homebrew itself needs them.
  uses_from_macos "swift" => :build

  # something has no package dependency: nothing is downloaded while it builds or is tested.
  deny_network_access! [:build, :test]

  def install
    system "swift", "build", *std_swift_args, "--product", "something"
    # Info.plist with this version, the program, share/, and an ad-hoc signature (no Apple account) that seals it.
    system "tools/make-app.sh", prefix, version.to_s, ".build/release/something"
    # A script that execs the program inside the .app: through a symlink, Bundle.main would not be the .app.
    bin.write_exec_script prefix/"something.app/Contents/MacOS/something"
  end

  # Spotlight does not index Homebrew's prefix; the tour offers a launcher in ~/Applications instead.
  def caveats
    <<~EOS
      Start something once: it can add itself to ~/Applications so Spotlight finds it.
    EOS
  end

  test do
    # Homebrew's test sandbox has no window server: no window can open here, so the version and the seal are tested.
    assert_match version.to_s, shell_output("#{bin}/something --version")
    system "codesign", "--verify", "--deep", "--strict", prefix/"something.app"
  end
end
