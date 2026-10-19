drop view if exists ldap_entry_objclasses;
drop view if exists ldap_entries;
drop materialized view if exists _ldap_entry_offsets;
drop sequence if exists _ldap_entry_offsets_seq;
drop view if exists _ldap_dhcp_hosts;
drop view if exists _ldap_dhcp_groups;
drop view if exists _ldap_dhcp_subclasses;
drop view if exists _ldap_dhcp_classes;
drop view if exists _ldap_dhcp_subnets;
drop view if exists _ldap_dhcp_services;
drop view if exists _ldap_dhcp_servers;
drop view if exists _ldap_dhcp_ou;
drop view if exists ldap_attr_mappings;
drop materialized view if exists _ldap_dhcp_attr_mappings;
drop sequence if exists _ldap_dhcp_attr_mappings_id_seq;
drop view if exists _ldap_dhcp_host_options;
drop view if exists _ldap_dhcp_host_statements;
drop view if exists _ldap_dhcp_group_options;
drop view if exists _ldap_dhcp_group_statements;
drop view if exists _ldap_dhcp_network_options;
drop view if exists _ldap_dhcp_network_statements;
drop view if exists _ldap_dhcp_subclass_options;
drop view if exists _ldap_dhcp_subclass_statements;
drop view if exists _ldap_dhcp_class_options;
drop view if exists _ldap_dhcp_class_statements;
drop view if exists _ldap_dhcp_config_options;
drop view if exists _ldap_dhcp_config_statements;
drop view if exists ldap_oc_mappings;
drop materialized view if exists _ldap_dhcp_oc_mappings;
drop sequence if exists _ldap_dhcp_oc_mappings_id_seq;

create or replace function ou2dn(text) returns text as $$
	select 'dc=' || array_to_string(regexp_split_to_array($1, E'\\.'), ',dc=');
$$ language sql;

---
--- ldap_oc_mappings
---

create sequence _ldap_dhcp_oc_mappings_id_seq;
create materialized view _ldap_dhcp_oc_mappings (id, name, keytbl, keycol) as
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'organizationalUnit', 'domains', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpServer', 'dhcp_servers', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpService', 'dhcp_services', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpClass', 'dhcp_classes', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpSubClass', 'dhcp_subclasses', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpSubnet', 'networks', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpGroup', 'device_groups', 'id'
	union all
	select nextval('_ldap_dhcp_oc_mappings_id_seq')::integer,
		'dhcpHost', 'devices', 'id'
;
create index on _ldap_dhcp_oc_mappings (name);

create or replace function _ldap_dhcp_oc_mappings_id(text) returns integer as $$
	select id from _ldap_dhcp_oc_mappings where name = $1
$$ language sql;

--  create table ldap_oc_mappings
--  (
--  	id serial not null primary key,
--  	name varchar(64) not null,
--  	keytbl varchar(64) not null,
--  	keycol varchar(64) not null,
--  	create_proc varchar(255),
--  	delete_proc varchar(255),
--  	expect_return int not null
--  );
create view ldap_oc_mappings (id, name, keytbl, keycol,
		create_proc, delete_proc, expect_return) as
	select id, name, keytbl, keycol,
		cast(NULL as text), cast(NULL as text), cast(0 as integer)
	from _ldap_dhcp_oc_mappings;

---
--- ldap_attr_mappings
---

create view _ldap_dhcp_config_statements (id, statement) as
	select id, unnest(statements) from dhcp_services;
--create view _ldap_dhcp_config_options (id, "option") as
--  select id, to_char(a.nr, 'fm000') || ': ' || a.elem
--  from dhcp_services as t
--  left join lateral unnest(t.options) with ordinality as a(elem, nr) on true;
create view _ldap_dhcp_config_options (id, "option") as
	select id, unnest(options) from dhcp_services;

create view _ldap_dhcp_class_statements (id, statement) as
	select id, unnest(statements) from dhcp_classes;
create view _ldap_dhcp_class_options (id, "option") as
	select id, unnest(options) from dhcp_classes;

create view _ldap_dhcp_subclass_statements (id, statement) as
	select id, unnest(statements) from dhcp_subclasses;
create view _ldap_dhcp_subclass_options (id, "option") as
	select id, unnest(options) from dhcp_subclasses;

create view _ldap_dhcp_network_statements (id, statement) as
	select id, unnest(dhcp_statements) from networks;
