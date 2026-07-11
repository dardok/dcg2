create extension if not exists plpython3u;
create extension if not exists intarray;

drop table if exists k8s_clusters cascade;

drop table if exists dashboard_anchor_overrides cascade;
drop table if exists dashboard_layouts cascade;
drop table if exists dashboard_link_overrides cascade;
drop table if exists dashboard_metric_overrides cascade;
drop table if exists dashboards cascade;

drop table if exists switchports cascade;
drop table if exists hostports cascade;
drop table if exists switches cascade;
drop table if exists switch_types cascade;
drop table if exists vlans cascade;
drop table if exists ksvars cascade;
drop table if exists hosts cascade;
drop table if exists host_types cascade;
drop table if exists host_groups cascade;

drop table if exists dhcp_subclasses cascade;
drop table if exists dhcp_classes cascade;

drop table if exists dhcp_servers cascade;
drop table if exists dhcp_services cascade;

drop table if exists ntp_servers cascade;
drop table if exists ceph_servers cascade;
drop table if exists krb_servers cascade;
drop table if exists tftp_servers cascade;
drop table if exists ldap_servers cascade;
drop table if exists mail_servers cascade;
drop table if exists name_servers cascade;

drop table if exists locations cascade;
drop table if exists reservations cascade;
drop table if exists aliases cascade;
drop table if exists device_groups cascade;
drop table if exists devices cascade;
drop table if exists networks cascade;
drop table if exists domains cascade;

create or replace function _limit_n() returns trigger as $$
declare
	_count integer;
