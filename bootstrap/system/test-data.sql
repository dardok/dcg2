begin;

-- ============================================================
-- MINIMAL TEST DATA FOR KEA TRIGGER SYNC VALIDATION
-- ============================================================

-- domains (only one allowed)
insert into domains (name, serialno) values
    ('test.example', cast(to_char(now(), 'YYMMDD') || '0001' as bigint));

-- locations
insert into locations (name, latitude, longitude) values
    ('Test Lab', 38.0, -77.0);

-- networks (with dhcp statements and options to test proc_networks_insert/update)
insert into networks (name, cidr, dhcp_statements, dhcp_options) values
    ('test-net', '192.168.100.0/24',
        ARRAY['next-server 192.168.100.1', 'filename "grub/x86_64-efi/core.efi"', 'valid-lifetime 3600'],
        ARRAY['domain-name-servers 192.168.100.1', 'routers 192.168.100.1', 'ntp-servers 192.168.100.1']
    );

-- device_groups (with dhcp options to test proc_device_groups_insert/update)
insert into device_groups (name, dhcp_statements, dhcp_options) values
    ('test-servers', NULL, ARRAY['dcg-console "ttyS0,115200n8"', 'dcg-extra-args "console=ttyS0"']),
    ('test-switches', NULL, NULL);

-- dhcp_services (must be named 'config', only one allowed)
insert into dhcp_services (name, statements, options) values
    ('config', ARRAY['authoritative 1 boolean'], ARRAY['domain-name "test.example"']);

-- dhcp_servers (max 2, only 1 primary)
insert into dhcp_servers (name, config, is_primary) values
    ('test-dhcp1', (select id from dhcp_services where name = 'config'), true);

-- dhcp_classes (match expressions for subclasses)
insert into dhcp_classes (name, statements, options) values
    ('match-hardware', ARRAY['match hardware'], NULL),
    ('match-vci', ARRAY['match option vendor-class-identifier'], NULL);

-- dhcp_subclasses (test proc_dhcp_subclasses_insert/update)
insert into dhcp_subclasses (name, class_id, statements, options) values
    ('01:aa:bb:cc:dd:ee:ff', (select id from dhcp_classes where name = 'match-hardware'),
        ARRAY['filename "ipxe/ipxe.efi"'], ARRAY['dcg-boot-default local']),
    ('PXEClient:Arch:00007', (select id from dhcp_classes where name = 'match-vci'),
        ARRAY['filename "grub/x86_64-efi/core.efi"'], NULL);

-- host_groups (with boot_default to test proc_host_groups_insert/update)
insert into host_groups (name, boot_default, location_id) values
    ('test-group', 'netboot', (select id from locations where name = 'Test Lab')),
    ('test-group-no-boot', NULL, (select id from locations where name = 'Test Lab'));

-- host_types
insert into host_types (name, arch, kernel_opt, cpuflags) values
    ('test-type', 'x86_64', 'GENERIC', 'sse sse2 sse3 ssse3');

-- devices (mgmt devices for hosts and switches)
insert into devices (name, mac, ip, group_id) values
    -- host management interfaces
    ('host1-mgmt', 'aa:bb:cc:dd:ee:01', '192.168.100.10', (select id from device_groups where name = 'test-servers')),
    ('host2-mgmt', 'aa:bb:cc:dd:ee:02', '192.168.100.11', (select id from device_groups where name = 'test-servers')),
    -- switch management interfaces
    ('switch1-mgmt', 'aa:bb:cc:dd:ee:10', '192.168.100.20', (select id from device_groups where name = 'test-switches')),
    -- IPMI interfaces
    ('host1-bmc', 'aa:bb:cc:dd:ee:81', '192.168.100.90', NULL),
    ('host2-bmc', 'aa:bb:cc:dd:ee:82', '192.168.100.91', NULL);

-- switches
insert into switches (mgmt_device_id, type_id, default_speed, location_id) values
    ((select id from devices where name = 'switch1-mgmt'), NULL, 10000000000, (select id from locations where name = 'Test Lab'));

-- hosts (test proc_hosts_insert/update)
insert into hosts (mgmt_device_id, ipmi_device_id, group_id, type_id, boot_default, main_profile) values
    ((select id from devices where name = 'host1-mgmt'),
     (select id from devices where name = 'host1-bmc'),
     (select id from host_groups where name = 'test-group'),
     (select id from host_types where name = 'test-type'),
     'local', 'test/profile'),
    ((select id from devices where name = 'host2-mgmt'),
     (select id from devices where name = 'host2-bmc'),
     (select id from host_groups where name = 'test-group-no-boot'),
     (select id from host_types where name = 'test-type'),
     NULL, 'test/profile');

-- hostports (management plane)
insert into hostports (host_id, interface, speed) values
    ((select id from hosts where mgmt_device_id = (select id from devices where name = 'host1-mgmt')), 'eth0', 1000000000),
    ((select id from hosts where mgmt_device_id = (select id from devices where name = 'host2-mgmt')), 'eth0', 1000000000);

-- switchports (data plane connections between switch and hosts)
insert into switchports (switch_id, interface, hostport_id, trunk_vlans, speed) values
    ((select id from switches where mgmt_device_id = (select id from devices where name = 'switch1-mgmt')), 'Ethernet1',
     (select id from hostports where host_id = (select id from hosts where mgmt_device_id = (select id from devices where name = 'host1-mgmt')) and interface = 'eth0'),
     ARRAY[100, 200], 10000000000),
    ((select id from switches where mgmt_device_id = (select id from devices where name = 'switch1-mgmt')), 'Ethernet2',
     (select id from hostports where host_id = (select id from hosts where mgmt_device_id = (select id from devices where name = 'host2-mgmt')) and interface = 'eth0'),
     ARRAY[100, 200], 10000000000);

-- vlans (referenced by switchports)
insert into vlans (id, name, auto_dns) values
    (100, 'VLAN100', false),
    (200, 'VLAN200', false)
on conflict (id, name) do update set auto_dns = EXCLUDED.auto_dns;

commit;