create view _ldap_dhcp_network_options (id, "option") as
--	select id, 'domain-name-servers ' ||
--		array_to_string(ARRAY(select lower(name) || '.' ||
--				domain() from name_servers), ', ')
--	from networks
--	where networks.dhcp_statements is not null
--	union all
--	select id, 'ntp-servers ' ||
--		array_to_string(ARRAY(select lower(name) || '.' ||
--				domain() from ntp_servers), ', ')
--	from networks
--	where networks.dhcp_statements is not null
--	union all
	select id, unnest(dhcp_options) from networks;

create view _ldap_dhcp_group_statements (id, statement) as
	select id, unnest(dhcp_statements) from device_groups;
create view _ldap_dhcp_group_options (id, "option") as
	select id, 'dcg-device-group "' || name || '"' from device_groups
	union all
	select id, unnest(dhcp_options) from device_groups;

create view _ldap_dhcp_host_statements (id, statement) as
	select id, 'fixed-address ' || host(devices.ip) from devices where devices.ip is not null;
create view _ldap_dhcp_host_options (id, "option") as
	select devices.id, 'dcg-boot-default "' || host_groups.boot_default || '"' from devices join
		hosts on (hosts.mgmt_device_id = devices.id and hosts.boot_default is null) join
		host_groups on (host_groups.id = hosts.group_id)
	union all
	select devices.id, 'dcg-boot-default "' || hosts.boot_default || '"' from devices join
		hosts on (hosts.mgmt_device_id = devices.id and hosts.boot_default is not null);

--

