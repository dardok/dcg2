EAPI="8"

IUSE=""
MODS="dcg"
BASEPOL="2.20260312_p1"
POLICY_FILES="dcg.if dcg.te dcg.fc"

inherit selinux-policy-2

DESCRIPTION="SELinux policy for dcg"

KEYWORDS="~amd64 ~x86"

DEPEND+="
        sec-policy/selinux-afs[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-dhcp[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-kerberos[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-ldap[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-postfix[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-sssd[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-sudo[${SELINUX_POLICY_USEDEP}]
"
RDEPEND+="
        sec-policy/selinux-afs[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-dhcp[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-kerberos[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-ldap[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-postfix[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-sssd[${SELINUX_POLICY_USEDEP}]
        sec-policy/selinux-sudo[${SELINUX_POLICY_USEDEP}]
"
