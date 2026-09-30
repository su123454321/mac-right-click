from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parent
app = root / "Build/右键小工具.app"
if not (app / "Contents/MacOS/RightClickTools").is_file():
    raise SystemExit("请先运行 python3 build.py")
out = root / "dist"
out.mkdir(exist_ok=True)
app_archive = out / "右键小工具.app.zip"
with zipfile.ZipFile(app_archive, "w", zipfile.ZIP_DEFLATED) as z:
    for path in sorted(app.rglob("*")):
        if path.is_file() and path.name != ".DS_Store" and not path.name.startswith("._"):
            z.write(path, str(Path(app.name) / path.relative_to(app)))
release = out / "mac-right-click-v2.1-macos-arm64.zip"
with zipfile.ZipFile(release, "w", zipfile.ZIP_DEFLATED) as z:
    for path, name in [(app_archive, "右键小工具.app.zip"),
                       (root / "install.command", "安装或更新.command"),
                       (root / "INSTALL.txt", "安装说明.txt"),
                       (root / "THIRD_PARTY_NOTICES.txt", "THIRD_PARTY_NOTICES.txt")]:
        info = zipfile.ZipInfo.from_file(path, "RightClickTools-2.1/" + name)
        if name.endswith(".command"):
            info.external_attr = (0o100755 << 16)
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, path.read_bytes())
checksum = hashlib.sha256(release.read_bytes()).hexdigest()
(out / "SHA256SUMS.txt").write_text(checksum + "  " + release.name + "\n", encoding="utf-8")
print(release)
