class AvrGccAT11 < Formula
  desc "GNU compiler collection for AVR 8-bit and 32-bit Microcontrollers"
  homepage "https://gcc.gnu.org/"

  url "https://ftp.gnu.org/gnu/gcc/gcc-11.5.0/gcc-11.5.0.tar.xz"
  mirror "https://ftpmirror.gnu.org/gcc/gcc-11.5.0/gcc-11.5.0.tar.xz"
  sha256 "a6e21868ead545cf87f0c01f84276e4b5281d672098591c1c896241f09363478"

  license "GPL-3.0-or-later" => { with: "GCC-exception-3.1" }

  head "https://gcc.gnu.org/git/gcc.git", branch: "releases/gcc-11"

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  pour_bottle? only_if: :clt_installed

  keg_only "it might interfere with other version of avr-gcc.\n" \
           "This is useful if you want to have multiple version of avr-gcc\n" \
           "installed on the same machine"

  depends_on "gmp"
  depends_on "isl"
  depends_on "libmpc"
  depends_on "mpfr"
  depends_on "osx-cross/avr/avr-binutils"

  uses_from_macos "zlib"

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  resource "avr-libc" do
    url "https://github.com/avrdudes/avr-libc/releases/download/avr-libc-2_2_1-release/avr-libc-2.2.1.tar.bz2"
    sha256 "006a6306cbbc938c3bdb583ac54f93fe7d7c8cf97f9cde91f91c6fb0273ab465"
  end

  # Branch from the Darwin maintainer of GCC, with a few generic fixes and
  # Apple Silicon support, located at https://github.com/iains/gcc-11-branch
  patch do
    url "https://raw.githubusercontent.com/Homebrew/formula-patches/5c941992/gcc/gcc-11.5.0.diff"
    sha256 "213b332bd09452e0cf081f874f32d028911fa871875f85b200b55c5b588ce193"
  end

  # Fix argument type mismatch error
  patch do
    url "https://raw.githubusercontent.com/osx-cross/homebrew-avr/e80a6b8/Patch/avr-gcc-11-fix-argument-type-mismatch.patch"
    sha256 "79232a7dcbe71bcf4a0cc52e84cd509553d7b40b887771eec06ac340f5f502f6"
  end

  def version_suffix
    if build.head?
      "HEAD"
    else
      version.major.to_s
    end
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"

    # Even when suffixes are appended, the info pages conflict when
    # install-info is run so pretend we have an outdated makeinfo
    # to prevent their build.
    ENV["gcc_cv_prog_makeinfo_modern"] = "no"

    languages = ["c", "c++"]

    pkgversion = "Homebrew AVR GCC #{pkg_version} #{build.used_options*" "}".strip

    args = %W[
      --target=avr
      --prefix=#{prefix}
      --libdir=#{lib}/avr-gcc/#{version_suffix}

      --enable-languages=#{languages.join(",")}

      --with-ld=#{Formula["avr-binutils"].opt_bin/"avr-ld"}
      --with-as=#{Formula["avr-binutils"].opt_bin/"avr-as"}

      --disable-nls
      --disable-libssp
      --disable-shared
      --disable-threads
      --disable-libgomp

      --with-dwarf2
      --with-avrlibc

      --with-system-zlib

      --with-pkgversion=#{pkgversion}
      --with-bugurl=https://github.com/osx-cross/homebrew-avr/issues
    ]

    # Avoid reference to sed shim
    args << "SED=/usr/bin/sed"

    mkdir "build" do
      system "../configure", *args

      # Use -headerpad_max_install_names in the build,
      # otherwise updated load commands won't fit in the Mach-O header.
      # This is needed because `gcc` avoids the superenv shim.
      system "make", "BOOT_LDFLAGS=-Wl,-headerpad_max_install_names"

      system "make", "install"
    end

    # info and man7 files conflict with native gcc
    rm_r(info)
    rm_r(man7)

    resource("avr-libc").stage do
      ENV.prepend_path "PATH", bin

      ENV.delete "CFLAGS"
      ENV.delete "CXXFLAGS"
      ENV.delete "LD"
      ENV.delete "CC"
      ENV.delete "CXX"

      system "./configure", "--prefix=#{prefix}", "--host=avr"
      system "make", "install"
    end
  end

  test do
    ENV.delete "CPATH"

    hello_c = <<~EOS
      #define F_CPU 8000000UL
      #include <avr/io.h>
      #include <util/delay.h>
      int main (void) {
        DDRB |= (1 << PB0);
        while(1) {
          PORTB ^= (1 << PB0);
          _delay_ms(500);
        }
        return 0;
      }
    EOS

    hello_c_hex = <<~EOS
      :10000000209A91E085B1892785B92FEF34E38CE000
      :0E001000215030408040E1F700C00000F3CFE7
      :00000001FF
    EOS

    hello_c_hex.gsub!("\n", "\r\n")

    (testpath/"hello.c").write(hello_c)

    system "#{bin}/avr-gcc", "-mmcu=atmega328p", "-Os", "-c", "hello.c", "-o", "hello.c.o", "--verbose"
    system "#{bin}/avr-gcc", "hello.c.o", "-o", "hello.c.elf"
    system "#{Formula["avr-binutils"].opt_bin}/avr-objcopy", "-O", "ihex", "-j", ".text", "-j", ".data", \
      "hello.c.elf", "hello.c.hex"

    assert_equal `cat hello.c.hex`, hello_c_hex

    hello_cpp = <<~EOS
      #define F_CPU 8000000UL
      #include <avr/io.h>
      #include <util/delay.h>
      int main (void) {
        DDRB |= (1 << PB0);
        uint8_t array[] = {1, 2, 3, 4};
        for (auto n : array) {
          uint8_t m = n;
          while (m > 0) {
            _delay_ms(500);
            PORTB ^= (1 << PB0);
            m--;
          }
        }
        return 0;
      }
    EOS

    hello_cpp_hex = <<~EOS
      :1000000010E0A0E6B0E0ECE7F0E003C0C895319660
      :100010000D92A636B107D1F700D000D0CDB7DEB72C
      :10002000209A8091600090916100A0916200B0914F
      :10003000630089839A83AB83BC83FE0131969E0162
      :100040002B5F3F4F41E0819181110AC0E217F30716
      :10005000D1F790E080E00F900F900F900F900895EF
      :100060005FEF64E39CE0515060409040E1F700C0D6
      :0C007000000095B1942795B98150E6CFAF
      :06007C0001020304000074
      :00000001FF
    EOS

    hello_cpp_hex.gsub!("\n", "\r\n")

    (testpath/"hello.cpp").write(hello_cpp)

    system "#{bin}/avr-g++", "-mmcu=atmega328p", "-Os", "-c", "hello.cpp", "-o", "hello.cpp.o", "--verbose"
    system "#{bin}/avr-g++", "hello.cpp.o", "-o", "hello.cpp.elf"
    system "#{Formula["avr-binutils"].opt_bin}/avr-objcopy", "-O", "ihex", "-j", ".text", "-j", ".data", \
      "hello.cpp.elf", "hello.cpp.hex"

    assert_equal `cat hello.cpp.hex`, hello_cpp_hex
  end
end
