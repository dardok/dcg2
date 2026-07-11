BEGIN;

-- SELECT createauditrevisiondhcp4(now(), 'all', 'option defs', false);
SELECT set_config('kea.disable_audit', 'true', false);

CREATE OR REPLACE FUNCTION dhcp4_option_def_data_type_id(type_name varchar) RETURNS smallint AS $$
	SELECT id FROM option_def_data_type WHERE name = type_name;
$$ LANGUAGE sql;

DELETE FROM dhcp4_option_def;

-- APC
INSERT INTO dhcp4_option_def (code, name, space, type, is_array, encapsulate) VALUES
	(1, 'cookie', 'APC', dhcp4_option_def_data_type_id('string'), false, '')
,   (43, 'vendor-encapsulated-options', 'dhcp4', (dhcp4_option_def_data_type_id('empty')), false, 'APC')
;

-- IPXE
INSERT INTO dhcp4_option_def (code, name, space, type, is_array, encapsulate) VALUES 
	(1, 'priority', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (8, 'keep-san', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (9, 'skip-san-boot', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (85, 'syslogs', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (91, 'cert', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (92, 'privkey', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (93, 'crosscert', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (176, 'no-pxedhcp', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (177, 'bus-id', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (188, 'san-filename', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (189, 'bios-drive', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (190, 'username', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (191, 'password', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (192, 'reverse-username', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (193, 'reverse-password', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (235, 'version', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
,   (203, 'iscsi-initiator-iqn', 'ipxe', dhcp4_option_def_data_type_id('string'), false, '')
-- Feature indicators
,   (16, 'pxeext', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (17, 'iscsi', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (18, 'aoe', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (19, 'http', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (20, 'https', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (21, 'tftp', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (22, 'ftp', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (23, 'dns', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (24, 'bzimage', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (25, 'multiboot', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (26, 'slam', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (27, 'srp', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (32, 'nbi', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (33, 'pxe', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (34, 'elf', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (35, 'comboot', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (36, 'efi', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (37, 'fcoe', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (38, 'vlan', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (39, 'menu', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (40, 'sdi', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (41, 'nfs', 'ipxe', dhcp4_option_def_data_type_id('int8'), false, '')
,   (175, 'ipxe-encapsulated-options', 'dhcp4', (dhcp4_option_def_data_type_id('empty')), false, 'ipxe')
;

-- DCG
INSERT INTO dhcp4_option_def (code, name, space, type, is_array, encapsulate) VALUES 
	-- installation hint
	(129, 'dcg-device-group', 'dhcp4', dhcp4_option_def_data_type_id('string'), false, '')
	-- serial console
,	(130, 'dcg-console',      'dhcp4', dhcp4_option_def_data_type_id('string'), false, '')
	-- extra kernel command line args
,	(131, 'dcg-extra-args',   'dhcp4', dhcp4_option_def_data_type_id('string'), false, '')
	-- grub/ipxe menu entry selector
,	(132, 'dcg-boot-default', 'dhcp4', dhcp4_option_def_data_type_id('string'), false, '')
;

INSERT INTO dhcp4_option_def_server (option_def_id, server_id)
	SELECT id, 1 FROM dhcp4_option_def;

COMMIT;
