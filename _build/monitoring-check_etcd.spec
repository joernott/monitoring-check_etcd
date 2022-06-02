#
# spec file for package monitoring-check_etcd
#

Name:           monitoring-check_etcd
Version:        %{version}
Release:        %{release}
Summary:        Check etcd cluster members
License:        BSD
Group:          System/Monitoring
Url:            https://github.com/joernott/monitoring-check_etcd
Source0:        monitoring-check_etcd-%{version}.tar.gz
BuildArch:      noarch
Requires:       curl

%description
A Nagios/Icinga2 check to monitor etcd cluster members written in bash.
This check makes use of etcdctl and curl to the /metrics endpoint.

%prep
%setup -q -n monitoring-check_etcd-%{version}

%install
rm -rf "$RPM_BUILD_ROOT"
mkdir -p "$RPM_BUILD_ROOT/usr/lib64/nagios/plugins"
cp check_etcd.sh "$RPM_BUILD_ROOT/usr/lib64/nagios/plugins/"

%files
%defattr(-,root,root,755)
/usr/lib64/nagios/plugins/check_etcd.sh

%changelog
* Thu Apr 28 2022 Joern Ott <joern.ott@ott-consult.de>
- Fix minor typo
- Standardize RPM; builds and rename repo
* Mon Jan 31 2022 Joern Ott <joern.ott@ott-consult.de>
- Initial RPM build
