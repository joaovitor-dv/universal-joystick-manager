Name:           universal-joystick-manager
Version:        0.1.0
Release:        1%{?dist}
Summary:        UJM - Universal Joystick Manager for Linux
License:        MIT
BuildArch:      noarch
Requires:       bash, systemd, bluez
Recommends:     upower, evtest
Suggests:       joycond

%description
Universal player numbering, battery indicators and Joy-Con pairing integration.

%install
mkdir -p %{buildroot}%{_datadir}/joystickmanager %{buildroot}%{_bindir} %{buildroot}%{_unitdir} %{buildroot}%{_docdir}/%{name}
install -m 0755 %{_sourcedir}/joystickmanager.sh %{buildroot}%{_bindir}/joystickmanager.sh
install -m 0755 %{_sourcedir}/joystickmanager-doctor %{buildroot}%{_bindir}/joystickmanager-doctor
install -m 0644 %{_sourcedir}/controllers.tsv %{buildroot}%{_datadir}/joystickmanager/controllers.tsv
install -m 0644 %{_sourcedir}/joystickmanager.service %{buildroot}%{_unitdir}/joystickmanager.service
install -m 0644 %{_sourcedir}/README.md %{buildroot}%{_docdir}/%{name}/README.md
install -m 0644 %{_sourcedir}/LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/joystickmanager.sh
%{_bindir}/joystickmanager-doctor
%{_datadir}/joystickmanager/controllers.tsv
%{_unitdir}/joystickmanager.service
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE
