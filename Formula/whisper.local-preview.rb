require "digest"

class WhisperLocalPreview < Formula
  include Language::Python::Virtualenv

  desc "Local real-time voice transcription TUI using Whisper"
  homepage "https://github.com/mjmammoth/whisper.local"
  url "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev2/whisper_local-0.1.4.dev2-py3-none-any.whl"
  sha256 "09c4500281084b598591583e0c1562db7822d35f8ec02381920db3f1bf9ea4b7"
  license "MIT"

  depends_on "portaudio"
  depends_on "python@3.12"
  depends_on "whisper-cpp"

  conflicts_with "whisper-local", because: "preview formula installs the same executables"

  def install
    virtualenv_create(libexec, "python3.12")
    # Strip Homebrew's SHA256 cache prefix to restore PEP 427 wheel filename for pip
    wheel_name = cached_download.basename.to_s.sub(/\A[0-9a-f]{64}--/i, "")
    wheel_path = buildpath/wheel_name
    cp cached_download, wheel_path

    system "python3.12", "-m", "pip", "--python=#{libexec}/bin/python",
           "install", "--no-cache-dir", wheel_path

    if OS.mac?
      # Pre-set bundled dylib IDs to the path Homebrew's post-install expects,
      # so its relinking step finds them already correct and skips them.
      Dir.glob(libexec/"lib/python3.12/site-packages/**/*.dylib", File::FNM_DOTMATCH) do |dylib|
        chmod 0644, dylib
        rel = Pathname.new(dylib).relative_path_from(prefix)
        target_id = "#{opt_prefix}/#{rel}"

        quiet_system "codesign", "--remove-signature", dylib
        mv "#{dylib}.tmp", dylib if quiet_system "vtool", "-remove-source-version",
                                                           "-output", "#{dylib}.tmp", dylib

        MachO::Tools.change_dylib_id(dylib, target_id)
        system "codesign", "--force", "--sign", "-", dylib
      end
    end

    tui_assets = {
      darwin: {
        arm:   [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev2/whisper-local-tui-darwin-arm64.tar.gz",
          "594f089634c5e1da53af41d99c3e63fce8bbb0412125b12f0a392df48211272d",
        ],
        intel: [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev2/whisper-local-tui-darwin-x64.tar.gz",
          "b5a8181eefa472f1b8fc262fe04dd8de0346d59452fa4526208b46bf6975b7bf",
        ],
      },
      linux:  {
        arm:   [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev2/whisper-local-tui-linux-arm64.tar.gz",
          "3043be90480b4889225351cd6d9cf767b0c17c8abb9b46c31c8f1fdcff2cd986",
        ],
        intel: [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev2/whisper-local-tui-linux-x64.tar.gz",
          "190113bb80d841ee43de90cbb32b1c53ab9a13f3aa7b7e75298e0412c60a4c56",
        ],
      },
    }

    platform_key = if OS.mac?
      :darwin
    elsif OS.linux?
      :linux
    else
      odie "Unsupported platform for whisper-local formula"
    end
    arch_key = if Hardware::CPU.arm?
      :arm
    elsif Hardware::CPU.intel?
      :intel
    else
      odie "Unsupported CPU architecture for whisper-local formula"
    end
    tui_url, tui_sha = tui_assets.fetch(platform_key).fetch(arch_key)
    expected_binary_name = "whisper-local-tui"

    tui_archive = buildpath/"whisper-local-tui.tar.gz"
    system "curl", "-fsSL", "-o", tui_archive, tui_url

    actual_sha = Digest::SHA256.file(tui_archive).hexdigest
    odie "TUI artifact SHA mismatch" if actual_sha != tui_sha

    (libexec/"bin").mkpath
    extraction_marker = buildpath/"whisper-local-tui-path.txt"
    extraction_script = <<~PY
      from pathlib import Path
      import sys

      from whisper_local.archive_extract import install_tui_binary_from_archive

      archive_path = Path(sys.argv[1])
      target_dir = Path(sys.argv[2])
      expected_binary_name = sys.argv[3]
      marker_path = Path(sys.argv[4])
      installed = install_tui_binary_from_archive(
          archive_path=archive_path,
          target_dir=target_dir,
          expected_binary_name=expected_binary_name,
      )
      marker_path.write_text(str(installed), encoding="utf-8")
    PY
    system libexec/"bin/python", "-c", extraction_script,
           tui_archive, libexec/"bin", expected_binary_name, extraction_marker

    tui_bin = Pathname.new(extraction_marker.read.strip)
    chmod 0755, tui_bin
    (bin/"whisper-local").write_env_script(
      libexec/"bin/whisper-local", WHISPER_LOCAL_TUI_BIN: tui_bin
    )
    if (libexec/"bin/whisper.local").exist?
      (bin/"whisper.local").write_env_script(
        libexec/"bin/whisper.local", WHISPER_LOCAL_TUI_BIN: tui_bin
      )
    end
  end

  def caveats
    <<~EOS
      whisper.local can run as a background service:
        whisper.local start
        whisper.local status
        whisper.local tui

      On Wayland, global key swallowing may be unavailable.
      Bind a desktop shortcut to:
        whisper.local trigger toggle

      First run downloads the selected model and may take a few minutes.
    EOS
  end

  test do
    assert_match "usage", shell_output("#{bin}/whisper-local --help")
    assert_match "Service", shell_output("#{bin}/whisper-local status")
  end
end
