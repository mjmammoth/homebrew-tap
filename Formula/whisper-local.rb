class WhisperLocal < Formula
  include Language::Python::Virtualenv

  desc "Local real-time voice transcription TUI using Whisper"
  homepage "https://github.com/mjmammoth/whisper.local"
  url "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.1-rc1/whisper_local-0.1.0-py3-none-any.whl"
  sha256 "ccd35d3b6b5b85ae131c1229361353bf20f8691bba3ecbb2c9f82fb5da6f4f0e"
  version "0.1.1-rc1"
  license "MIT"

  depends_on arch: :arm64
  depends_on "python@3.12"
  depends_on "portaudio"
  depends_on "whisper-cpp"

  resource "whisper-local-tui" do
    url "https://github.com/mjmammoth/whisper.local/releases/download/v0.1.1-rc1/whisper-local-tui-darwin-arm64.tar.gz"
    sha256 "7fc6b8cee233295fb005089ad00110cdae07f0ee0794abb4c71e96ea01ca7ca3"
  end

  def install
    venv = virtualenv_create(libexec, "python3.12")
    # Strip Homebrew's SHA256 cache prefix to restore PEP 427 wheel filename for pip
    wheel_name = cached_download.basename.to_s.sub(/\A[0-9a-f]{64}--/i, "")
    wheel_path = buildpath/wheel_name
    cp cached_download, wheel_path
    # Install wheel with dependencies from PyPI (venv.pip_install uses --no-deps)
    system "python3.12", "-m", "pip", "--python=#{libexec}/bin/python",
           "install", "--no-cache-dir", wheel_path

    # Rewrite bundled dylib IDs to @loader_path so Homebrew skips relinking.
    # (Pip wheels bundle native libs with short placeholder IDs that can't
    # fit the full Cellar path in their Mach-O headers.)
    Dir.glob(libexec/"lib/python3.12/site-packages/**/*.dylib") do |dylib|
      chmod 0644, dylib
      system "install_name_tool", "-id", "@loader_path/#{File.basename(dylib)}", dylib
    end

    resource("whisper-local-tui").stage do
      (libexec/"bin").install "whisper-local-tui"
    end
    chmod 0755, libexec/"bin/whisper-local-tui"

    (bin/"whisper-local").write_env_script libexec/"bin/whisper-local", WHISPER_LOCAL_TUI_BIN: libexec/"bin/whisper-local-tui"
    if (libexec/"bin/whisper.local").exist?
      (bin/"whisper.local").write_env_script libexec/"bin/whisper.local", WHISPER_LOCAL_TUI_BIN: libexec/"bin/whisper-local-tui"
    end
  end

  def caveats
    <<~EOS
      whisper.local requires macOS microphone + input monitoring permissions.
      Grant permissions in System Settings > Privacy & Security.

      First run downloads the selected model and may take a few minutes.

      Optional RNNoise support:
        brew install --cask rnnoise
    EOS
  end

  test do
    assert_match "usage", shell_output("#{bin}/whisper-local --help")
    assert_match "bridge", shell_output("#{bin}/whisper-local bridge --help")
  end
end