create sequence _ldap_dhcp_attr_mappings_id_seq;
create materialized view _ldap_dhcp_attr_mappings (id, oc_map_id, name,
		sel_expr, from_tbls, join_where) as

	--
	-- organizationalUnit
	--

	-- organizationalUnit.ou
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('organizationalUnit'),
		'ou',
		'distinct(''dhcp'')',
		'domains',
		NULL

	--
	-- dhcpServer
	--

	-- dhcpServer.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpServer'),
		'cn',
		'dhcp_servers.name',
		'dhcp_servers',
		NULL
	-- dhcpServer.dhcpServiceDN
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpServer'),
		'dhcpServiceDN',
		'''cn='' || dhcp_services.name || '',ou=dhcp,'' || ou2dn(domain())',
		'dhcp_servers, dhcp_services',
		'dhcp_servers.config = dhcp_services.id'

	--
	-- dhcpService
	--

	-- dhcpService.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		'cn',
		'dhcp_services.name',
		'dhcp_services',
		NULL
	-- dhcpService.dhcpPrimaryDN
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		'dhcpPrimaryDN',
		'''cn='' || dhcp_servers.name || '',ou=dhcp,'' || ou2dn(domain())',
		'dhcp_services, dhcp_servers',
		'dhcp_services.id = dhcp_servers.config and dhcp_servers.is_primary'
	-- dhcpService.dhcpSecondaryDN
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		'dhcpSecondaryDN',
		'''cn='' || dhcp_servers.name || '',ou=dhcp,'' || ou2dn(domain())',
		'dhcp_services, dhcp_servers',
		'dhcp_services.id = dhcp_servers.config and not dhcp_servers.is_primary'
	-- dhcpService.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		'dhcpStatements',
		'statements.statement',
		'dhcp_services, _ldap_dhcp_config_statements as statements',
		'dhcp_services.id = statements.id'
	-- dhcpService.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		'dhcpOption',
		'options.option',
		'dhcp_services, _ldap_dhcp_config_options as options',
		'dhcp_services.id = options.id'

	--
	-- dhcpClass
	--

	-- dhcpClass.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpClass'),
		'cn',
		'dhcp_classes.name',
		'dhcp_classes',
		NULL
	-- dhcpClass.dhcpSubclassesDN
--	union all
--	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
--		_ldap_dhcp_oc_mappings_id('dhcpClass'),
--		'dhcpSubclassesDN',
--		'''cn='' || dhcp_subclasses.name || '',cn='' || dhcp_classes.name ||
--			'',cn=config,ou=dhcp,'' || ou2dn(domain())',
--		'dhcp_classes, dhcp_subclasses',
--		'dhcp_classes.id = dhcp_subclasses.class_id'
	-- dhcpClass.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpClass'),
		'dhcpStatements',
		'statements.statement',
		'dhcp_classes, _ldap_dhcp_class_statements as statements',
		'dhcp_classes.id = statements.id'
	-- dhcpClass.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpClass'),
		'dhcpOption',
		'options.option',
		'dhcp_classes, _ldap_dhcp_class_options as options',
		'dhcp_classes.id = options.id'

	--
	-- dhcpSubClass
	--

	-- dhcpSubClass.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
		'cn',
		'dhcp_subclasses.name',
		'dhcp_subclasses',
		NULL
	-- dhcpSubClass.dhcpClassData
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
		'dhcpClassData',
		'dhcp_classes.name',
		'dhcp_subclasses, dhcp_classes',
		'dhcp_subclasses.class_id = dhcp_classes.id'
	-- dhcpSubClass.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
		'dhcpStatements',
		'statements.statement',
		'dhcp_subclasses, _ldap_dhcp_subclass_statements as statements',
		'dhcp_subclasses.id = statements.id'
	-- dhcpSubClass.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
		'dhcpOption',
		'options.option',
		'dhcp_subclasses, _ldap_dhcp_subclass_options as options',
		'dhcp_subclasses.id = options.id'

	--
	-- dhcpSubnet
	--

	-- dhcpSubnet.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubnet'),
		'cn',
		'host(cidr)',
		'networks',
		NULL
	-- dhcpSubnet.dhcpNetMask
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubnet'),
		'dhcpNetMask',
		'masklen(networks.cidr)',
		'networks',
		NULL
	-- dhcpSubnet.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubnet'),
		'dhcpStatements',
		'statements.statement',
		'networks, _ldap_dhcp_network_statements as statements',
		'networks.id = statements.id'
	-- dhcpSubnet.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpSubnet'),
		'dhcpOption',
		'options.option',
		'networks, _ldap_dhcp_network_options as options',
		'networks.id = options.id'

	--
	-- dhcpGroup
	--

	-- dhcpGroup.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpGroup'),
		'cn',
		'device_groups.name',
		'device_groups',
		NULL
	-- dhcpGroup.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpGroup'),
		'dhcpStatements',
		'statements.statement',
		'device_groups, _ldap_dhcp_group_statements as statements',
		'device_groups.id = statements.id'
	-- dhcpGroup.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpGroup'),
		'dhcpOption',
		'options.option',
		'device_groups, _ldap_dhcp_group_options as options',
		'device_groups.id = options.id'

	--
	-- dhcpHost
	--

	-- dhcpHost.cn
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpHost'),
		'cn',
		'devices.name',
		'devices',
		NULL
	-- dhcpHost.dhcpHWAddress
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpHost'),
		'dhcpHWAddress',
		'''ethernet '' || cast(devices.mac as text)',
		'devices',
		NULL
	-- dhcpHost.dhcpStatements
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpHost'),
		'dhcpStatements',
		'statements.statement',
		'devices, _ldap_dhcp_host_statements as statements',
		'devices.id = statements.id'
	-- dhcpHost.dhcpOption
	union all
	select nextval('_ldap_dhcp_attr_mappings_id_seq')::integer,
		_ldap_dhcp_oc_mappings_id('dhcpHost'),
		'dhcpOption',
		'options.option',
		'devices, _ldap_dhcp_host_options as options',
		'devices.id = options.id'
;

create index on _ldap_dhcp_attr_mappings (oc_map_id);

--  create table ldap_attr_mappings
--  (
--  	id serial not null primary key,
--  	oc_map_id integer not null references ldap_oc_mappings(id),
--  	name varchar(255) not null,
--  	sel_expr varchar(255) not null,
--  	sel_expr_u varchar(255),
--  	from_tbls varchar(255) not null,
--  	join_where varchar(255),
--  	add_proc varchar(255),
--  	delete_proc varchar(255),
--  	param_order int not null,
--  	expect_return int not null
--  );  
create view ldap_attr_mappings (id, oc_map_id, name,
		sel_expr, sel_expr_u, from_tbls, join_where,
		add_proc, delete_proc,
		param_order, expect_return) as
	select id, oc_map_id, name,
		sel_expr, cast(NULL as text), from_tbls, join_where,
		cast(NULL as text), cast(NULL as text),
		cast(NULL as integer), cast(NULL as integer)
	from _ldap_dhcp_attr_mappings;

---
--- ldap_entries unique sequence numbers
---

create sequence _ldap_entry_offsets_seq;
create materialized view _ldap_entry_offsets (id, name, class_offset) as
	select nextval('_ldap_entry_offsets_seq'), 'organizationalUnit',	700000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpServer',			600000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpService',			500000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpClass',				400000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpSubClass',			300000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpSubnet',			200000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpGroup',				100000000
	union all
	select nextval('_ldap_entry_offsets_seq'), 'dhcpHost', 				0
;
create index on _ldap_entry_offsets (name);

create or replace function _ldap_entry_offset(text) returns integer as $$
	select class_offset from _ldap_entry_offsets where name = $1
$$ language sql;

create or replace function _ldap_entry_range(text) returns integer as $$
	select range
	from (select name, lag(class_offset) over (order by id) - class_offset as range
		from _ldap_entry_offsets) as subquery
	where name = $1
$$ language sql;

create or replace function _ldap_table_max_seq() returns trigger as $$
declare
	_cur integer;
	_max integer;
begin
	begin
		execute format('select currval(''%s'')', TG_ARGV[0]::text) into _cur;
		execute format('select _ldap_entry_range(''%s'')', TG_ARGV[1]::text) into _max;
	exception when others then
		return new;
	end;

	if _cur >= _max then
		raise exception 'value % for sequence ''%'' exceeds max range % for table ''%''',
			_cur, TG_ARGV[0]::text, _max, TG_ARGV[1]::text;
	end if;

	return new;
