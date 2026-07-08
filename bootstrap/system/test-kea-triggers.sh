#!/bin/bash
set -euo pipefail

# test-kea-triggers.sh - Exercise and verify Kea FDW trigger synchronization
# Requires: system and kea databases already created, schemas loaded

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
SYS_USER="${SYS_USER:-system}"
KEA_USER="${KEA_USER:-kea}"
SYS_DB="${SYS_DB:-system}"
KEA_DB="${KEA_DB:-kea}"

PSQL_SYS="psql -h $PGHOST -p $PGPORT -U $SYS_USER -d $SYS_DB -v ON_ERROR_STOP=1"
PSQL_KEA="psql -h $PGHOST -p $PGPORT -U $KEA_USER -d $KEA_DB -v ON_ERROR_STOP=1"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_count() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        echo "  ✓ $desc (count=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

run_sys() {
    $PSQL_SYS -t -A -c "$1"
}

run_kea() {
    $PSQL_KEA -t -A -c "$1"
}

run_sys_q() {
    $PSQL_SYS -c "$1"
}

run_kea_q() {
    $PSQL_KEA -c "$1"
}

echo "=========================================="
echo "Kea Trigger Sync Test Suite"
echo "=========================================="
echo "System DB: $SYS_USER@$PGHOST:$PGPORT/$SYS_DB"
echo "Kea DB:    $KEA_USER@$PGHOST:$PGPORT/$KEA_DB"
echo ""

# -----------------------------------------------------------------------------
# PHASE 1: Load test data
# -----------------------------------------------------------------------------
echo "--- Phase 1: Loading test-data.sql ---"
$PSQL_SYS -f test-data.sql
echo "Test data loaded."
echo ""

# -----------------------------------------------------------------------------
# PHASE 2: Verify initial sync
# -----------------------------------------------------------------------------
echo "--- Phase 2: Verifying initial Kea sync ---"

# 2.1 Networks -> dhcp4_subnet
echo "Checking networks -> dhcp4_subnet..."
subnet_count=$(run_kea "SELECT count(*) FROM dhcp4_subnet;")
assert_count "Subnet count" 1 "$subnet_count"

subnet_prefix=$(run_kea "SELECT subnet_prefix FROM dhcp4_subnet;")
assert_eq "Subnet prefix" "192.168.100.0/24" "$subnet_prefix"

next_server=$(run_kea "SELECT next_server FROM dhcp4_subnet;")
assert_eq "Next server" "192.168.100.1" "$next_server"

boot_file=$(run_kea "SELECT boot_file_name FROM dhcp4_subnet;")
assert_eq "Boot file" "grub/x86_64-efi/core.efi" "$boot_file"

valid_lifetime=$(run_kea "SELECT valid_lifetime FROM dhcp4_subnet;")
assert_eq "Valid lifetime" "3600" "$valid_lifetime"

# 2.2 Subnet options
echo "Checking subnet options..."
net_id=$(run_sys "SELECT id FROM networks WHERE name = 'test-net';")
opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'subnet' AND o.dhcp4_subnet_id = $net_id;")
assert_count "Subnet options" 3 "$opt_count"

# 2.3 Device groups -> dhcp4_client_class
echo "Checking device_groups -> dhcp4_client_class..."
class_count=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name LIKE 'device_group_%';")
assert_count "Device group classes" 2 "$class_count"

# 2.4 Device group options
echo "Checking device group options..."
dg_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class LIKE 'device_group_%';")
assert_count "Device group options" 4 "$dg_opt_count"

# 2.5 dhcp_servers -> dhcp4_server
echo "Checking dhcp_servers -> dhcp4_server..."
srv_count=$(run_kea "SELECT count(*) FROM dhcp4_server;")
assert_count "DHCP servers" 2 "$srv_count"  # 1 for 'all' + 1 test server

# 2.6 dhcp_services -> global parameters
echo "Checking dhcp_services -> global parameters..."
srv_id=$(run_kea "SELECT id FROM dhcp4_server WHERE tag = 'test-dhcp1';")
gp_count=$(run_kea "SELECT count(*) FROM dhcp4_global_parameter gp JOIN dhcp4_global_parameter_server gps ON gp.id = gps.parameter_id WHERE gps.server_id = $srv_id;")
assert_count "Global parameters" 1 "$gp_count"

# 2.7 dhcp_classes/subclasses -> dhcp4_client_class
echo "Checking dhcp_subclasses -> dhcp4_client_class..."
subclass_count=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name LIKE 'match-hardware-%' OR name LIKE 'match-vci-%';")
assert_count "DHCP subclasses" 2 "$subclass_count"

# 2.8 Subclass options
echo "Checking subclass options..."
sc_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class LIKE 'match-%';")
assert_count "Subclass options" 1 "$sc_opt_count"

