# The Homebrew formula of something, kept here so that it changes with the code it builds. The CI of this repository
# installs this very file on a fresh Mac (.github/workflows/tests.yml, job "brew"). The tap emiwltz/homebrew-tap gets
# its twin, packaging/homebrew/tap/Formula/something.rb: the same steps and release; the tap adds the bottles' block.
class Something < Formula
  desc "Sees every coding agent on your Mac and gives your HTML pages a bridge to them"
  homepage "https://github.com/emiwltz/something"
  # The release v0.2.0 (the tap's twin names the same tarball and gets its bottles). At the next tag, both
  # formulas take that tag's url and the SHA-256 of the downloaded file (shasum -a 256 <file>).
  url "https://github.com/emiwltz/something/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "88ba2489ded5c448b54730cde4c0ed6effb1006064d158fc0a407ead2c224f43"
  license "MIT"
  head "https://github.com/emiwltz/something.git", branch: "main"

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
