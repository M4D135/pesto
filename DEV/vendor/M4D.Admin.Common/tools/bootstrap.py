"""Fetch the pinned Microsoft reference pack for explicit development builds only."""
import base64
import hashlib
import pathlib
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
URL = "https://api.nuget.org/v3-flatcontainer/microsoft.netframework.referenceassemblies.net472/1.0.3/microsoft.netframework.referenceassemblies.net472.1.0.3.nupkg"
# SHA512 published in NuGet's Microsoft package catalog (version 1.0.3).
SHA512 = "PvZKpFbtsxtJBi6hJyzt/iaK71qGdu9mNVpJT43+i1Wp23ym57YVuQI+BEnO/99K2pxPMEgYtz62n7yZFEgi2A=="
PREFIX = "build/.NETFramework/v4.7.2/"


def main():
    cache = ROOT / ".build"
    cache.mkdir(exist_ok=True)
    package = cache / "net472-1.0.3.nupkg"
    if not package.exists():
        with urllib.request.urlopen(URL, timeout=60) as response:
            data = response.read(30 * 1024 * 1024)
        if base64.b64encode(hashlib.sha512(data).digest()).decode() != SHA512:
            raise ValueError("Microsoft reference pack SHA512 mismatch")
        package.write_bytes(data)
    if base64.b64encode(hashlib.sha512(package.read_bytes()).digest()).decode() != SHA512:
        raise ValueError("Cached reference pack SHA512 mismatch")
    target = cache / "net472"
    target.mkdir(exist_ok=True)
    count = 0
    with zipfile.ZipFile(package) as archive:
        for entry in archive.infolist():
            if not entry.filename.startswith(PREFIX) or not entry.filename.endswith(".dll"):
                continue
            relative = pathlib.PurePosixPath(entry.filename[len(PREFIX):])
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Unsafe reference pack member")
            output = target.joinpath(*relative.parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(archive.read(entry))
            count += 1
    if not (target / "mscorlib.dll").is_file():
        raise ValueError("Reference pack has no mscorlib")
    print(f"Microsoft .NET 4.7.2 references verified: {count} assemblies in {target}")


if __name__ == "__main__":
    main()