# 2.9 host_groups -> dhcp4_client_class
echo "Checking host_groups -> dhcp4_client_class..."
hg_class_count=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name LIKE 'host_group_%';")
assert_count "Host group classes" 2 "$hg_class_count"

# 2.10 Host group options (dcg-boot-default)
echo "Checking host group options..."
hg_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class LIKE 'host_group_%';")
assert_count "Host group options" 1 "$hg_opt_count"

# 2.11 Devices -> hosts
echo "Checking devices -> hosts..."
host_count=$(run_kea "SELECT count(*) FROM hosts;")
assert_count "Kea hosts" 5 "$host_count"

# 2.12 Host client classes (from device group)
echo "Checking host client classes..."
h1_id=$(run_sys "SELECT id FROM devices WHERE name = 'host1-mgmt';")
h1_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h1_id;")
assert_eq "Host1 client classes" "device_group_test-servers, host_group_test-group" "$h1_classes"

h2_id=$(run_sys "SELECT id FROM devices WHERE name = 'host2-mgmt';")
h2_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h2_id;")
assert_eq "Host2 client classes" "device_group_test-servers, host_group_test-group-no-boot" "$h2_classes"

# 2.13 Host options (dcg-boot-default)
echo "Checking host options..."
h1_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'host' AND o.host_id = $h1_id;")
assert_count "Host1 options" 1 "$h1_opt_count"

h2_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'host' AND o.host_id = $h2_id;")
assert_count "Host2 options" 0 "$h2_opt_count"  # host2 has no boot_default

echo ""
echo "Initial sync verification complete."
echo ""

# -----------------------------------------------------------------------------
# PHASE 3: Test UPDATE operations
# -----------------------------------------------------------------------------
echo "--- Phase 3: Testing UPDATE operations ---"

# 3.1 Update network dhcp_statements
echo "Updating network dhcp_statements..."
run_sys "UPDATE networks SET dhcp_statements = ARRAY['next-server 192.168.100.2', 'filename \"ipxe/ipxe.efi\"', 'valid-lifetime 7200'] WHERE name = 'test-net';"

next_server=$(run_kea "SELECT next_server FROM dhcp4_subnet;")
assert_eq "Updated next_server" "192.168.100.2" "$next_server"

boot_file=$(run_kea "SELECT boot_file_name FROM dhcp4_subnet;")
assert_eq "Updated boot_file" "ipxe/ipxe.efi" "$boot_file"

valid_lifetime=$(run_kea "SELECT valid_lifetime FROM dhcp4_subnet;")
assert_eq "Updated valid_lifetime" "7200" "$valid_lifetime"

# 3.2 Update network dhcp_options
echo "Updating network dhcp_options..."
run_sys "UPDATE networks SET dhcp_options = ARRAY['domain-name-servers 192.168.100.2', 'routers 192.168.100.2', 'ntp-servers 192.168.100.2', 'domain-name \"updated.example\"'] WHERE name = 'test-net';"

opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'subnet' AND o.dhcp4_subnet_id = $net_id;")
assert_count "Updated subnet options" 4 "$opt_count"

# 3.3 Update device_group name (should rename client class)
echo "Updating device_group name..."
run_sys "UPDATE device_groups SET name = 'test-servers-renamed' WHERE name = 'test-servers';"

dg_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'device_group_test-servers-renamed';")
assert_count "Renamed device group class" 1 "$dg_class"

old_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'device_group_test-servers';")
assert_count "Old device group class gone" 0 "$old_class"

# Verify host client classes updated
h1_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h1_id;")
assert_eq "Host1 updated client classes" "device_group_test-servers-renamed, host_group_test-group" "$h1_classes"

# 3.4 Update device_group dhcp_options
echo "Updating device_group dhcp_options..."
run_sys "UPDATE device_groups SET dhcp_options = ARRAY['dcg-console \"ttyS1,115200n8\"', 'dcg-extra-args \"console=ttyS1\"', 'interface-mtu 9000'] WHERE name = 'test-servers-renamed';"

dg_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class = 'device_group_test-servers-renamed';")
assert_count "Updated device group options" 4 "$dg_opt_count"

# 3.5 Update dhcp_subclass
echo "Updating dhcp_subclass..."
run_sys "UPDATE dhcp_subclasses SET statements = ARRAY['filename \"grub/x86_64-efi/core.efi\"'], options = ARRAY['dcg-boot-default netboot'] WHERE name = '01:aa:bb:cc:dd:ee:ff';"

sc_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_count "Subclass class exists" 1 "$sc_class"

