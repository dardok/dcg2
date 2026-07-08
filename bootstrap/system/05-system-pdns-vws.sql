drop view if exists dns_authority cascade;
drop view if exists dns_lookup cascade;
drop view if exists _dns_soa_records cascade;
drop view if exists _dns_ns_records cascade;
drop view if exists _dns_srv_records cascade;
drop view if exists _dns_services cascade;
drop view if exists _dns_cname_records cascade;
drop view if exists _dns_mx_records cascade;
drop view if exists dns_findzone cascade;
drop view if exists _dns_class_c_ptr_records cascade;
drop view if exists _dns_a_records cascade;
drop view if exists _dns_devices cascade;
drop view if exists _dns_auto_devices cascade;
drop view if exists _dns_networks cascade;
drop view if exists _dns_auto_networks cascade;

create or replace view _dns_auto_networks (name, cidr) as
	with subnets (subnet) as (select * from generate_series(1, 2))
	select
		'vlan' || vlans.id || '-' || subnets.subnet as name,
		cast('10.' || vlans.id - 1900 || '.' || subnets.subnet || '.0/24' as cidr) as cidr
	from vlans cross join subnets
	where vlans.auto_dns = TRUE;

create or replace view _dns_networks (name, cidr) as
	select name, cidr from networks
	union all
	select name, cidr from _dns_auto_networks;

create or replace view _dns_auto_devices (name, ip) as
	with subnets (subnet) as (select * from generate_series(1, 2))
	, host_reservations (name, reservation) as (
		select
			devices.name, reservations.reservation
		from reservations join devices on devices.id = reservations.mgmt_device_id
	)
	select
		host_reservations.name || '-vlan' || vlans.id || '-' || subnets.subnet as name,
		cast('10.' || vlans.id - 1900 || '.' || subnets.subnet || '.' || host_reservations.reservation as inet) as ip
	from vlans cross join subnets, host_reservations
	where vlans.auto_dns = TRUE;

create or replace view _dns_devices (name, ip) as
	select name, ip from devices where devices.ip is not null
	union all
	select name, ip from _dns_auto_devices;

create or replace function class_c_reverse_zone (text) returns text as $$
	select split_part($1, '.', 3) || '.' ||
		split_part($1, '.', 2) || '.' ||
		split_part($1, '.', 1) || '.in-addr.arpa';
$$ language sql;

create or replace view _dns_a_records (zone, ttl, mx_priority, host, data) as
	select domain(),			-- zone
		1800,					-- ttl
		cast(null as integer),	-- mx_priority
		_dns_devices.name,		-- host
		host(_dns_devices.ip)	-- data
	from _dns_devices join _dns_networks on (_dns_devices.ip << _dns_networks.cidr);

create or replace view _dns_class_c_ptr_records (zone, ttl, mx_priority, host, data) as
	select class_c_reverse_zone(host(_dns_devices.ip)),		-- zone
		1800,												-- ttl
		cast(null as integer),								-- mx_priority
		split_part(host(_dns_devices.ip), '.', 4),			-- host
		_dns_devices.name || '.' || domain() || '.' as data	-- data
	from _dns_devices join _dns_networks on (_dns_devices.ip << _dns_networks.cidr);

--- dns_findzone
create or replace view dns_findzone (zone) as
	select distinct (zone) from (
		select zone from _dns_a_records
		union all
		select zone from _dns_class_c_ptr_records
	) as subquery;

create or replace view _dns_mx_records (zone, ttl, mx_priority, host, data) as
	select domain(),	-- zone
		604800,			-- ttl
		10,				-- mx_priority
		'@',			-- host
		name			-- data
	from mail_servers;

create or replace view _dns_cname_records (zone, ttl, mx_priority, host, data) as
	select domain(),			-- zone
		1800,					-- ttl
		cast(null as integer),	-- mx_priority
		name,					-- host
		cname					-- data
	from aliases;

