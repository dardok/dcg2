#!/bin/bash

# export PGHOST=192.168.180.2 

createuser -U postgres system
createdb -U postgres -O system system
psql -U postgres -d system -c "ALTER USER system WITH superuser;"
psql -U system -d system -f 00-system-schema.sql

# Kea DHCP

createuser -U postgres kea
createdb -U postgres -O kea kea
psql -U kea -d kea -f /usr/share/kea/scripts/pgsql/dhcpdb_create.pgsql
KEA_SCHEMA_VERSION=$(psql -t -F. -A -U kea -d kea -c "select * from schema_version;")
if [ "${KEA_SCHEMA_VERSION}" != "29.0" ]; then
    printf "**** UNEXPECTED KEA SCHEMA VERSION '%s' ****\n", ${KEA_SCHEMA_VERSION}
fi

# Support view for hacking kea's audit table-based refresh mechanism
psql -U kea -d kea <<"EOF"
CREATE VIEW dhcp4_audit_revision_id_seq_view AS
    SELECT nextval('dhcp4_audit_revision_id_seq') as seq
EOF
# FDW calls to remote views/functions don't see public schema by default
psql -U kea -d kea <<"EOF"
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT format(
            'ALTER FUNCTION %I.%I(%s) SET search_path = %I, pg_catalog;',
            n.nspname,
            p.proname,
            pg_catalog.pg_get_function_identity_arguments(p.oid),
            n.nspname
        ) AS cmd
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
    LOOP
        EXECUTE r.cmd;
    END LOOP;
END $$;
EOF
psql -U kea -d kea -f 01-kea-dhcp4-option-defs.sql
psql -U system -d system -f 02-system-kea-fdw.sql
psql -U system -d system -f 03-system-kea-fns.sql
psql -U system -d system -f 04-system-kea-trg.sql

# PowerDNS

psql -U system -d system -f 05-system-pdns-vws.sql
createuser -U postgres pdns
createdb -U postgres -O pdns pdns
psql -U postgres -d pdns -c "ALTER USER pdns WITH superuser;"
bzcat /usr/share/doc/pdns-*/schema.pgsql.sql.bz2 | psql -U pdns -d pdns
psql -U pdns -d pdns <<"EOF"
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER system_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '127.0.0.1', port '5432', dbname 'system');
CREATE USER MAPPING FOR pdns SERVER system_server OPTIONS (user 'system');

ALTER TABLE comments DROP CONSTRAINT domain_exists;
ALTER TABLE cryptokeys DROP CONSTRAINT cryptokeys_domain_id_fkey;
ALTER TABLE domainmetadata DROP CONSTRAINT domainmetadata_domain_id_fkey;
DROP TABLE IF EXISTS records;
DROP TABLE IF EXISTS domains;
CREATE FOREIGN TABLE domains (
    id integer NOT NULL,
    name varchar(255) NOT NULL,
    master varchar(128) DEFAULT NULL::varchar,
    last_check integer,
    type text NOT NULL,
    notified_serial bigint,
    account varchar(40) DEFAULT NULL::varchar,
    options text,
    catalog text
)
SERVER system_server OPTIONS (schema_name 'public', table_name 'pdns_domains');

CREATE FOREIGN TABLE records (
    id bigint NOT NULL,
    domain_id integer,
    name varchar(255) DEFAULT NULL::varchar,
    type varchar(10) DEFAULT NULL::varchar,
    content varchar(65535) DEFAULT NULL::varchar,
    ttl integer,
    prio integer,
    disabled boolean DEFAULT false,
    ordername varchar(255),
    auth boolean DEFAULT true
)
SERVER system_server OPTIONS (schema_name 'public', table_name 'pdns_records');
EOF

# LOAD
# psql -U system -d system -f system-data.sql
# psql -U system -d system -f switchports.sql
