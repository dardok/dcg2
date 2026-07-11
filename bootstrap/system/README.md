# DCG Bootstrap System

Declarative infrastructure management for **Kea DHCP** and **PowerDNS** using PostgreSQL as the source of truth.

## Architecture Overview

```
┌─────────────────┐     FDW (postgres_fdw)      ┌─────────────────┐
│   system DB     │ ◄─────────────────────────► │     kea DB      │
│  (source of     │   Triggers sync changes     │  (Kea DHCP      │
│   truth)        │   to Kea tables in real-    │   tables)       │
└────────┬────────┘   time via AFTER triggers    └────────┬────────┘
         │                                               │
         │ FDW                                           │
         ▼                                               ▼
┌─────────────────┐                             ┌─────────────────┐
│    pdns DB      │                             │  Kea DHCP       │
│  (PowerDNS      │                             │  Service        │
│   views)        │                             │  (reads Kea DB) │
└─────────────────┘                             └─────────────────┘
```

### Three Database Roles

| Database | Owner | Purpose |
|----------|-------|---------|
| `system` | `system` | **Source of truth** - networks, devices, hosts, DHCP config, DNS data |
| `kea`    | `kea`    | Kea DHCP schema + data synced from `system` via FDW triggers |
| `pdns`   | `pdns`   | PowerDNS schema with FDW views reading from `system` |

---

## Component Breakdown

### 1. System Schema (`00-system-schema.sql`)
Core tables for infrastructure modeling:
- **Networks** — CIDR blocks with DHCP statements/options arrays
- **Device Groups** — Hardware profiles with DHCP options
- **Devices** — Management interfaces (MAC/IP) with optional group membership
- **Hosts** — Host records linking mgmt/IPMI devices, host groups, types, boot profiles
- **DHCP Services/Servers** — Global DHCP configuration and server definitions
- **DHCP Classes/Subclasses** — Match expressions (hardware, vendor-class) with statements/options
- **Host Groups** — Logical host groupings with boot defaults
- **Switches/Ports/VLANs** — Data-plane topology
- **Locations** — Geographic metadata for distance calculations
- **Service Tables** — DNS, NTP, LDAP, TFTP, Kerberos, Ceph, mail servers

### 2. Kea Option Definitions (`01-kea-dhcp4-option-defs.sql`)
Registers custom DHCP option spaces in Kea:
- **APC** — Vendor encapsulated options
- **iPXE** — 40+ iPXE-specific options (san-filename, bzimage, no-pxedhcp, etc.)
- **DCG** — Custom options: `dcg-device-group`, `dcg-console`, `dcg-extra-args`, `dcg-boot-default`

### 3. FDW Bridge (`02-system-kea-fdw.sql`)
PostgreSQL Foreign Data Wrapper configuration:
- `kea_server` — FDW server pointing to `kea` database
- Foreign tables for all Kea tables needing sync: `dhcp4_subnet`, `dhcp4_client_class`, `dhcp4_options`, `hosts`, `dhcp4_server`, `dhcp4_global_parameter`, `dhcp4_option_def`, etc.
- **Audit revision hack** — Kea uses audit tables for config reload triggers; FDW exposes `dhcp4_audit_revision_id_seq_view` and `createAuditRevisionDHCP4()` to bump the revision from `system` DB

### 4. Sync Functions (`03-system-kea-fns.sql`)
PL/pgSQL utilities for DHCP data transformation:

| Function | Purpose |
|----------|---------|
| `_parse_dhcp_options(text[])` | Parses `"name value"` or `"space.name value"` strings into (space, name, value) rows |
| `_convert_dhcp_option_value(code, space, text)` | Converts text values to `bytea` per Kea option definition types (uint8/16/32, int8/16/32, string, fqdn, boolean, binary, empty) |
| `apply_dhcp4_options(scope, ...)` | Generic upsert for `dhcp4_options` across scopes: `subnet`, `client-class`, `host`, `global`; handles encapsulation options |
| `apply_dhcp4_statements(table, id_col, id, statements[])` | Applies DHCP statements (`next-server`, `filename`, `valid-lifetime`, `min-valid-lifetime`, `max-valid-lifetime`, `offer-lifetime`) to target table |
| `parse_match_statement(statement, name)` | Converts `match hardware` / `match option vendor-class-identifier` / `substring(...)` to Kea expression syntax |
| `append_string_array_item` / `replace_string_array_item` / `remove_string_array_item` | Comma-separated string array manipulation for `dhcp4_client_classes` CSV column |

### 5. Sync Triggers (`04-system-kea-trg.sql`)
**AFTER triggers** on `system` tables → write to Kea foreign tables:

