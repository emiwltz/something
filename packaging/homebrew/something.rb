# The Homebrew formula of something, kept here so that it changes with the code it builds. The CI of this repository
# installs this very file on a fresh Mac (.github/workflows/tests.yml, job "brew"). The tap emiwltz/homebrew-tap gets
# its twin, packaging/homebrew/tap/Formula/something.rb: the same steps and release; the tap adds the bottles' block.
class Something < Formula
  desc "Sees every coding agent on your Mac and gives your HTML pages a bridge to them"
  homepage "https://github.com/emiwltz/something"
  # The release v0.3.0, as in the tap's twin, which also gets its bottles. A release: AGENTS.md, "Releasing".
  url "https://github.com/emiwltz/something/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "2bd702734adc7e367bc187150b2fd9c0987303fc0516e83f451a051b77fc13a8"
  license all_of: ["MIT", "OFL-1.1"]
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

  test do
    # Homebrew's test sandbox has no window server: no window can open here, so the version and the seal are tested.
    assert_match version.to_s, shell_output("#{bin}/something --version")
    system "codesign", "--verify", "--deep", "--strict", prefix/"something.app"
  end
end