end
$$ language plpgsql;

create trigger trigger_limit_domains_seq before insert on domains
for each row execute procedure _ldap_table_max_seq('domains_id_seq', 'organizationalUnit');

create trigger trigger_limit_servers_seq before insert on dhcp_servers
for each row execute procedure _ldap_table_max_seq('dhcp_servers_id_seq', 'dhcpServer');

create trigger trigger_limit_services_seq before insert on dhcp_services
for each row execute procedure _ldap_table_max_seq('dhcp_services_id_seq', 'dhcpService');

create trigger trigger_limit_classes_seq before insert on dhcp_classes
for each row execute procedure _ldap_table_max_seq('dhcp_classes_id_seq', 'dhcpClass');

create trigger trigger_limit_subclasses_seq before insert on dhcp_subclasses
for each row execute procedure _ldap_table_max_seq('dhcp_subclasses_id_seq', 'dhcpSubClass');

create trigger trigger_limit_subnets_seq before insert on networks
for each row execute procedure _ldap_table_max_seq('networks_id_seq', 'dhcpSubnet');

create trigger trigger_limit_device_groups_seq before insert on device_groups
for each row execute procedure _ldap_table_max_seq('device_groups_id_seq', 'dhcpGroup');

create trigger trigger_limit_hosts_seq before insert on devices
for each row execute procedure _ldap_table_max_seq('devices_id_seq', 'dhcpHost');

---
--- ldap_entries
---

create view _ldap_dhcp_ou (id, dn, parent) as
	select domains.id,
		'ou=dhcp,' || ou2dn(name),
		0
	from domains limit 1;

create view _ldap_dhcp_servers (id, dn, parent) as
	select dhcp_servers.id,
		'cn=' || dhcp_servers.name || ',' || _ldap_dhcp_ou.dn,
		_ldap_dhcp_ou.id
	from dhcp_servers join _ldap_dhcp_ou on _ldap_dhcp_ou.dn like 'ou=dhcp,%';

create view _ldap_dhcp_services (id, dn, parent) as
	select dhcp_services.id,
		'cn=' || dhcp_services.name || ',' || _ldap_dhcp_ou.dn,
		_ldap_dhcp_ou.id
	from dhcp_services join
		_ldap_dhcp_ou on _ldap_dhcp_ou.dn like 'ou=dhcp,%';

create view _ldap_dhcp_classes (id, dn, parent) as
	select dhcp_classes.id,
		'cn=' || dhcp_classes.name || ',' || _ldap_dhcp_services.dn,
		_ldap_dhcp_services.id
	from dhcp_classes join
		_ldap_dhcp_services on _ldap_dhcp_services.dn like 'cn=config,%';

-- schema says dhcpSubClass has X-NDS_CONTAINMENT dhcpClass, but dhcpd doesn't like that
--create view _ldap_dhcp_subclasses (id, dn, parent) as
--	select dhcp_subclasses.id,
--		'cn=' || dhcp_subclasses.name || ',' || _ldap_dhcp_classes.dn,
--		_ldap_dhcp_classes.id
--	from dhcp_subclasses join
--		_ldap_dhcp_classes on dhcp_subclasses.class_id = _ldap_dhcp_classes.id;

