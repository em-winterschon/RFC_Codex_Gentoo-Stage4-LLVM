#!/usr/bin/env python3
"""Apply a Hetzner DNS desired-state plan with guarded create/update/delete."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib import error, parse, request


def load_json_file(path: str) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_dns_name(value: str) -> str:
    return value.strip().strip("{}").strip().rstrip(".").lower()


def load_token_groups(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.token_groups_json:
        payload = json.loads(args.token_groups_json)
    elif args.token_groups_file:
        payload = load_json_file(args.token_groups_file)
    elif os.getenv("HETZNER_DNS_TOKEN_GROUPS_JSON"):
        payload = json.loads(os.environ["HETZNER_DNS_TOKEN_GROUPS_JSON"])
    else:
        raise RuntimeError(
            "token groups are required via --token-groups-json, --token-groups-file, or env"
        )

    if not isinstance(payload, list):
        raise RuntimeError("token groups must be a list")
    groups: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise RuntimeError(f"token_groups[{index}] must be a mapping")
        name = str(item.get("name", "")).strip()
        if not name:
            raise RuntimeError(f"token_groups[{index}] missing name")
        zones = item.get("zones", [])
        if zones is None:
            zones = []
        if not isinstance(zones, list):
            raise RuntimeError(f"token_groups[{index}].zones must be a list")
        groups.append(
            {
                "name": name,
                "token_name": str(item.get("token_name", "")).strip(),
                "api_token": str(item.get("api_token", "")).strip(),
                "zones": [normalize_dns_name(str(zone)) for zone in zones if str(zone).strip()],
            }
        )
    return groups


def request_json(
    method: str,
    url: str,
    token: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    headers = {"Accept": "application/json"}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = request.Request(url, data=data, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=30) as response:  # noqa: S310
            raw = response.read().decode("utf-8")
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Hetzner DNS {method} {url} failed: HTTP {exc.code}: {body}") from exc
    return json.loads(raw) if raw else {}


def append_query(url: str, params: dict[str, str]) -> str:
    parsed = parse.urlsplit(url)
    query = dict(parse.parse_qsl(parsed.query, keep_blank_values=True))
    query.update(params)
    return parse.urlunsplit(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parse.urlencode(query),
            parsed.fragment,
        )
    )


def pagination_payload(payload: dict[str, Any]) -> dict[str, Any]:
    pagination = payload.get("pagination")
    if isinstance(pagination, dict):
        return pagination
    meta = payload.get("meta")
    if isinstance(meta, dict) and isinstance(meta.get("pagination"), dict):
        return meta["pagination"]
    return {}


def next_page_number(pagination: dict[str, Any], current_page: int) -> int | None:
    next_page = pagination.get("next_page")
    if isinstance(next_page, int):
        return next_page
    if isinstance(next_page, str) and next_page.isdigit():
        return int(next_page)
    last_page = pagination.get("last_page")
    if isinstance(last_page, str) and last_page.isdigit():
        last_page = int(last_page)
    if isinstance(last_page, int) and current_page < last_page:
        return current_page + 1
    return None


def fetch_paginated_payloads(url: str, token: str) -> list[dict[str, Any]]:
    payloads: list[dict[str, Any]] = []
    page = 1
    while True:
        page_url = append_query(url, {"page": str(page), "per_page": "100"})
        payload = request_json("GET", page_url, token)
        payloads.append(payload)
        pagination = pagination_payload(payload)
        next_page = next_page_number(pagination, page)
        if next_page is None:
            break
        page = next_page
    return payloads


def sanitize_provider_error(message: str) -> str:
    message = re.sub(r"Token [A-Za-z0-9._~+/=-]+", "Token REDACTED", message)
    message = re.sub(r"Bearer [A-Za-z0-9._~+/=-]+", "Bearer REDACTED", message)
    return message


def is_already_exists_error(message: str) -> bool:
    return "already exist" in message or "uniqueness_error" in message


def extract_list(
    payload: dict[str, Any], keys: tuple[str, ...], context: str
) -> list[dict[str, Any]]:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    raise RuntimeError(f"{context} response did not contain any of: {', '.join(keys)}")


def rrsets_to_records(rrsets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for rrset in rrsets:
        values = rrset.get("records", rrset.get("values", []))
        if isinstance(values, str):
            values = [values]
        if not isinstance(values, list):
            values = []
        normalized_values: list[str] = []
        for value in values:
            if isinstance(value, dict):
                record_value = str(value.get("value", "")).strip()
            else:
                record_value = str(value).strip()
            if record_value:
                normalized_values.append(record_value)
        records.append(
            {
                "id": str(rrset.get("id", "")).strip(),
                "name": str(rrset.get("name", "")).strip(),
                "type": str(rrset.get("type", "")).strip().upper(),
                "values": normalized_values,
                "ttl": rrset.get("ttl"),
            }
        )
    return records


def extract_records(payload: dict[str, Any], context: str) -> list[dict[str, Any]]:
    rrsets = payload.get("rrsets")
    if isinstance(rrsets, list):
        return rrsets_to_records([item for item in rrsets if isinstance(item, dict)])
    rows = extract_list(payload, ("records", "results"), context)
    records: list[dict[str, Any]] = []
    grouped: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        name = str(row.get("name", "")).strip()
        record_type = str(row.get("type", "")).strip().upper()
        value = str(row.get("value", "")).strip()
        key = (name, record_type)
        grouped.setdefault(
            key,
            {
                "id": str(row.get("id", "")).strip(),
                "name": name,
                "type": record_type,
                "values": [],
                "ttl": row.get("ttl"),
            },
        )
        if value:
            grouped[key]["values"].append(value)
    records.extend(grouped.values())
    return records


def fixture_group(fixture: dict[str, Any], token_group_name: str) -> dict[str, Any] | None:
    for group in fixture.get("token_groups", []):
        if isinstance(group, dict) and group.get("name") == token_group_name:
            return group
    return None


def fixture_zones(fixture: dict[str, Any], token_group_name: str) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    if not group:
        return []
    zones = group.get("zones", [])
    if not isinstance(zones, list):
        return []
    return [zone for zone in zones if isinstance(zone, dict)]


def fixture_records(
    fixture: dict[str, Any], token_group_name: str, zone_id: str
) -> list[dict[str, Any]]:
    group = fixture_group(fixture, token_group_name)
    if not group:
        return []
    records_by_zone_id = group.get("records_by_zone_id", {})
    if not isinstance(records_by_zone_id, dict):
        return []
    payload = records_by_zone_id.get(zone_id, [])
    if isinstance(payload, dict):
        return extract_records(payload, "fixture records")
    if isinstance(payload, list):
        return rrsets_to_records([record for record in payload if isinstance(record, dict)])
    return []


def fetch_zones(api_endpoint: str, token: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for payload in fetch_paginated_payloads(f"{api_endpoint.rstrip('/')}/zones", token):
        rows.extend(extract_list(payload, ("zones", "results"), "zones"))
    return rows


def fetch_zone_records(api_endpoint: str, token: str, zone_id: str) -> list[dict[str, Any]]:
    base_url = api_endpoint.rstrip("/")
    urls = [
        f"{base_url}/zones/{parse.quote(zone_id, safe='')}/rrsets",
        f"{base_url}/records?{parse.urlencode({'zone_id': zone_id})}",
        f"{base_url}/zones/{parse.quote(zone_id, safe='')}/records",
    ]
    last_error: RuntimeError | None = None
    for url in urls:
        try:
            rows: list[dict[str, Any]] = []
            for payload in fetch_paginated_payloads(url, token):
                rows.extend(extract_records(payload, "records"))
            return rows
        except RuntimeError as exc:
            last_error = exc
    raise last_error or RuntimeError(f"could not fetch records for zone id {zone_id}")


def rrset_payload(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": record["relative_name"],
        "type": record["type"],
        "ttl": int(record.get("ttl") or 300),
        "records": [{"value": value} for value in record.get("values", [])],
    }


def records_payload(record: dict[str, Any]) -> dict[str, Any]:
    return {"records": [{"value": value} for value in record.get("values", [])]}


def create_rrset(api_endpoint: str, token: str, zone_id: str, record: dict[str, Any]) -> None:
    url = f"{api_endpoint.rstrip('/')}/zones/{parse.quote(zone_id, safe='')}/rrsets"
    request_json("POST", url, token, rrset_payload(record))


def update_rrset(
    api_endpoint: str, token: str, zone_id: str, rrset_id: str, record: dict[str, Any]
) -> None:
    url = (
        f"{api_endpoint.rstrip('/')}/zones/{parse.quote(zone_id, safe='')}"
        f"/rrsets/{parse.quote(record['relative_name'], safe='')}"
        f"/{parse.quote(record['type'], safe='')}/actions/set_records"
    )
    request_json("POST", url, token, records_payload(record))


def delete_rrset(api_endpoint: str, token: str, zone_id: str, rrset_id: str) -> None:
    url = (
        f"{api_endpoint.rstrip('/')}/zones/{parse.quote(zone_id, safe='')}"
        f"/rrsets/{parse.quote(rrset_id, safe='')}"
    )
    request_json("DELETE", url, token)


def zone_lookup(
    *,
    token_groups: list[dict[str, Any]],
    api_endpoint: str,
    fixture: dict[str, Any] | None,
) -> dict[tuple[str, str], dict[str, Any]]:
    zones: dict[tuple[str, str], dict[str, Any]] = {}
    for group in token_groups:
        provider_zones = (
            fixture_zones(fixture, group["name"])
            if fixture is not None
            else fetch_zones(api_endpoint, group["api_token"])
        )
        zone_names = set(group["zones"])
        for zone in provider_zones:
            zone_name = normalize_dns_name(str(zone.get("name", "")))
            if zone_names and zone_name not in zone_names:
                continue
            zone_id = str(zone.get("id", "")).strip()
            if not zone_name or not zone_id:
                continue
            zones[(group["name"], zone_name)] = {
                "id": zone_id,
                "name": zone_name,
                "token_group": group["name"],
                "api_token": group["api_token"],
            }
    return zones


def current_record_lookup(
    *,
    token_groups: list[dict[str, Any]],
    api_endpoint: str,
    fixture: dict[str, Any] | None,
    zones: dict[tuple[str, str], dict[str, Any]],
) -> dict[tuple[str, str, str, str], dict[str, Any]]:
    by_group = {group["name"]: group for group in token_groups}
    records: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for (group_name, zone_name), zone in zones.items():
        group = by_group[group_name]
        rows = (
            fixture_records(fixture, group_name, zone["id"])
            if fixture is not None
            else fetch_zone_records(api_endpoint, group["api_token"], zone["id"])
        )
        for row in rows:
            key = (
                group_name,
                zone_name,
                str(row.get("name", "")).strip(),
                str(row.get("type", "")).strip().upper(),
            )
            records[key] = {
                "id": str(row.get("id", "")).strip(),
                "values": sorted(set(str(value) for value in row.get("values", []))),
                "ttl": int(row.get("ttl") or 300),
            }
    return records


def find_current_record(
    *,
    api_endpoint: str,
    token: str,
    zone_id: str,
    relative_name: str,
    record_type: str,
) -> dict[str, Any] | None:
    for row in fetch_zone_records(api_endpoint, token, zone_id):
        if (
            str(row.get("name", "")).strip() == relative_name
            and str(row.get("type", "")).strip().upper() == record_type
        ):
            return {
                "id": str(row.get("id", "")).strip(),
                "values": sorted(set(str(value) for value in row.get("values", []))),
                "ttl": int(row.get("ttl") or 300),
            }
    return None


def apply_dns_plan(
    *,
    plan: dict[str, Any],
    token_groups: list[dict[str, Any]],
    api_endpoint: str,
    apply: bool,
    allow_delete: bool,
    fixture: dict[str, Any] | None = None,
) -> dict[str, Any]:
    zones = zone_lookup(token_groups=token_groups, api_endpoint=api_endpoint, fixture=fixture)
    current = current_record_lookup(
        token_groups=token_groups,
        api_endpoint=api_endpoint,
        fixture=fixture,
        zones=zones,
    )
    current_types_by_name: dict[tuple[str, str, str], set[str]] = {}
    for group_name, zone_name, relative_name, record_type in current:
        current_types_by_name.setdefault((group_name, zone_name, relative_name), set()).add(
            record_type
        )

    actions: list[dict[str, str]] = []
    summary = {
        "planned": 0,
        "created": 0,
        "updated": 0,
        "deleted": 0,
        "unchanged": 0,
        "errors": 0,
    }

    for record in plan.get("records", []):
        if not isinstance(record, dict):
            continue
        group_name = str(record.get("token_group", "")).strip()
        zone_name = normalize_dns_name(str(record.get("zone", "")))
        relative_name = str(record.get("relative_name", "")).strip()
        record_type = str(record.get("type", "")).strip().upper()
        action = str(record.get("action", "ensure")).strip().lower()
        desired_values = sorted(set(str(value) for value in record.get("values", [])))
        zone = zones.get((group_name, zone_name))
        name_key = (group_name, zone_name, relative_name)
        result = {
            "action": action,
            "token_group": group_name,
            "zone": zone_name,
            "name": relative_name,
            "type": record_type,
            "result": "planned",
        }

        if not zone:
            result["result"] = "error"
            result["reason"] = "zone_not_found"
            summary["errors"] += 1
            actions.append(result)
            continue

        current_types = current_types_by_name.get(name_key, set())
        has_type_conflict = action != "delete" and any(
            (record_type == "CNAME" and current_type != "CNAME")
            or (record_type != "CNAME" and current_type == "CNAME")
            for current_type in current_types
        )
        if has_type_conflict:
            result["result"] = "error"
            result["reason"] = "existing_rrset_type_conflict"
            result["current_types"] = ",".join(sorted(current_types))
            summary["errors"] += 1
            actions.append(result)
            continue

        current_key = (group_name, zone_name, relative_name, record_type)
        existing = current.get(current_key)

        if action == "delete":
            if not allow_delete:
                result["result"] = "error"
                result["reason"] = "delete_not_allowed"
                summary["errors"] += 1
            elif existing:
                result["result"] = "deleted" if apply else "planned_delete"
                if apply and fixture is None:
                    try:
                        delete_rrset(api_endpoint, zone["api_token"], zone["id"], existing["id"])
                        summary["deleted"] += 1
                    except RuntimeError as exc:
                        result["result"] = "error"
                        result["reason"] = "provider_delete_failed"
                        result["detail"] = sanitize_provider_error(str(exc))
                        summary["errors"] += 1
                else:
                    summary["planned"] += 1
            else:
                result["result"] = "unchanged"
                result["reason"] = "already_absent"
                summary["unchanged"] += 1
            actions.append(result)
            continue

        if existing and existing["values"] == desired_values:
            result["result"] = "unchanged"
            summary["unchanged"] += 1
        elif existing:
            result["result"] = "updated" if apply else "planned_update"
            if apply and fixture is None:
                try:
                    update_rrset(api_endpoint, zone["api_token"], zone["id"], existing["id"], record)
                    summary["updated"] += 1
                except RuntimeError as exc:
                    result["result"] = "error"
                    result["reason"] = "provider_update_failed"
                    result["detail"] = sanitize_provider_error(str(exc))
                    summary["errors"] += 1
            else:
                summary["planned"] += 1
        else:
            result["result"] = "created" if apply else "planned_create"
            if apply and fixture is None:
                try:
                    create_rrset(api_endpoint, zone["api_token"], zone["id"], record)
                    summary["created"] += 1
                except RuntimeError as exc:
                    if is_already_exists_error(str(exc)):
                        latest = find_current_record(
                            api_endpoint=api_endpoint,
                            token=zone["api_token"],
                            zone_id=zone["id"],
                            relative_name=relative_name,
                            record_type=record_type,
                        )
                        if latest and latest["values"] == desired_values:
                            result["result"] = "unchanged"
                            result["reason"] = "already_exists_matches"
                            summary["unchanged"] += 1
                        elif latest:
                            try:
                                update_rrset(
                                    api_endpoint,
                                    zone["api_token"],
                                    zone["id"],
                                    latest["id"],
                                    record,
                                )
                                result["result"] = "updated"
                                result["reason"] = "already_exists_updated"
                                summary["updated"] += 1
                            except RuntimeError as update_exc:
                                result["result"] = "error"
                                result["reason"] = "provider_update_after_create_conflict_failed"
                                result["detail"] = sanitize_provider_error(str(update_exc))
                                summary["errors"] += 1
                        else:
                            result["result"] = "error"
                            result["reason"] = "provider_create_conflict_unresolved"
                            result["detail"] = sanitize_provider_error(str(exc))
                            summary["errors"] += 1
                    else:
                        result["result"] = "error"
                        result["reason"] = "provider_create_failed"
                        result["detail"] = sanitize_provider_error(str(exc))
                        summary["errors"] += 1
            else:
                summary["planned"] += 1
        actions.append(result)

    return {
        "apply": apply,
        "allow_delete": allow_delete,
        "provider": "hetzner_cloud_dns",
        "summary": summary,
        "actions": actions,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-file", required=True)
    parser.add_argument("--token-groups-json", default="")
    parser.add_argument("--token-groups-file", default="")
    parser.add_argument("--api-endpoint", default=os.getenv("HETZNER_DNS_API_ENDPOINT", "https://api.hetzner.cloud/v1"))
    parser.add_argument("--fixture-file", default="")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-delete", action="store_true")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument("--output", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = load_json_file(args.plan_file)
    token_groups = load_token_groups(args)
    fixture = load_json_file(args.fixture_file) if args.fixture_file else None
    result = apply_dns_plan(
        plan=plan,
        token_groups=token_groups,
        api_endpoint=args.api_endpoint,
        apply=args.apply,
        allow_delete=args.allow_delete,
        fixture=fixture,
    )

    if args.format == "json":
        output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    else:
        lines = [
            f"apply={str(result['apply']).lower()}",
            f"allow_delete={str(result['allow_delete']).lower()}",
        ]
        for key, value in result["summary"].items():
            lines.append(f"{key}={value}")
        for action in result["actions"]:
            lines.append(
                f"{action['result']} {action['zone']} {action['name']} {action['type']}"
            )
        output = "\n".join(lines) + "\n"

    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 1 if result["summary"]["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
