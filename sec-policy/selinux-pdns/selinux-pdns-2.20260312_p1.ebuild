EAPI="8"

IUSE=""
MODS="pdns"
BASEPOL="2.20260312_p1"
POLICY_FILES="pdns.te pdns.if pdns.fc"

inherit selinux-policy-2

DESCRIPTION="SELinux policy for pdns"

KEYWORDS="~amd64 ~x86"