sc_boot=$(run_kea "SELECT boot_file_name FROM dhcp4_client_class WHERE name = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_eq "Updated subclass boot file" "grub/x86_64-efi/core.efi" "$sc_boot"

sc_opt=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_count "Updated subclass options" 1 "$sc_opt"

echo "Updating dhcp_subclass options with encapsulation..."
run_sys "UPDATE dhcp_subclasses SET options = ARRAY['ipxe.no-pxedhcp 1', 'ipxe.bzimage 1'] WHERE name = '01:aa:bb:cc:dd:ee:ff';"

sc_opt=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_count "Updated subclass options" 3 "$sc_opt"

echo "Removing dhcp_subclass options with encapsulation..."
run_sys "UPDATE dhcp_subclasses SET options = NULL WHERE name = '01:aa:bb:cc:dd:ee:ff';"

sc_opt=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_count "Updated subclass options" 0 "$sc_opt"

# 3.6 Update host_group name
echo "Updating host_group name..."
run_sys "UPDATE host_groups SET name = 'test-group-renamed' WHERE name = 'test-group';"

hg_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'host_group_test-group-renamed';")
assert_count "Renamed host group class" 1 "$hg_class"

old_hg=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'host_group_test-group';")
assert_count "Old host group class gone" 0 "$old_hg"

# 3.7 Update host_group boot_default
echo "Updating host_group boot_default..."
run_sys "UPDATE host_groups SET boot_default = 'local' WHERE name = 'test-group-renamed';"

dcg_boot_code=$(run_kea "SELECT code FROM dhcp4_option_def WHERE name = 'dcg-boot-default' AND space = 'dhcp4';")
hg_opt_fmt=$(run_kea "SELECT convert_from(value, 'utf8') FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'client-class' AND o.dhcp_client_class = 'host_group_test-group-renamed' AND o.code = $dcg_boot_code;")
assert_eq "Updated host_group boot_default" "local" "$hg_opt_fmt"

# 3.8 Update host boot_default
echo "Updating host boot_default..."
run_sys "UPDATE hosts SET boot_default = 'netboot' WHERE mgmt_device_id = $h2_id;"

h2_opt_count=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'host' AND o.host_id = $h2_id;")
assert_count "Host2 now has boot_default option" 1 "$h2_opt_count"

h2_opt_val=$(run_kea "SELECT convert_from(value, 'utf8') FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'host' AND o.host_id = $h2_id AND o.code = $dcg_boot_code;")
assert_eq "Host2 boot_default value" "netboot" "$h2_opt_val"

# 3.9 Update host group_id
echo "Updating host group_id..."
hg_id=$(run_sys "SELECT id FROM host_groups WHERE name = 'test-group-renamed';")
run_sys "UPDATE hosts SET group_id = $hg_id WHERE mgmt_device_id = $h2_id;"

h2_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h2_id;")
assert_eq "Host2 client classes updated" "device_group_test-servers-renamed, host_group_test-group-renamed" "$h2_classes"

# 3.10 Update device group_id (moves host between device groups)
echo "Updating device group_id..."
switch_dg_id=$(run_sys "SELECT id FROM device_groups WHERE name = 'test-switches';")
run_sys "UPDATE devices SET group_id = $switch_dg_id WHERE name = 'host1-mgmt';"

h1_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h1_id;")
assert_eq "Host1 client classes after group move" "device_group_test-switches, host_group_test-group-renamed" "$h1_classes"

echo ""
echo "UPDATE tests complete."
echo ""

# -----------------------------------------------------------------------------
# PHASE 4: Test DELETE operations
# -----------------------------------------------------------------------------
echo "--- Phase 4: Testing DELETE operations ---"

# 4.1 Delete host
echo "Deleting host..."
run_sys "DELETE FROM hosts WHERE mgmt_device_id = $h1_id;"

# 4.2 Delete device (cascades to host)
echo "Deleting device..."
run_sys "DELETE FROM devices WHERE name = 'host1-mgmt';"

h1_kea=$(run_kea "SELECT count(*) FROM hosts WHERE host_id = $h1_id;")
assert_count "Host deleted from hosts" 0 "$h1_kea"

# 4.3 Delete network (should remove subnet and options)
echo "Deleting network..."
run_sys "DELETE FROM networks WHERE name = 'test-net';"

subnet_count=$(run_kea "SELECT count(*) FROM dhcp4_subnet;")
assert_count "Subnet deleted" 0 "$subnet_count"

# 4.4 Remove device from device_group
echo "Remove device from device_group..."
run_sys "UPDATE devices SET group_id = NULL WHERE id = $h2_id;"

# Verify host client classes updated
h2_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h2_id;")
assert_eq "Host2 updated client classes" "host_group_test-group-renamed" "$h2_classes"

# 4.4 Delete device_group
echo "Deleting device_group..."
run_sys "DELETE FROM device_groups WHERE name = 'test-servers-renamed';"

dg_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'device_group_test-servers-renamed';")
assert_count "Device group class deleted" 0 "$dg_class"

# 4.5 Delete dhcp_subclass
echo "Deleting dhcp_subclass..."
run_sys "DELETE FROM dhcp_subclasses WHERE name = '01:aa:bb:cc:dd:ee:ff';"

sc_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'match-hardware-01:aa:bb:cc:dd:ee:ff';")
assert_count "Subclass class deleted" 0 "$sc_class"

# 4.6 Delete host_group
echo "Remove host from group..."
run_sys "UPDATE hosts SET group_id = NULL WHERE id = $h2_id;"

echo "Deleting host_group..."
run_sys "DELETE FROM host_groups WHERE name = 'test-group-renamed';"

hg_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'host_group_test-group-renamed';")
assert_count "Host group class deleted" 0 "$hg_class"

echo ""
echo "DELETE tests complete."
echo ""

# -----------------------------------------------------------------------------
# PHASE 5: Test INSERT operations
# -----------------------------------------------------------------------------
echo "--- Phase 5: Testing INSERT operations ---"

# 5.1 Insert new network
echo "Inserting new network..."
run_sys "INSERT INTO networks (name, cidr, dhcp_statements, dhcp_options) VALUES ('new-net', '10.0.0.0/24', ARRAY['next-server 10.0.0.1'], ARRAY['domain-name-servers 10.0.0.1']);"

new_subnet=$(run_kea "SELECT count(*) FROM dhcp4_subnet WHERE subnet_prefix = '10.0.0.0/24';")
assert_count "New network synced" 1 "$new_subnet"

# 5.2 Insert new device_group
echo "Inserting new device_group..."
run_sys "INSERT INTO device_groups (name, dhcp_options) VALUES ('new-device-group', ARRAY['dcg-console \"ttyS0,9600n8\"']);"

new_dg_class=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'device_group_new-device-group';")
assert_count "New device group class created" 1 "$new_dg_class"

# 5.3 Insert new dhcp_server
echo "Inserting new dhcp_server..."
run_sys "INSERT INTO dhcp_servers (name, config, is_primary) VALUES ('test-dhcp2', (SELECT id FROM dhcp_services WHERE name = 'config'), false);"

new_srv=$(run_kea "SELECT count(*) FROM dhcp4_server WHERE tag = 'test-dhcp2';")
assert_count "New dhcp_server synced" 1 "$new_srv"

# 5.4 Insert new dhcp_subclass
echo "Inserting new dhcp_subclass..."
run_sys "INSERT INTO dhcp_subclasses (name, class_id, statements, options) VALUES ('01:11:22:33:44:55:66', (SELECT id FROM dhcp_classes WHERE name = 'match-hardware'), ARRAY['filename \"grub/x86_64-efi/core.efi\"'], ARRAY['dcg-boot-default local']);"

new_sc=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'match-hardware-01:11:22:33:44:55:66';")
assert_count "New subclass synced" 1 "$new_sc"

# 5.5 Insert new host_group
echo "Inserting new host_group..."
loc_id=$(run_sys "SELECT id FROM locations WHERE name = 'Test Lab';")
run_sys "INSERT INTO host_groups (name, boot_default, location_id) VALUES ('new-host-group', 'netboot', $loc_id);"

new_hg=$(run_kea "SELECT count(*) FROM dhcp4_client_class WHERE name = 'host_group_new-host-group';")
assert_count "New host group class created" 1 "$new_hg"

# 5.6 Insert new host
echo "Inserting new host..."
run_sys "INSERT INTO devices (name, mac, ip) VALUES ('host3-mgmt', 'aa:bb:cc:dd:ee:03', '192.168.100.13');"
run_sys "INSERT INTO hosts (mgmt_device_id, group_id, type_id, boot_default, main_profile) VALUES ((SELECT id FROM devices WHERE name = 'host3-mgmt'), (SELECT id FROM host_groups WHERE name = 'new-host-group'), (SELECT id FROM host_types WHERE name = 'test-type'), 'netboot', 'test/profile');"

h3_id=$(run_sys "SELECT id FROM devices WHERE name = 'host3-mgmt';")
host_count=$(run_kea "SELECT count(*) FROM hosts WHERE host_id = $h3_id;")
assert_count "New host in hosts" 1 "$host_count"

h3_classes=$(run_kea "SELECT dhcp4_client_classes FROM hosts WHERE host_id = $h3_id;")
assert_eq "New host client classes" "host_group_new-host-group" "$h3_classes"

h3_opts=$(run_kea "SELECT count(*) FROM dhcp4_options o JOIN dhcp_option_scope s ON o.scope_id = s.scope_id WHERE s.scope_name = 'host' AND o.host_id = $h3_id;")
assert_count "New host options" 1 "$h3_opts"

echo ""
echo "INSERT tests complete."
echo ""

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Some tests FAILED!"
    exit 1
else
    echo ""
    echo "All tests PASSED!"
    exit 0
fi