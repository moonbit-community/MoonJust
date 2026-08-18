#!/usr/bin/env python3
"""Measure release artifacts and enforce frozen executable/archive budgets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import struct
import subprocess
from pathlib import Path


SCHEMA_VERSION = 2
SUPPORTED_BASELINE_SCHEMAS = {1, 2}
DEFAULT_HARD_LIMIT = 1.05
DEFAULT_ENGINEERING_TARGET = 1.00


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def detected_platform() -> str:
    systems = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}
    machines = {
        "x86_64": "x86_64",
        "AMD64": "x86_64",
        "arm64": "aarch64",
        "aarch64": "aarch64",
    }
    system = systems.get(platform.system())
    machine = machines.get(platform.machine())
    if system is None or machine is None:
        raise ValueError(
            f"unsupported artifact-size platform: {platform.system()}-{platform.machine()}"
        )
    return f"{system}-{machine}"


def read_uleb(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte & 0x80 == 0:
            return value, offset
        shift += 7
        if shift > 63:
            break
    raise ValueError("invalid wasm unsigned LEB128")


def wasm_sections(data: bytes) -> list[dict[str, object]]:
    if not data.startswith(b"\0asm\x01\0\0\0"):
        raise ValueError("artifact is not a wasm1 module")
    names = {
        1: "type",
        2: "import",
        3: "function",
        4: "table",
        5: "memory",
        6: "global",
        7: "export",
        8: "start",
        9: "element",
        10: "code",
        11: "data",
        12: "data-count",
    }
    offset = 8
    rows: list[dict[str, object]] = []
    index = 0
    while offset < len(data):
        section_id = data[offset]
        offset += 1
        payload_size, payload_offset = read_uleb(data, offset)
        end = payload_offset + payload_size
        if end > len(data):
            raise ValueError("wasm section extends beyond end of file")
        name = names.get(section_id, f"unknown-{section_id}")
        if section_id == 0:
            name_size, name_offset = read_uleb(data, payload_offset)
            name_end = name_offset + name_size
            if name_end > end:
                raise ValueError("wasm custom section name exceeds payload")
            name = "custom:" + data[name_offset:name_end].decode("utf-8", errors="replace")
        rows.append(
            {
                "index": index,
                "id": section_id,
                "name": name,
                "payload_bytes": payload_size,
                "encoded_bytes": end - (offset - 1),
            }
        )
        index += 1
        offset = end
    return rows


def elf_sections(data: bytes) -> list[dict[str, object]]:
    if not data.startswith(b"\x7fELF"):
        raise ValueError("artifact is not ELF")
    elf_class = data[4]
    endian = {1: "<", 2: ">"}.get(data[5])
    if endian is None or elf_class not in {1, 2}:
        raise ValueError("unsupported ELF class or byte order")
    header_format = endian + ("HHIIIIIHHHHHH" if elf_class == 1 else "HHIQQQIHHHHHH")
    fields = struct.unpack_from(header_format, data, 16)
    section_offset = fields[5]
    section_entry_size = fields[10]
    section_count = fields[11]
    names_index = fields[12]
    section_format = endian + ("IIIIIIIIII" if elf_class == 1 else "IIQQQQIIQQ")
    expected_size = struct.calcsize(section_format)
    if section_entry_size < expected_size or not 0 <= names_index < section_count:
        raise ValueError("invalid ELF section table")
    raw: list[tuple[int, int, int, int]] = []
    for index in range(section_count):
        row = struct.unpack_from(section_format, data, section_offset + index * section_entry_size)
        raw.append((row[0], row[1], row[4], row[5]))
    _, _, names_offset, names_size = raw[names_index]
    names = data[names_offset : names_offset + names_size]

    def section_name(offset: int) -> str:
        end = names.find(b"\0", offset)
        if end < 0:
            end = len(names)
        return names[offset:end].decode("utf-8", errors="replace")

    return [
        {
            "index": index,
            "name": section_name(name_offset),
            "type": section_type,
            "file_offset": file_offset,
            "bytes": size,
        }
        for index, (name_offset, section_type, file_offset, size) in enumerate(raw)
    ]


def macho_sections(data: bytes) -> list[dict[str, object]]:
    if len(data) < 32:
        raise ValueError("Mach-O artifact is truncated")
    little_magic = struct.unpack_from("<I", data)[0]
    big_magic = struct.unpack_from(">I", data)[0]
    if little_magic == 0xFEEDFACF:
        endian = "<"
    elif big_magic == 0xFEEDFACF:
        endian = ">"
    elif big_magic in {0xCAFEBABE, 0xCAFEBABF}:
        raise ValueError("fat Mach-O artifacts must be thinned before analysis")
    else:
        raise ValueError("artifact is not 64-bit Mach-O")
    _, _, _, _, command_count, command_bytes, _, _ = struct.unpack_from(
        endian + "IiiIIIII", data
    )
    offset = 32
    command_end = offset + command_bytes
    rows: list[dict[str, object]] = []
    for _ in range(command_count):
        command, size = struct.unpack_from(endian + "II", data, offset)
        if size < 8 or offset + size > command_end or offset + size > len(data):
            raise ValueError("invalid Mach-O load command")
        if command == 0x19:
            segment = struct.unpack_from(endian + "II16sQQQQiiII", data, offset)
            segment_name = segment[2].split(b"\0", 1)[0].decode(errors="replace")
            section_count = segment[9]
            section_offset = offset + 72
            for index in range(section_count):
                section = struct.unpack_from(
                    endian + "16s16sQQIIIIIIII", data, section_offset + index * 80
                )
                section_name = section[0].split(b"\0", 1)[0].decode(errors="replace")
                rows.append(
                    {
                        "index": len(rows),
                        "name": f"{segment_name},{section_name}",
                        "file_offset": section[4],
                        "bytes": section[3],
                    }
                )
        offset += size
    return rows


def pe_sections(data: bytes) -> list[dict[str, object]]:
    if not data.startswith(b"MZ") or len(data) < 0x40:
        raise ValueError("artifact is not PE/COFF")
    header_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if data[header_offset : header_offset + 4] != b"PE\0\0":
        raise ValueError("PE signature is missing")
    _, section_count, _, _, _, optional_size, _ = struct.unpack_from(
        "<HHIIIHH", data, header_offset + 4
    )
    offset = header_offset + 24 + optional_size
    rows: list[dict[str, object]] = []
    for index in range(section_count):
        section = struct.unpack_from("<8sIIIIIIHHI", data, offset + index * 40)
        rows.append(
            {
                "index": index,
                "name": section[0].split(b"\0", 1)[0].decode(errors="replace"),
                "virtual_bytes": section[1],
                "file_offset": section[4],
                "bytes": section[3],
            }
        )
    return rows


def analyze_sections(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if data.startswith(b"\0asm"):
        kind = "wasm1"
        sections = wasm_sections(data)
    elif data.startswith(b"\x7fELF"):
        kind = "elf"
        sections = elf_sections(data)
    elif data.startswith(b"MZ"):
        kind = "pe"
        sections = pe_sections(data)
    else:
        kind = "mach-o"
        sections = macho_sections(data)
    return {"format": kind, "sections": sections}


def top_elf_symbols(path: Path, limit: int = 50) -> list[dict[str, object]]:
    nm = shutil.which("nm")
    if nm is None or not path.read_bytes()[:4] == b"\x7fELF":
        return []
    result = subprocess.run(
        [nm, "-S", "--size-sort", "--radix=d", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    rows: list[dict[str, object]] = []
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=3)
        if len(parts) != 4 or not parts[1].isdigit():
            continue
        rows.append({"bytes": int(parts[1]), "type": parts[2], "name": parts[3]})
    return list(reversed(rows[-limit:]))


def artifact_record(path: Path, analyze: bool = False) -> dict[str, object]:
    record: dict[str, object] = {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }
    if analyze:
        record.update(analyze_sections(path))
        symbols = top_elf_symbols(path)
        if symbols:
            record["top_symbols"] = symbols
    return record


def section_size(section: dict[str, object]) -> int:
    for key in ("bytes", "encoded_bytes", "payload_bytes"):
        value = section.get(key)
        if isinstance(value, int):
            return value
    return 0


def section_diff(
    current: object,
    frozen: object,
) -> list[dict[str, object]] | None:
    if not isinstance(current, list) or not isinstance(frozen, list):
        return None
    rows: list[dict[str, object]] = []
    for index in range(max(len(current), len(frozen))):
        current_row = current[index] if index < len(current) else {}
        frozen_row = frozen[index] if index < len(frozen) else {}
        if not isinstance(current_row, dict) or not isinstance(frozen_row, dict):
            continue
        old = section_size(frozen_row)
        new = section_size(current_row)
        delta = new - old
        ratio = delta / old if old else (1.0 if delta else 0.0)
        rows.append(
            {
                "index": index,
                "name": current_row.get("name", frozen_row.get("name")),
                "baseline_bytes": old,
                "bytes": new,
                "delta_bytes": delta,
                "delta_ratio": ratio,
                "requires_review": delta > 64 * 1024 or ratio > 0.05,
            }
        )
    return rows


def attach_section_evidence(
    record: dict[str, object],
    baseline: object,
    name: str,
    failures: list[str],
) -> None:
    if not isinstance(baseline, dict):
        return
    diff = section_diff(record.get("sections"), baseline.get("sections"))
    if diff is None:
        return
    record["section_diff"] = diff
    reviewed = [row for row in diff if row.get("requires_review")]
    if reviewed:
        failures.append(
            f"{name} has unapproved section growth: "
            + ", ".join(str(row.get("name")) for row in reviewed)
        )


def command_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return (result.stdout + result.stderr).strip()


def baseline_bytes(entry: dict[str, object], archive: bool = False) -> int | None:
    key = "archive_bytes" if archive else "bytes"
    value = entry.get(key)
    return value if isinstance(value, int) and value > 0 else None


def apply_budget(
    name: str,
    record: dict[str, object],
    frozen_bytes: int,
    hard_limit: float,
    target: float,
    failures: list[str],
) -> None:
    record["baseline_bytes"] = frozen_bytes
    ratio = int(record["bytes"]) / frozen_bytes
    record["ratio"] = ratio
    record["hard_limit_ratio"] = hard_limit
    record["engineering_target_ratio"] = target
    record["within_engineering_target"] = ratio <= target
    if ratio > hard_limit:
        failures.append(f"{name} grew {(ratio - 1) * 100:.2f}% from frozen baseline")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--native-debug", type=Path)
    parser.add_argument("--wasm-debug", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--platform", default=detected_platform())
    parser.add_argument("--source-commit")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-complete-baseline", action="store_true")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    if baseline.get("schema_version") not in SUPPORTED_BASELINE_SCHEMAS:
        raise ValueError("unsupported artifact-size baseline schema")
    native_baseline = baseline.get("native", {}).get(args.platform)
    wasm_baseline = baseline.get("wasm1")
    if not isinstance(wasm_baseline, dict):
        raise ValueError("frozen wasm1 artifact baseline is missing")
    paths = [args.native, args.wasm, args.native_debug, args.wasm_debug, args.archive]
    for path in (path for path in paths if path is not None):
        if not path.is_file():
            raise ValueError(f"release artifact is missing: {path}")

    hard_limit = float(baseline.get("hard_limit_ratio", DEFAULT_HARD_LIMIT))
    target = float(baseline.get("engineering_target_ratio", DEFAULT_ENGINEERING_TARGET))
    failures: list[str] = []
    missing: list[str] = []
    record: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "commit": args.source_commit or command_output(["git", "rev-parse", "HEAD"]),
        "platform": args.platform,
        "baseline_commit": baseline["commit"],
        "moon": command_output(["moon", "version", "--all"]),
        "machine": {
            "platform": platform.platform(),
            "system": platform.system(),
            "machine": platform.machine(),
            "python": platform.python_version(),
            "builder_id": os.environ.get("MOONJUST_BUILDER_ID"),
        },
        "hard_limit_ratio": hard_limit,
        "engineering_target_ratio": target,
        "native": artifact_record(args.native, analyze=True),
        "wasm1": artifact_record(args.wasm, analyze=True),
    }
    if not isinstance(native_baseline, dict):
        missing.append(f"native/{args.platform}")
    else:
        frozen = baseline_bytes(native_baseline)
        if frozen is None:
            missing.append(f"native/{args.platform}/bytes")
        else:
            apply_budget("native", record["native"], frozen, hard_limit, target, failures)  # type: ignore[arg-type]
            attach_section_evidence(record["native"], native_baseline, "native", failures)  # type: ignore[arg-type]
    frozen_wasm = baseline_bytes(wasm_baseline)
    if frozen_wasm is None:
        missing.append("wasm1/bytes")
    else:
        apply_budget("wasm1", record["wasm1"], frozen_wasm, hard_limit, target, failures)  # type: ignore[arg-type]
        attach_section_evidence(record["wasm1"], wasm_baseline, "wasm1", failures)  # type: ignore[arg-type]

    if args.archive is not None:
        archive_record = artifact_record(args.archive)
        record["archive"] = archive_record
        archive_frozen = baseline_bytes(native_baseline, archive=True) if isinstance(native_baseline, dict) else None
        if archive_frozen is None:
            missing.append(f"archive/{args.platform}/bytes")
        else:
            apply_budget("archive", archive_record, archive_frozen, hard_limit, target, failures)
    if args.native_debug is not None:
        record["native_debug"] = artifact_record(args.native_debug, analyze=True)
    if args.wasm_debug is not None:
        record["wasm1_debug"] = artifact_record(args.wasm_debug, analyze=True)
    if args.require_complete_baseline and missing:
        failures.append("frozen artifact baseline is incomplete: " + ", ".join(missing))
    record["missing_baselines"] = missing
    record["status"] = "failed" if failures else ("incomplete-baseline" if missing else "passed")
    record["failures"] = failures
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    if failures and not args.report_only:
        raise ValueError("; ".join(failures))
    ratios = [
        f"{name}={values['ratio']:.3f}x"
        for name, values in record.items()
        if isinstance(values, dict) and "ratio" in values
    ]
    print("artifact size report: " + " ".join(ratios))
    if missing:
        print("artifact size baseline incomplete: " + ", ".join(missing))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError, struct.error) as error:
        raise SystemExit(f"artifact size gate error: {error}")