create or replace view _dns_services (name, priority, weight, port, target) as
	select '_ldap._tcp', 0, 0, 389, name from ldap_servers
	union all
	select '_kerberos._udp', 0, 0, 88, name from krb_servers
	union all
	select '_' || cluster || '-mon._tcp', 0, 0, 6789, name from ceph_servers
;

create or replace view _dns_srv_records (zone, ttl, mx_priority, host, data) as
	select domain(),			-- zone
		604800,					-- ttl
		cast(null as integer),	-- mx_priority
		name,					-- host
		priority || ' ' ||
			weight || ' ' ||
			port || ' ' ||
			target				-- data
	from _dns_services;

create or replace view _dns_ns_records (zone, ttl, data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum) as
	select zone,						-- zone
		604800,							-- ttl
		name_servers.name || '.' ||
			domain() || '.',			-- data
		cast(null as text),				-- primary_ns
		cast(null as text),				-- resp_contact
		cast(null as bigint),			-- serial
		cast(null as integer),			-- refresh
		cast(null as integer),			-- retry
		cast(null as integer),			-- expire
		cast(null as integer)			-- minimum
	from dns_findzone left join name_servers on true;

create or replace view _dns_soa_records (zone, ttl, data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum) as
	select zone,						-- zone
		3600,							-- ttl
		null,							-- data
		(select name || '.' || domain() || '.'
			from name_servers limit 1),	-- primary_ns
		'root.' || domain() || '.',		-- resp_contact
		(select serialno
			from domains limit 1),		-- serial
		21600,							-- refresh
		600,							-- retry
		604800,							-- expire
		3600							-- minimum
	from dns_findzone;

--- dns_lookup
create or replace view dns_lookup (zone, host, ttl, type, mx_priority, data) as
	select zone, host, ttl, 'A', mx_priority, data
	from _dns_a_records
	union all
	select zone, host, ttl, 'PTR', mx_priority, data
	from _dns_class_c_ptr_records
	union all
	select zone, host, ttl, 'MX', mx_priority, data
	from _dns_mx_records
	union all
	select zone, host, ttl, 'CNAME', mx_priority, data
	from _dns_cname_records
	union all
	select zone, host, ttl, 'SRV', mx_priority, data
	from _dns_srv_records
;

--- dns_authority
create or replace view dns_authority (zone, ttl, type, data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum) as
	select zone, ttl, 'NS', data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum
	from _dns_ns_records
	union all
	select zone, ttl, 'SOA', data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum
	from _dns_soa_records
;

--- dns_allnodes
create or replace view dns_allnodes (zone, host, ttl, type, mx_priority, data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum) as
	select zone, NULL, ttl, type, cast(null as integer), data,
		primary_ns, resp_contact, serial, refresh, retry, expire, minimum
	from dns_authority
	union all
	select zone, host, ttl, type, mx_priority, data,
		NULL, NULL, NULL, NULL, NULL, NULL, NULL
	from dns_lookup
;

-- soa serial number
create or replace function update_serialno() returns bigint as $$
declare
	_cur_serialno bigint;
	_cur_date bigint;
	_cur_seq bigint;
	_today bigint;
	_next_seq bigint;
	_next_serialno bigint;
begin
	select serialno into _cur_serialno from domains limit 1;
	select cast(substring(cast(_cur_serialno as text) for 6) as bigint) into _cur_date;
	select cast(substring(cast(_cur_serialno as text) from 9 for 2) as bigint) into _cur_seq;
	select cast(to_char(now(), 'YYMMDD') as bigint) into _today;

	if _cur_date = _today then
		_next_seq = _cur_seq + 1;
	else
		_next_seq = 1;
	end if;

	if _next_seq >= 10000 then
		raise exception 'only 9999 serial number updates are supported per day';
	end if;

	select cast((cast(_today as text) || to_char(_next_seq, 'fm0000')) as bigint) into _next_serialno;

	update domains set serialno = _next_serialno;

	return _next_serialno;
