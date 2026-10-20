# The Homebrew formula of something, kept here so that it changes with the code it builds. The CI of this repository
# installs this very file on a fresh Mac (.github/workflows/tests.yml, job "brew"). The tap emiwltz/homebrew-tap gets
# its twin, packaging/homebrew/tap/Formula/something.rb: the same steps, plus the tag's url and sha256.
class Something < Formula
  desc "Sees every coding agent on your Mac and gives your HTML pages a bridge to them"
  homepage "https://github.com/emiwltz/something"
  # The url and sha256 lines are added on release day, here and in the tap's formula, before license: the tag's
  # tarball, and the SHA-256 of that downloaded file (shasum -a 256 <file>). Until then the formula builds main
  # (brew install --HEAD):
  #   url "https://github.com/emiwltz/something/archive/refs/tags/<the tag>.tar.gz"
  #   sha256 "<64 hexadecimal digits>"
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
