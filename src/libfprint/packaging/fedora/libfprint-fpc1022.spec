Name:           libfprint-fpc1022
Version:        1.94.100
Release:        1%{?dist}
Summary:        libfprint with FPC1022/Disum 10a5:9200 support
License:        LGPL-2.1-or-later
URL:            https://github.com/sahid-code404/xiaomi-fprint-driver
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gobject-2.0)
BuildRequires:  pkgconfig(gusb)
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  pkgconfig(libusb-1.0)
BuildRequires:  pkgconfig(opencv4)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(udev)
BuildRequires:  doctest-devel

Conflicts:      libfprint
Provides:       libfprint = %{version}

%description
An in-tree, source-built libfprint variant with support for the FPC1022/Disum
match-on-host fingerprint sensor (USB 10a5:9200). It replaces the distribution
libfprint package and is deliberately installed through RPM so the package
database can audit and remove its files.

%prep
%autosetup -n %{name}-%{version}

%build
%meson -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
%meson_build

%check
%meson_test --no-suite libfprint:data
%meson_test udev-hwdb
if meson introspect build --targets | grep -q 'sigfm-tests'; then
    meson compile -C build sigfm-tests
    meson test -C build --print-errorlogs sigfm
fi

%install
%meson_install

%files
%license COPYING
%doc README.md NEWS
%{_libdir}/libfprint-2.so.2*
%{_libdir}/libfprint-2.so
%{_libdir}/pkgconfig/libfprint-2.pc
%{_includedir}/libfprint-2
%{_datadir}/metainfo/org.freedesktop.libfprint.metainfo.xml
%{_udevrulesdir}/*fprint*.rules
%{_udevhwdbdir}/60-autosuspend-libfprint-2.hwdb

%changelog
* Mon Oct 26 2026 Xiaomi FPC1022 maintainers <maintainers@example.invalid> - 1.94.100-1
- Build the FPC1022-enabled libfprint through RPM rather than overwriting files.
