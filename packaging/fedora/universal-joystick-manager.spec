Name:           universal-joystick-manager
Version:        0.8.0
Release:        1%{?dist}
Summary:        UJM - Universal Joystick Manager for Linux
License:        MIT
BuildArch:      noarch
URL:            https://github.com/joaovitor-dv/universal-joystick-manager
Requires:       bash, systemd, bluez, evtest, python3
Recommends:     upower, python3-gobject-base, polkit
Suggests:       joycond

%description
Universal player numbering, battery indicators and Joy-Con pairing integration.

%install
mkdir -p %{buildroot}%{_datadir}/joystickmanager %{buildroot}%{_libexecdir} %{buildroot}%{_bindir} %{buildroot}%{_unitdir} %{buildroot}%{_docdir}/%{name}
install -m 0755 %{_sourcedir}/joystickmanager.sh %{buildroot}%{_bindir}/joystickmanager.sh
install -m 0755 %{_sourcedir}/joystickmanager-doctor %{buildroot}%{_bindir}/joystickmanager-doctor
install -m 0644 %{_sourcedir}/controllers.tsv %{buildroot}%{_datadir}/joystickmanager/controllers.tsv
install -m 0755 %{_sourcedir}/switchpro-leds.py %{buildroot}%{_libexecdir}/joystickmanager-switchpro-leds
# the unit in the repository points at /usr/local (install.sh); packages install to /usr
sed 's|/usr/local/bin/|%{_bindir}/|' %{_sourcedir}/joystickmanager.service > %{buildroot}%{_unitdir}/joystickmanager.service
# D-Bus bridge for the interface (needs python3-gobject-base; started by the bus, stops by itself)
install -m 0755 %{_sourcedir}/bridge/ujm-bridge %{buildroot}%{_libexecdir}/ujm-bridge
sed 's|/usr/local/libexec/ujm-bridge|%{_libexecdir}/ujm-bridge|' %{_sourcedir}/bridge/ujm-bridge.service > %{buildroot}%{_unitdir}/ujm-bridge.service
install -Dm 0644 %{_sourcedir}/bridge/org.ujm.Manager1.conf %{buildroot}%{_datadir}/dbus-1/system.d/org.ujm.Manager1.conf
install -Dm 0644 %{_sourcedir}/bridge/org.ujm.Manager1.service %{buildroot}%{_datadir}/dbus-1/system-services/org.ujm.Manager1.service
install -Dm 0644 %{_sourcedir}/bridge/org.ujm.manager.policy %{buildroot}%{_datadir}/polkit-1/actions/org.ujm.manager.policy
install -m 0644 %{_sourcedir}/README.md %{buildroot}%{_docdir}/%{name}/README.md
install -m 0644 %{_sourcedir}/LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/joystickmanager.sh
%{_bindir}/joystickmanager-doctor
%{_libexecdir}/joystickmanager-switchpro-leds
%{_datadir}/joystickmanager/controllers.tsv
%{_unitdir}/joystickmanager.service
%{_libexecdir}/ujm-bridge
%{_unitdir}/ujm-bridge.service
%{_datadir}/dbus-1/system.d/org.ujm.Manager1.conf
%{_datadir}/dbus-1/system-services/org.ujm.Manager1.service
%{_datadir}/polkit-1/actions/org.ujm.manager.policy
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%changelog
* Fri Oct 16 2026 João <joao@localhost> - 0.8.0-1
- Version synchronized with the v0.8.0 tag; install the Pro Controller LED helper; unit points at /usr/bin.
