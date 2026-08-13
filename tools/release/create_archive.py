#!/usr/bin/env python3
import argparse
import gzip
import io
import pathlib
import tarfile
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    files = sorted(path for path in source.rglob("*") if path.is_file())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.suffix == ".zip":
        with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                info = zipfile.ZipInfo(path.relative_to(source).as_posix())
                info.date_time = (1980, 1, 1, 0, 0, 0)
                mode = 0o755 if path.name in {"just", "just.exe"} else 0o644
                info.external_attr = mode << 16
                archive.writestr(info, path.read_bytes())
    else:
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for path in files:
                info = archive.gettarinfo(str(path), path.relative_to(source).as_posix())
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = "root"
                info.gname = "root"
                info.mode = 0o755 if path.name == "just" else 0o644
                with path.open("rb") as stream:
                    archive.addfile(info, stream)
        with args.output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                compressed.write(buffer.getvalue())


if __name__ == "__main__":
    main()
