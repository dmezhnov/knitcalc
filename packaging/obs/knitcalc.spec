# RPM spec for the openSUSE Build Service (home project), repackaging the
# prebuilt Linux bundle from GitHub releases — the upstream build needs the
# exact pinned Flutter SDK, so building from source on OBS is intentionally
# avoided. See packaging/README.md for the update procedure.

# The bundle ships its own Flutter engine and plugin libraries that resolve
# among themselves; keep RPM from requiring/providing them as system libs.
# libjvm is dlopened by the bundled jni plugin only on Android; never on desktop.
%global __requires_exclude ^lib(flutter_linux_gtk|app|dartjni|jvm|.*_plugin)\\.so.*$
%global __provides_exclude ^lib(flutter_linux_gtk|app|dartjni|.*_plugin)\\.so.*$
# Prebuilt binaries: no debuginfo to extract.
%global debug_package %{nil}

Name:           knitcalc
Version:        {{VERSION}}
Release:        0
Summary:        Knitting calculator
License:        MIT
URL:            https://github.com/dmezhnov/knitcalc
Source0:        https://github.com/dmezhnov/knitcalc/releases/download/v%{version}/knitcalc-linux-x64-%{version}.tar.gz
Source1:        https://raw.githubusercontent.com/dmezhnov/knitcalc/v%{version}/LICENSE
BuildRequires:  patchelf
Requires:       gtk3
ExclusiveArch:  x86_64

%description
Gauge conversion, increases/decreases distribution, yarn estimation and
project notes with photos.

%prep
%setup -q -c
# Upstream CI leaves RUNPATHs pointing into the build runner's home; strip
# them so distro rpath checks pass.
for so in lib/libdartjni.so lib/libfile_selector_linux_plugin.so \
          lib/liburl_launcher_linux_plugin.so; do
  patchelf --remove-rpath "$so"
done

%build
# Nothing to build: prebuilt bundle.

%install
install -d %{buildroot}/usr/lib/knitcalc
cp -a knitcalc lib data %{buildroot}/usr/lib/knitcalc/

install -d %{buildroot}%{_bindir}
ln -s ../lib/knitcalc/knitcalc %{buildroot}%{_bindir}/knitcalc

# The bundled launcher ships with an @EXEC@ placeholder that the upstream
# per-user install.sh fills in; point it at the system-wide symlink instead.
sed 's|@EXEC@|/usr/bin/knitcalc|' desktop/io.github.dmezhnov.knitcalc.desktop \
  > io.github.dmezhnov.knitcalc.desktop
install -Dm644 io.github.dmezhnov.knitcalc.desktop \
  -t %{buildroot}%{_datadir}/applications
cp -a desktop/icons %{buildroot}%{_datadir}/
chmod -R u=rwX,go=rX %{buildroot}%{_datadir}/icons

install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%files
/usr/lib/knitcalc
%{_bindir}/knitcalc
%{_datadir}/applications/io.github.dmezhnov.knitcalc.desktop
%{_datadir}/icons/hicolor/*/apps/io.github.dmezhnov.knitcalc.png
%license %{_datadir}/licenses/%{name}/LICENSE

%changelog