| Trigger | Source Table | Kea Target | Key Logic |
|---------|--------------|------------|-----------|
| `networks_*` | `networks` | `dhcp4_subnet` | Creates subnet; applies statements + options; deletes subnet when statements/options become NULL |
| `device_groups_*` | `device_groups` | `dhcp4_client_class` | Creates class `device_group_<name>`; injects `dcg-device-group <name>` option; renames class + updates host `dhcp4_client_classes` on name change |
| `devices_*` | `devices` | `hosts` | Creates host reservation when device has MAC+IP; links to subnet via CIDR containment; manages `dhcp4_client_classes` for device group membership |
| `dhcp_servers_*` | `dhcp_servers` | `dhcp4_server` + global params/options | Creates server (ID = system_id + 1); syncs service statements as global parameters + options |
| `dhcp_subclasses_*` | `dhcp_subclasses` | `dhcp4_client_class` | Creates class `<parent>-<name>` with parsed match expression; syncs statements + options |
| `host_groups_*` | `host_groups` | `dhcp4_client_class` | Creates class `host_group_<name>`; manages `dcg-boot-default` option; renames class + updates hosts on name change |
| `hosts_*` | `hosts` | `hosts` | Updates `dhcp4_client_classes` for host group membership; manages host-scoped `dcg-boot-default` option |

### 6. PowerDNS Views (`05-system-pdns-vws.sql`)
Materialized-view-like SQL views exposing DNS data to PowerDNS via FDW:
- `_dns_devices` — Devices with IPs (manual + auto-generated from reservations/VLANs)
- `_dns_a_records` / `_dns_class_c_ptr_records` — Forward/reverse records
- `_dns_mx_records` / `_dns_cname_records` / `_dns_srv_records` — Service records
- `dns_authority` — SOA/NS records per zone
- `dns_lookup` / `dns_allnodes` — Unified record views
- `pdns_domains` / `pdns_records` — PowerDNS foreign table schema mapping

Serial number auto-increment via statement-level triggers on `devices`/`aliases`.

### 7. Test Data (`test-data.sql`)
Minimal fixture for trigger validation:
- 1 domain, 1 location, 1 network with statements/options
- 2 device groups, 1 DHCP service + server
- 2 DHCP classes (match-hardware, match-vci) + 2 subclasses
- 2 host groups (with/without boot_default)
- 6 devices (2 hosts + IPMI + switch)
- 2 hosts with differing group/boot configs
- Switch ports + VLANs

### 8. Test Suite (`test-kea-triggers.sh`)
Bash test runner exercising full CRUD lifecycle:
- **Phase 1** — Load test data
- **Phase 2** — Verify initial sync (subnets, classes, hosts, options)
- **Phase 3** — UPDATE tests (network statements/options, group renames, subclass changes, host moves, boot defaults)
- **Phase 4** — DELETE tests (host, network, device group, subclass, host group)
- **Phase 5** — INSERT tests (new network, device group, server, subclass, host group, host)
- Assertions with pass/fail counting and summary

---

## Data Flow

```
INSERT/UPDATE/DELETE on system tables
         │
         ▼
   AFTER TRIGGER fires
         │
         ▼
   PL/pgSQL function executes
         │
         ├──► Writes to Kea foreign tables (FDW)
         │         │
         │         ▼
         │    Kea DB updated
         │         │
         │         ▼
         │    createAuditRevisionDHCP4()  ──► Kea reloads config
         │
         └──► (for hosts) Updates dhcp4_client_classes CSV
```

---

## Deployment

```bash
# Run as postgres superuser
./init-postgres.sh

# Run tests (requires system+kea databases initialized)
./test-kea-triggers.sh
```

### Prerequisites
- PostgreSQL 14+ with `postgres_fdw`, `plpython3u`, `intarray` extensions
- Kea DHCP 2.9+ (schema version 29.0) with PostgreSQL backend
- PowerDNS 4.8+ with PostgreSQL backend

---

## Extending

### Add Custom DHCP Option
1. Add definition to `01-kea-dhcp4-option-defs.sql`
2. Use in `dhcp_options` arrays as `"dcg-my-option value"`

### Add New Sync Source
1. Add foreign table to `02-system-kea-fdw.sql`
2. Write sync function in `03-system-kea-fns.sql`
3. Create AFTER triggers in `04-system-kea-trg.sql`

### Add DNS Record Type
1. Add view to `05-system-pdns-vws.sql`
2. Map in `pdns_records` view

---

## Design Principles

1. **Declarative** — Describe desired state in `system`; triggers converge Kea/PDNS
2. **Single Source of Truth** — No direct Kea/PDNS writes; all via `system`
3. **Audit-Driven Reload** — Kea config reload triggered by audit revision bump
4. **Scope-Aware Options** — DHCP options scoped to subnet, client-class, host, or global
5. **Encapsulation Auto-Management** — Vendor option spaces (iPXE, APC) get encapsulation options inserted automatically
6. **Idempotent Sync** — Upsert patterns handle re-runs safely