create view _ldap_dhcp_subclasses (id, dn, parent) as
	select dhcp_subclasses.id,
		'cn=' || dhcp_subclasses.name || ',' || _ldap_dhcp_services.dn,
		_ldap_dhcp_services.id
	from dhcp_subclasses join
		_ldap_dhcp_services on _ldap_dhcp_services.dn like 'cn=config,%';

create view _ldap_dhcp_subnets (id, dn, parent) as
	select networks.id,
		'cn=' || networks.name || ',' || _ldap_dhcp_services.dn,
		_ldap_dhcp_services.id
	from networks join
		_ldap_dhcp_services on _ldap_dhcp_services.dn like 'cn=config,%'
	where networks.dhcp_statements is not null;

create view _ldap_dhcp_groups (id, dn, parent) as
	select device_groups.id,
		'cn=' || device_groups.name || ',' || _ldap_dhcp_services.dn,
		_ldap_dhcp_services.id
	from device_groups join
		_ldap_dhcp_services on _ldap_dhcp_services.dn like 'cn=config,%';

create view _ldap_dhcp_hosts (id, dn, parent, poffset) as
	-- grouped devices
	select devices.id,
		'cn=' || devices.name || ',' || _ldap_dhcp_groups.dn,
		_ldap_dhcp_groups.id,
		_ldap_entry_offset('dhcpGroup')
	from devices join
		_ldap_dhcp_groups on devices.group_id = _ldap_dhcp_groups.id join
		networks on (devices.ip << networks.cidr and networks.dhcp_statements is not null)
	where devices.ip is not null and devices.mac is not null
	-- ungrouped devices
	union all
	select devices.id,
		'cn=' || devices.name || ',' || _ldap_dhcp_services.dn,
		_ldap_dhcp_services.id,
		_ldap_entry_offset('dhcpService')
	from devices join
		_ldap_dhcp_services on _ldap_dhcp_services.dn like 'cn=config,%' join
		networks on (devices.ip << networks.cidr and networks.dhcp_statements is not null)
	where devices.ip is not null and devices.mac is not null and devices.group_id is null
;

--  create table ldap_entries
--  (
--  	id serial not null primary key,
--  	dn varchar(255) not null,
--  	oc_map_id integer not null references ldap_oc_mappings(id),
--  	parent int not null,
--  	keyval int not null,
--  	UNIQUE ( oc_map_id, keyval ),
--  	UNIQUE ( dn )
--  );
create view ldap_entries (id, dn, oc_map_id, parent, keyval) as

	select _ldap_entry_offset('organizationalUnit') + id, dn,
		_ldap_dhcp_oc_mappings_id('organizationalUnit'),
		parent, id
	from _ldap_dhcp_ou

	union all
	select _ldap_entry_offset('dhcpServer') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpServer'),
		_ldap_entry_offset('organizationalUnit') + parent, id
	from _ldap_dhcp_servers

	union all
	select _ldap_entry_offset('dhcpService') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpService'),
		_ldap_entry_offset('organizationalUnit') + parent, id
	from _ldap_dhcp_services

	union all
	select _ldap_entry_offset('dhcpClass') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpClass'),
		_ldap_entry_offset('dhcpService') + parent, id
	from _ldap_dhcp_classes

-- schema says dhcpSubClass has X-NDS_CONTAINMENT dhcpClass, but dhcpd doesn't like that
--	union all
--	select _ldap_entry_offset('dhcpSubClass') + id, dn,
--		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
--		_ldap_entry_offset('dhcpClass') + parent, id
--	from _ldap_dhcp_subclasses

	union all
	select _ldap_entry_offset('dhcpSubClass') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpSubClass'),
		_ldap_entry_offset('dhcpService') + parent, id
	from _ldap_dhcp_subclasses

	union all
	select _ldap_entry_offset('dhcpSubnet') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpSubnet'),
		_ldap_entry_offset('dhcpService') + parent, id
	from _ldap_dhcp_subnets

	union all
	select _ldap_entry_offset('dhcpGroup') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpGroup'),
		_ldap_entry_offset('dhcpService') + parent, id
	from _ldap_dhcp_groups

	union all
	select _ldap_entry_offset('dhcpHost') + id, dn,
		_ldap_dhcp_oc_mappings_id('dhcpHost'),
		(poffset + parent), id
	from _ldap_dhcp_hosts
;

---
--- ldap_entry_objclasses
---

--  create table ldap_entry_objclasses
--  (
--  	entry_id integer not null references ldap_entries(id),
--  	oc_name varchar(64)
--  );
create view ldap_entry_objclasses (entry_id, oc_name) as select 0, cast(NULL as text);