end
$$ language plpgsql;

--
-- devices
--

create or replace function _update_serialno_on_devices() returns trigger as $$
declare
	_count integer;
begin
	if TG_OP = 'UPDATE' then
		select count(1) from newtbl full outer join oldtbl using (name, ip)
		where newtbl.id is null or oldtbl.id is null into _count;
	elsif TG_OP = 'DELETE' then
		select count(*) from oldtbl into _count;
	else
		select count(*) from newtbl into _count;
	end if;

	if _count > 0 then
		perform update_serialno();
	end if;

	return null;
end;
$$ language plpgsql;

-- update
create trigger trigger_update_device_update_serialno after update on devices
referencing new table as newtbl old table as oldtbl for each statement
execute procedure _update_serialno_on_devices();
-- delete
create trigger trigger_delete_device_update_serialno after delete on devices
referencing old table as oldtbl for each statement
execute procedure _update_serialno_on_devices();
-- insert
create trigger trigger_insert_device_update_serialno after insert on devices
referencing new table as newtbl for each statement
execute procedure _update_serialno_on_devices();

--
-- aliases
--

create or replace function _update_serialno_on_aliases() returns trigger as $$
declare
	_count integer;
begin
	if TG_OP = 'UPDATE' then
		select count(1) from newtbl full outer join oldtbl using (name, cname)
		where newtbl.id is null or oldtbl.id is null into _count;
	elsif TG_OP = 'DELETE' then
		select count(*) from oldtbl into _count;
	else
		select count(*) from newtbl into _count;
	end if;

	if _count > 0 then
		perform update_serialno();
	end if;

	return null;
end;
$$ language plpgsql;

-- update
create trigger trigger_update_alias_update_serialno after update on aliases
referencing new table as newtbl old table as oldtbl for each statement
execute procedure _update_serialno_on_aliases();
-- delete
create trigger trigger_delete_alias_update_serialno after delete on aliases
referencing old table as oldtbl for each statement
execute procedure _update_serialno_on_aliases();
-- insert
create trigger trigger_insert_alias_update_serialno after insert on aliases
referencing new table as newtbl for each statement
execute procedure _update_serialno_on_aliases();

-- NEW VIEWS FOR PowerDNS
CREATE OR REPLACE VIEW pdns_domains AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY zone) AS id,
    zone AS name,
    NULL::varchar AS master,
    NULL::integer AS last_check,
    'NATIVE' AS type,
    serial AS notified_serial,
    NULL::varchar AS account,
    NULL::text AS options,
    NULL::text AS catalog
FROM dns_authority WHERE type = 'SOA';

CREATE OR REPLACE VIEW pdns_records AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY 1) AS id,
    (SELECT id FROM pdns_domains WHERE name = zone) AS domain_id,
    CASE
        WHEN type IN ('SOA', 'NS', 'MX') THEN zone
        WHEN type IN ('A', 'PTR', 'CNAME', 'SRV') THEN
            host || '.' || zone
        ELSE host
    END AS name,
    type,
    CASE
        WHEN type = 'SOA' THEN 
            primary_ns || ' ' || 
            resp_contact || ' ' || 
            serial || ' ' || 
            refresh || ' ' || 
            retry || ' ' || 
            expire || ' ' || 
            minimum
        WHEN type = 'MX' THEN
            data || '.' || zone
        WHEN type = 'SRV' THEN
            substring(data from position(' ' in data) + 1) || '.' || zone
        WHEN type IN ('NS', 'PTR') THEN
            rtrim(data, '.') 
        ELSE data
    END AS content,
    ttl,
    CASE
        WHEN type = 'MX' THEN mx_priority
        WHEN type = 'SRV' THEN CAST(split_part(data, ' ', 1) AS INTEGER)
    END AS prio,
    false AS disabled,
    NULL::varchar AS ordername,
    (type IN ('NS', 'SOA')) AS auth
FROM dns_allnodes;