#!/usr/bin/env python3
"""Exercise the CMake download targets with real dmf-get and local packages."""
import argparse
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]


def run(*args, env=None, success=True):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env)
    if (result.returncode == 0) != success:
        raise AssertionError(result.stdout)
    return result.stdout


def check_layout(dmf_get, explicit_manifest):
    with tempfile.TemporaryDirectory(prefix="dmboot layout ") as tmp:
        root = Path(tmp)
        source, build = root / "source", root / "build"
        (source / "modules").mkdir(parents=True)
        (source / "scripts").mkdir()
        (source / "configs/common/services").mkdir(parents=True)
        shutil.copy(REPO / "modules/CMakeLists.txt", source / "modules")
        # The unit that mounts /tmp comes with the sources of the firmware, not with a package
        shutil.copy(REPO / "configs/common/services/tmp.ini", source / "configs/common/services")
        shutil.copy(REPO / "scripts/module_output.cmake", source / "scripts")
        manifest = root / "manifest.dmm"
        entries = []
        for kind in ("flash", "sdcard"):
            module = kind + "mod"
            archive = root / (module + ".zip")
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr(module + ".dmfc", "fixture binary")
                package.writestr(module + ".dmd", "# No dependencies\n")
                package.writestr("LICENSE", module + " license\n")
                package.writestr("configs/fixture.ini", module + " config\n")
                package.writestr("views/main.dmv", module + " view\n")
                package.writestr(module + ".dmr", "\n".join((
                    "dmfc=./${module}.dmfc => ${destination}/${module}.dmfc",
                    "dmd=./${module}.dmd => ${destination}/${module}.dmd",
                    "license=./LICENSE => ${destination}/${module}/LICENSE",
                    "config=./configs => ${destination}/${module}/configs",
                    "views=./views => ${views_dir}",
                )))
            entries.append(f"{module} {archive}\n")
            (source / f"configs/common/{kind}.dmd").write_text(
                f"{module} driver=fixture.ini\n")
        manifest.write_text("".join(entries))
        (source / "CMakeLists.txt").write_text('''cmake_minimum_required(VERSION 3.10)
project(layout NONE)
set(DMBOOT_CONFIG_DIR "${CMAKE_BINARY_DIR}/cfg")
set(DMBOOT_EVIEWS_DIR "${CMAKE_BINARY_DIR}/eviews")
set(DMBOOT_LICENSE_DIR "${CMAKE_BINARY_DIR}/lic")
set(DMBOOT_MAIN_MODULE "flashmod")
set(DMBOOT_MODULE_TYPE "dmfc")
add_subdirectory(modules)
''')
        env = os.environ.copy()
        env["DMOD_CACHE_DIR"] = str(root / "cache")
        env["DMOD_MANIFEST"] = str(manifest)
        for name in ("DMOD_TOOLS_NAME", "DMOD_LICENSE_DIR", "DMOD_PACKAGE_DIR", "DMOD_VIEWS_DIR"):
            env.pop(name, None)
        # The fixture payload tests installation paths, not binary decoding.
        # Run the actual downloader with architecture checks disabled for fixtures.
        wrapper = root / "dmf-get-fixtures"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(str(dmf_get)) +
                           ' --skip-arch-check --skip-dmod-ver-check --no-fallback "$@"\n')
        wrapper.chmod(0o755)
        args = ["cmake", "-S", str(source), "-B", str(build), f"-DDMF_GET={wrapper}"]
        if explicit_manifest:
            args.append(f"-DDMBOOT_MANIFEST_URL={manifest}")
        run(*args, env=env)
        # Simulate an earlier installation, including hidden download stamps.
        for path in (build / "dmf", build / "sdcard/bin"):
            path.mkdir(parents=True, exist_ok=True)
            (path / "old-package").mkdir()
            (path / "old-package/README").write_text("preserve me")
            (path / ".download_complete").touch()
        run("cmake", "--build", str(build), "--target", "download_modules",
            "download_sdcard_modules", env=env)
        # The configuration goes where the module goes: the firmware's /cfg, the card's cfg/
        for kind, binary_dir, license_dir, views_dir, config_dir in (
            ("flash", build / "dmf", build / "lic", build / "eviews", build / "cfg"),
            ("sdcard", build / "sdcard/bin", build / "sdcard/lic", build / "sdcard/views", build / "sdcard/cfg"),
        ):
            module = kind + "mod"
            assert {p.name for p in binary_dir.iterdir()} == {module + ".dmfc"}
            assert (license_dir / module / "LICENSE").read_text() == module + " license\n"
            assert (views_dir / module / "main.dmv").is_file()
            assert (config_dir / f"drivers/{module}/fixture.ini").is_file()
            packages = build / "packages" / kind
            assert (packages / f"{module}.dmd").is_file()
            assert (packages / f"{module}.dmr").is_file()
            assert (packages / "legacy-output/old-package/README").read_text() == "preserve me"
            assert (packages / "legacy-output/.download_complete").is_file()
            assert (build / f"modules/{kind}.download_complete").is_file()
        assert {p.name for p in (build / "sdcard").iterdir()} == {"bin", "cfg", "lic", "views"}
        assert not (build / "cfg/drivers/sdcardmod").exists()
        # Validation rejects stray resources, and migration never overwrites a backup.
        (build / "dmf/unexpected.txt").write_text("stray file")
        script = str(source / "scripts/module_output.cmake")
        run("cmake", f"-DMODULE_DIR={build / 'dmf'}", "-DCHECK_ONLY=ON", "-P", script, success=False)
        (build / "packages/flash/legacy-output/unexpected.txt").write_text("backup")
        run("cmake", f"-DMODULE_DIR={build / 'dmf'}", f"-DPACKAGE_DIR={build / 'packages/flash'}",
            "-P", script, success=False)
        assert (build / "dmf/unexpected.txt").read_text() == "stray file"
        assert (build / "packages/flash/legacy-output/unexpected.txt").read_text() == "backup"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dmf-get", required=True, type=Path)
    args = parser.parse_args()
    for explicit_manifest in (True, False):
        check_layout(args.dmf_get.resolve(), explicit_manifest)
    print("Module layout tests passed (explicit and default manifests).")