begin
	execute format('select count(*) from %s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME) into _count;

	if _count = TG_ARGV[0]::integer then 
		raise exception 'only % item(s) in table ''%'' currently supported',
			TG_ARGV[0], TG_TABLE_NAME;
	end if;

	return new;
end;
$$ language plpgsql;

-- domains
create table domains (
	id serial primary key,
	name varchar(255) unique not null,
	serialno bigint
);
create trigger trigger_limit_one_domain before insert on domains
for each row execute procedure _limit_n(1);

create or replace function domain() returns text as $$
	select name from domains limit 1
$$ language sql SET search_path = public, pg_temp; -- for dns_views.sql fdw calls

create or replace function domain_id(text) returns integer as $$
	select id from domains where name = $1
$$ language sql;

-- networks
create table networks (
	id serial primary key,
	name varchar(255) not null,
	cidr cidr unique not null,
	dhcp_statements text[],
	dhcp_options text[],
	unique (name, cidr)
);

-- device_groups
create table device_groups (
	id serial primary key,
	name varchar(255) unique not null,
	dhcp_statements text[],
	dhcp_options text[]
);

create or replace function device_group_id(text) returns integer as $$
	select id from device_groups where name = $1
$$ language sql;

-- devices
create table devices (
	id serial primary key,
	name varchar(255) not null,
	mac macaddr,
	ip inet,
	group_id integer references device_groups(id),
	unique (name, ip)
);

create unique index devices_name_ip on devices (name, ip);
create index devices_lower_name_idx on devices (lower(name));
create index devices_upper_ethernet_mac_idx on devices (upper('ethernet ' || cast(mac as text)));
create index devices_mac_is_not_null_idx on devices ((mac is not null));
create index devices_ip_is_not_null_idx on devices ((ip is not null));
create index devices_group_id_is_null_idx on devices ((group_id is null));

create or replace function device_id(text) returns integer as $$
	select id from devices where lower(name) = lower($1)
$$ language sql;

-- reservations
create table reservations (
	mgmt_device_id integer not null references devices(id) on delete cascade,
	reservation integer unique
);

create or replace view reservations_view as
	select devices.name as host_name,
		reservation as reservation
	from reservations
		join devices on (reservations.mgmt_device_id = devices.id);

-- aliases
create table aliases (
	id serial primary key,
	name varchar(255) not null,
	cname varchar(255)
);

-- name_servers
create table name_servers (
	id serial primary key,
	name varchar(255) unique not null
);
-- CREATE OR REPLACE FUNCTION proc_name_servers_insert() RETURNS trigger AS $$
-- DECLARE
-- 	v_name_server_ip cidr;
-- 	v_network_id integer;
-- 	v_dhcp_options text[];
-- BEGIN
-- 	SELECT ip FROM devices WHERE name = new.name INTO v_name_server_ip;

-- 	IF FOUND THEN
-- 		SELECT id, dhcp_options FROM networks WHERE v_name_server_ip << networks.cidr INTO v_network_id, v_dhcp_options;

-- 		IF FOUND THEN
-- 			IF 'domain-name-servers%' LIKE ANY(v_dhcp_options) THEN
-- 		    ELSE
-- 			END IF;

-- 			UPDATE networks SET
--                 dhcp_options = v_dhcp_options
--             WHERE id = v_network_id;
-- 		END IF;
-- 	END IF;
    
--     RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;
-- CREATE TRIGGER name_servers_insert AFTER INSERT ON name_servers FOR EACH ROW EXECUTE PROCEDURE proc_name_servers_insert();
-- CREATE OR REPLACE FUNCTION proc_name_servers_update() RETURNS trigger AS $$
-- BEGIN
--     RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;
-- CREATE TRIGGER name_servers_update AFTER UPDATE ON name_servers FOR EACH ROW EXECUTE PROCEDURE proc_name_servers_update();
-- CREATE OR REPLACE FUNCTION proc_name_servers_delete() RETURNS trigger AS $$
-- BEGIN
--     RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;
-- CREATE TRIGGER name_servers_delete AFTER DELETE ON name_servers FOR EACH ROW EXECUTE PROCEDURE proc_name_servers_delete();

-- mail_servers
create table mail_servers (
	id serial primary key,
	name varchar(255) unique not null
);

-- ldap_servers
create table ldap_servers (
	id serial primary key,
	name varchar(255) unique not null
);

-- tftp_servers
create table tftp_servers (
	id serial primary key,
	name varchar(255) unique not null
);

-- ntp_servers
create table ntp_servers (
	id serial primary key,
	name varchar(255) unique not null
);

-- krb_servers
create table krb_servers (
	id serial primary key,
	name varchar(255) unique not null
);

-- ceph_servers
create table ceph_servers (
	id serial primary key,
	cluster varchar(255) not null,
	name varchar(255) not null,
	unique (cluster, name)
);

-- dhcp_services
create table dhcp_services (
	id serial primary key,
	name varchar(255) unique not null,
	statements text[],
	options text[]
);
create trigger trigger_limit_one_dhcp_service before insert on dhcp_services
for each row execute procedure _limit_n(1);

-- dhcp_servers
create table dhcp_servers (
	id serial primary key,
	name varchar(255) unique not null,
	config integer references dhcp_services(id),
	is_primary boolean
);
create trigger trigger_limit_two_dhcp_servers before insert on dhcp_servers
for each row execute procedure _limit_n(2);

create or replace function _limit_one_primary_dhcp_server() returns trigger as $$
declare
	_count integer;
begin
	if new.is_primary then
		execute format('select count(*) from dhcp_servers where dhcp_servers.is_primary') into _count;

		if _count = 1 then
			raise exception 'only one primary dhcp server is currently supported';
		end if;
	end if;
	return new;
end;
$$ language plpgsql;

create trigger trigger_limit_one_primary_dhcp_server before insert on dhcp_servers
for each row execute procedure _limit_one_primary_dhcp_server();

-- dhcp_classes
create table dhcp_classes (
	id serial primary key,
	name varchar(255) unique not null,
	statements text[],
	options text[]
);
create index dhcp_classes_name_idx on dhcp_classes(upper(name));

create or replace function dhcp_class_id(text) returns integer as $$
	select id from dhcp_classes where name = $1
$$ language sql;

-- dhcp_subclasses
create table dhcp_subclasses (
	id serial primary key,
	name varchar(255) not null,
	class_id integer references dhcp_classes(id),
	statements text[],
	options text[],
	unique (name, class_id)
);
create index dhcp_subclasses_name_idx on dhcp_subclasses(upper(name));

-- locations
create table locations (
	id serial primary key,
	name varchar(255) not null,
	latitude double precision,
	longitude double precision
);

create or replace function location_distance(integer, integer) RETURNS double precision as $$
	with a as (select * from locations where id = $1),
		b as (select * from locations where id = $2)
	select sqrt(power(a.latitude - b.latitude, 2) + power(a.longitude - b.longitude, 2))
	from a, b;
$$ language sql;

create or replace function location_id(text) returns integer as $$
	select id from locations where name = $1
$$ language sql;

-- host_groups
create table host_groups (
	id serial primary key,
	name varchar(255) unique not null,
	boot_default text,
	location_id integer
);

create or replace function host_group_id(text) returns integer as $$
	select id from host_groups where name = $1
$$ language sql;

-- host_types
create table host_types (
	id serial primary key,
	name varchar(255) unique not null,
	arch varchar(255),
	kernel_opt varchar(255),
	cpuflags varchar(255)
);

create or replace function host_type_id(text) returns integer as $$
	select id from host_types where name = $1
$$ language sql;

-- hosts
create table hosts (
	id serial primary key,
	mgmt_device_id integer not null references devices(id) on delete cascade,
	ipmi_device_id integer references devices(id) on delete set null,
	group_id integer references host_groups(id),
	type_id integer references host_types(id),
	boot_default text,
	main_profile text,
	location_id integer,
	unique (mgmt_device_id),
	unique (mgmt_device_id, ipmi_device_id),
	unique (ipmi_device_id)
);

create or replace view host_view as
	select hosts.id as id, 
		devices.name as host_name,
		devices.mac as macaddress,
		devices.ip as ipaddress,
		device_groups.name as device_group_name,
		host_groups.name as host_group_name,
		host_types.name as host_type_name,
		ipmi_devices.mac as ipmi_macaddress,
		ipmi_devices.ip as ipmi_ipaddress,
		hosts.boot_default,
		hosts.main_profile,
		CASE
			WHEN (hosts.location_id IS NULL) THEN host_groups.location_id
			ELSE hosts.location_id
		END as location_id
	from hosts
		join devices on (hosts.mgmt_device_id = devices.id)
		left outer join device_groups on (devices.group_id = device_groups.id)
		left outer join host_groups on (hosts.group_id = host_groups.id)
		left outer join host_types on (hosts.type_id = host_types.id)
		left outer join devices as ipmi_devices on (devices.id = hosts.ipmi_device_id);

create or replace function host_id(text) returns integer as $$
	select id from hosts where mgmt_device_id = device_id($1)
$$ language sql;

-- switch_types
create table switch_types (
	id serial primary key,
	vendor varchar(255) not null,
	model text not null,
	unique (vendor, model)
);

create or replace function switch_type_id(text, text) returns integer as $$
	select id from switch_types where vendor = $1 and model = $2
$$ language sql;

-- switches
create table switches (
	id serial primary key,
	mgmt_device_id integer not null references devices(id) on delete cascade,
	type_id integer references switch_types(id),
	location_id integer,
	default_speed bigint,
	unique (mgmt_device_id)
);

create or replace view switch_view as
	select switches.id as id,
		devices.name as switch_name,
		devices.mac as macaddress,
		devices.ip as ipaddress,
		device_groups.name as device_group_name,
		switch_types.vendor as switch_vendor,
		switch_types.model as switch_model,
		switches.location_id,
		switches.default_speed
	from switches
		join devices on (switches.mgmt_device_id = devices.id)
		left outer join device_groups on (devices.group_id = device_groups.id)
		left outer join switch_types on (switches.type_id = switch_types.id);

create or replace function switch_id(text) returns integer as $$
	select id from switches where mgmt_device_id = device_id($1)
$$ language sql;

-- ksvars
create table ksvars (
	id serial primary key,
	mgmt_device_id integer not null references devices(id) on delete cascade,
	var text,
	val text,
	unique (mgmt_device_id, var)
);

-- vlans
create table vlans (
	id integer not null primary key,
	name text,
	auto_dns bool default false,
	unique (id, name)
);
create index vlans_auto_dns_idx on vlans ((auto_dns = TRUE));

create or replace function ranges(vlans text) returns integer[]
language plpython3u
as $$    
    return sum(((list(range(*[int(j) + k for k,j in enumerate(i.split('-'))]))
         if '-' in i else [int(i)]) for i in vlans.split(',')), [])
$$;

-- hostports
create table hostports (
	id serial primary key,
	host_id integer not null references hosts(id) on delete cascade,
	interface text,
	speed bigint,
	unique (host_id, interface)
);

alter sequence hostports_id_seq restart with 10000;

create or replace view hostport_view as
	select hostports.id as id,
		host_view.host_name as host_name,
		hostports.interface as interface,
		host_view.location_id,
		hostports.speed
	from hostports join host_view on (hostports.host_id = host_view.id);

create or replace function hostport_id(text, text) returns integer as $$
	select id from hostports where host_id = host_id($1) and interface = $2
$$ language sql;

create or replace function lookup_hostport_id(text, text) returns integer as $$
declare
	_hostport_id integer;
begin
	execute format('select id from hostports where host_id = host_id(''%s'') and interface = ''%s''', $1, $2) into _hostport_id;
	if _hostport_id is null then
		raise exception 'hostport %:% not found', $1, $2;
	end if;
	return _hostport_id;
end;
$$ language plpgsql;

-- switchports
create table switchports (
	id serial primary key,
	switch_id integer not null references switches(id) on delete cascade,
	interface text,
	description text,
	access_vlan int, -- references vlans(id) on delete set null,
	trunk_vlans int[], -- (each element of trunk_vlans) references vlans(id) on delete set null
	enabled boolean DEFAULT true,
	hostport_id integer references hostports(id) on delete set null,
	switchport_id integer references switchports(id) on delete set null,
    speed bigint,
	unique (switch_id, interface),
	unique (switchport_id, hostport_id)
);

alter sequence switchports_id_seq restart with 20000;

create or replace view switchport_view as
	select switchports.id as id,
		switch_view.switch_name as switch_name,
		switchports.interface as interface,
		switchports.description as description,
		switchports.access_vlan as access_vlan,
		sort(switchports.trunk_vlans) as trunk_vlans,
		switchports.enabled as enabled,
		switchports.hostport_id as hostport_id,
		switchports.switchport_id as switchport_id,
		switch_view.location_id,
		case
			when (switchports.speed is null) then switch_view.default_speed
			else switchports.speed
		end as speed
	from switchports join switch_view on (switchports.switch_id = switch_view.id);

create or replace function switchport_id(text, text) returns integer as $$
	select id from switchports where switch_id = switch_id($1) and interface = $2
$$ language sql;

create or replace function lookup_switchport_id(text, text) returns integer as $$
declare
	_switchport_id integer;
begin
	execute format('select id from switchports where switch_id = switch_id(''%s'') and interface = ''%s''', $1, $2) into _switchport_id;
	if _switchport_id is null then
		raise exception 'switchport %:% not found', $1, $2;
	end if;
	return _switchport_id;
end;
$$ language plpgsql;

create or replace function _check_switchport() returns trigger as $$
begin
	if new.hostport_id is not null and new.switchport_id is not null then
		raise exception 'hostport_id and switchport_id cannot both be set';
	end if;
	return new;
end;
$$ language plpgsql;

create trigger trigger_check_insert_switchport before insert on switchports
for each row execute procedure _check_switchport();
create trigger trigger_check_update_switchport before update on switchports
for each row execute procedure _check_switchport();

create or replace function _connect_switchports() returns trigger as $$
declare
	_remote integer;
begin
	if old.switchport_id is not null then
		execute format('select switchport_id from switchports where id = %s', old.switchport_id) into _remote;

		if _remote is not null then
			execute format('update switchports set switchport_id = NULL where id = %s', old.switchport_id);
		end if;
	end if;

	if new.switchport_id is not null then
		execute format('select switchport_id from switchports where id = %s', new.switchport_id) into _remote;

		if _remote is null then
			execute format('update switchports set switchport_id = %s where id = %s', new.id, new.switchport_id);
		elsif _remote != new.id then
			execute format('update switchports set switchport_id = %s where id = %s', new.id, _remote);
		end if;
	end if;
	return new;
end;
$$ language plpgsql;

create trigger trigger_insert_switchport after insert on switchports
for each row execute procedure _connect_switchports();
create trigger trigger_update_switchport after update on switchports
for each row execute procedure _connect_switchports();

-- vlans
create or replace view switch_vlans as
	with vlans as (
		select switchport_view.switch_name as switch_name,
			switchport_view.access_vlan as vlan
			from switchport_view
		union all
		select switchport_view.switch_name as switch_name,
			unnest(switchport_view.trunk_vlans) as vlan
			from switchport_view
	)
	select vlans.switch_name as switch_name,
		array_agg(distinct(vlans.vlan)) as vlans
		from vlans where vlans.vlan is not null
		group by vlans.switch_name
	;

create or replace view hostport_vlans as
	with vlans as (
		select hostport_view.host_name as host_name,
			hostport_view.interface as interface,
			unnest(switchport_view.trunk_vlans) as vlan
			from switchport_view
		join hostport_view on
			(hostport_view.id = switchport_view.hostport_id)
	)	
	select vlans.host_name as host_name,
		vlans.interface as interface,
		array_agg(distinct(vlans.vlan)) as vlans
		from vlans where vlans.vlan is not null
		group by vlans.host_name, vlans.interface
	;

create or replace function host_vlans(text) returns setof record as $$
	select interface, unnest(vlans) as vlan from hostport_vlans where host_name = $1
$$ language sql;
-- select * from host_vlans('alien1') as (interface text, vlan integer);

-- connections
create or replace view connections as
	select switchport_view.id as id,
		switchport_view.switch_name as switch_name,
		switchport_view.interface as interface,
		switchport_view.speed as speed,
		switchport_view.location_id as location_id,
		switchport_view.description as description,
		switchport_view.access_vlan as access_vlan,
		sort(switchport_view.trunk_vlans) as trunk_vlans,
		'HOST' as remote_type,
		hostport_view.id as remote_id,
		hostport_view.host_name as remote_name,
		hostport_view.interface as remote_interface,
		hostport_view.speed as remote_speed,
		hostport_view.location_id as remote_location_id
	from switchport_view
		join hostport_view on (switchport_view.hostport_id = hostport_view.id)
		where switchport_view.enabled and hostport_view.speed is not null
	union all
	select switchport_view.id as id,
		switchport_view.switch_name as switch_name,
		switchport_view.interface as interface,
		switchport_view.speed as speed,
		switchport_view.location_id as location_id,
		switchport_view.description as description,
		switchport_view.access_vlan as access_vlan,
		sort(switchport_view.trunk_vlans) as trunk_vlans,
		'SWITCH' as remote_type,
		switchport_view2.id as remote_id,
		switchport_view2.switch_name as remote_name,
		switchport_view2.interface as remote_interface,
		switchport_view2.speed as remote_speed,
		switchport_view2.location_id as remote_location_id
	from switchport_view
		join switchport_view as switchport_view2 on (switchport_view.switchport_id = switchport_view2.id)
		where switchport_view.enabled and switchport_view2.enabled
	;

create or replace view portspeed_view as
	select switchport_view.switch_name as name,
	    switchport_view.interface,
    	switchport_view.speed
   	from switchport_view
	union all
 	select hostport_view.host_name as name,
    	hostport_view.interface,
    	hostport_view.speed
   	from hostport_view;

-- dashboards

create table dashboards
(
	id serial primary key,
	uuid uuid unique not null default gen_random_uuid(),
	name text not null,
	title text
);

create or replace function dashboard_id(text) returns integer as $$
	select id from dashboards where name = $1
$$ language sql;

create table dashboard_layouts (
	id serial primary key,
	uuid uuid default gen_random_uuid() not null,
	dashboard_id integer not null references dashboards(id) on delete cascade,
	node_name text not null,
	relative boolean,
	position integer[],
	relative_to text
);

create table dashboard_anchor_overrides (
	dashboard_id integer not null references dashboards(id) on delete cascade,
	interface text not null,
	remote_interface text not null,
	anchor integer,
	"order" integer
);

create table dashboard_metric_overrides (
	dashboard_id integer not null references dashboards(id) on delete cascade,
	query text,
	override text
);

create table dashboard_link_overrides (
	dashboard_id integer not null references dashboards(id) on delete cascade,
	interface text not null,
	remote_interface text not null,
	hidden bool default false
);

-- k8s

create table k8s_clusters
(
	id serial primary key,
	name text unique not null,
	apiserver_host_id integer not null references hosts(id) on delete set null,
	apiserver_port integer not null default 6443,
	certificate_authority_data text,
	admin_certificate_data text,
	admin_key_data text,
	unique (apiserver_host_id, apiserver_port)
);

create or replace function k8s_cluster_id(text) returns integer as $$
	select id from k8s_clusters where name = $1
$$ language sql;

create or replace view k8s_cluster_view as
	select k8s_clusters.name,
		host_view.host_name as apiserver_host_name,
		k8s_clusters.apiserver_port as apiserver_port,
		k8s_clusters.certificate_authority_data as certificate_authority_data,
		k8s_clusters.admin_certificate_data as admin_certificate_data,
		k8s_clusters.admin_key_data as admin_key_data	
	from k8s_clusters
		join host_view on k8s_clusters.apiserver_host_id = host_view.id;

create or replace view k8s_cluster_configs as
	select name, json_build_object(
		'name', name,
		'cluster', json_build_object(
			'server', 'https://' || apiserver_host_name || ':' || apiserver_port::text,
			'certificate-authority-data', certificate_authority_data
		)
	)::jsonb as cluster_config from k8s_cluster_view;

create or replace view k8s_context_configs as
	select name, json_build_object(
		'name', name,
		'context', json_build_object(
			'cluster', name,
			'user', name || '-admin'
		)
	)::jsonb as context_config from k8s_cluster_view;

create or replace view k8s_admin_configs as
	select name, json_build_object(
		'name', name || '-admin',
		'user', json_build_object(
			'client-certificate-data', admin_certificate_data,
			'client-key-data', admin_key_data
		)
	)::jsonb as admin_config from k8s_cluster_view;

create or replace function k8s_admin_kubeconfig(text[]) returns text as $$
	select json_build_object(
		'apiVersion', 'v1',
		'kind', 'Config',
		'preferences', json_build_object(),
		'clusters', ARRAY(select cluster_config from k8s_cluster_configs where name = ANY($1)),
		'contexts', ARRAY(select context_config from k8s_context_configs where name = ANY($1)),
		'users', ARRAY(select admin_config from k8s_admin_configs where name = ANY($1))
	)::jsonb as kubeconfig;
$$ language sql;

create or replace function k8s_nodes (cluster text)
  returns text[]
as $$
import os
import tempfile
import yaml
import json
import traceback
from kubernetes import client, config

_temp_files = []


def _create_temp_file(content=""):
    handler, name = tempfile.mkstemp()
    _temp_files.append(name)
    os.write(handler, str.encode(content))
    os.close(handler)
    return name


try:
    try:
        config.load_incluster_config()
    except config.ConfigException:
        plan = plpy.prepare("SELECT k8s_admin_kubeconfig(ARRAY[$1]);", ["text"])
        kube_config = next(iter(plpy.execute(plan, [cluster])))
        if kube_config is None:
            return None

        config.load_kube_config(
            _create_temp_file(
                yaml.dump(
                    {
                        **json.loads(kube_config["k8s_admin_kubeconfig"]),
                        **{"current-context": cluster},
                    }
                )
            )
        )

    with client.ApiClient() as cli:
        corev1api = client.CoreV1Api(cli)
        response = corev1api.list_node(limit=10, watch=False)
        nodes = [node.metadata.name for node in response.items]
        while response.metadata._continue is not None:
            response = corev1api.list_node(
                limit=10, watch=False, _continue=response.metadata._continue
            )
            nodes += [node.metadata.name for node in response.items]

    return nodes

except:
    plpy.error(traceback.format_exc())
finally:
    for f in _temp_files:
        os.remove(f)
$$ language plpython3u volatile;

	-- import requests
	-- r = requests.get('http://nrl-dc-xe-00/cgi-bin/graph.py')
	-- return r.text