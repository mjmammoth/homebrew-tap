require "digest"

class WhisperLocalPreview < Formula
  include Language::Python::Virtualenv

  desc "Local real-time voice transcription TUI using Whisper"
  homepage "https://github.com/mjmammoth/whisper.local"
  url "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev1/whisper_local-0.1.4.dev1-py3-none-any.whl"
  sha256 "38debabe936eb3d99b05283d989207912a28de5662828d03463381441fe46f16"
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
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev1/whisper-local-tui-darwin-arm64.tar.gz",
          "a0cfb72f5d375f7efb4c7bd42dfba1ab13646ea9cbc92ddd0d5369cd8511651a",
        ],
        intel: [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev1/whisper-local-tui-darwin-x64.tar.gz",
          "98865d428390035aeb1621d5cae0b3bdb3b7060d966c349161442a7695ada26a",
        ],
      },
      linux:  {
        arm:   [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev1/whisper-local-tui-linux-arm64.tar.gz",
          "59dee860e480457d57aca516fa56367564969c3db8548130abcc80fae130a1e4",
        ],
        intel: [
          "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.4.dev1/whisper-local-tui-linux-x64.tar.gz",
          "14bd9660d93a40dc72ac9bc7c0fbc33f2a8363c2384a0b51de82f5894a1a31fb",
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
