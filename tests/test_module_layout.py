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


def check_layout(dmf_get, explicit_manifest, screen_variants=False):
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
        for kind in ("flash", "sdcard", "ext"):
            module = kind + "mod"
            archive = root / (module + ".zip")
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr(module + ".dmfc", "fixture binary")
                package.writestr(module + ".dmd", "# No dependencies\n")
                package.writestr("LICENSE", module + " license\n")
                package.writestr("configs/fixture.ini", module + " config\n")
                if screen_variants:
                    for screen in ("480x272", "320x240", "epaper-mono"):
                        package.writestr(f"views/{screen}/main.dmv", module + " " + screen)
                        package.writestr(f"views/{screen}/{screen}.dmvf", "font " + screen)
                else:
                    package.writestr("views/main.dmv", module + " view\n")
                package.writestr(module + ".dmr", "\n".join((
                    "dmfc=./${module}.dmfc => ${destination}/${module}.dmfc",
                    "dmd=./${module}.dmd => ${destination}/${module}.dmd",
                    "license=./LICENSE => ${destination}/${module}/LICENSE",
                    "config=./configs => ${destination}/${module}/configs",
                    ("views=./views/480x272 => ${views_dir} [screen=480x272] [default=true]\n"
                     "views=./views/320x240 => ${views_dir} [screen=320x240]\n"
                     "views=./views/epaper-mono => ${views_dir} [screen=epaper-mono]" if screen_variants else
                     "views=./views => ${views_dir}"),
                )))
            entries.append(f"{module} {archive}\n")
            (source / f"configs/common/{kind}.dmd").write_text(
                f"{module} driver=fixture.ini" +
                (" @screen 480x272" if screen_variants and kind == "sdcard" else "") + "\n")
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
        for name in ("DMOD_TOOLS_NAME", "DMOD_LICENSE_DIR", "DMOD_PACKAGE_DIR", "DMOD_VIEWS_DIR", "DMOD_SCREEN"):
            env.pop(name, None)
        # The fixture payload tests installation paths, not binary decoding.
        # Run the actual downloader with architecture checks disabled for fixtures.
        wrapper = root / "dmf-get-fixtures"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(str(dmf_get)) +
                           ' --skip-arch-check --skip-dmod-ver-check --no-fallback "$@"\n')
        wrapper.chmod(0o755)
        args = ["cmake", "-S", str(source), "-B", str(build), f"-DDMF_GET={wrapper}"]
        if screen_variants:
            args.append("-DDMBOOT_SCREEN=epaper-mono")
        if explicit_manifest:
            args.append(f"-DDMBOOT_MANIFEST_URL={manifest}")
        run(*args, env=env)
        # Simulate an earlier installation, including hidden download stamps.
        for path in (build / "dmf", build / "sdcard/bin", build / "ext/bin"):
            path.mkdir(parents=True, exist_ok=True)
            (path / "old-package").mkdir()
            (path / "old-package/README").write_text("preserve me")
            (path / ".download_complete").touch()
        run("cmake", "--build", str(build), "--target", "download_modules",
            "download_sdcard_modules", "download_ext_modules", env=env)
        # The configuration goes where the module goes: the firmware's /cfg, the card's cfg/
        for kind, binary_dir, license_dir, views_dir, config_dir in (
            ("flash", build / "dmf", build / "lic", build / "eviews", build / "cfg"),
            ("sdcard", build / "sdcard/bin", build / "sdcard/lic", build / "sdcard/views", build / "sdcard/cfg"),
            ("ext", build / "ext/bin", build / "ext/lic", build / "ext/views", build / "ext/cfg"),
        ):
            module = kind + "mod"
            assert {p.name for p in binary_dir.iterdir()} == {module + ".dmfc"}
            assert (license_dir / module / "LICENSE").read_text() == module + " license\n"
            assert (views_dir / module / "main.dmv").is_file()
            if screen_variants:
                selected = "480x272" if kind == "sdcard" else "epaper-mono"
                assert (views_dir / module / "main.dmv").read_text() == module + " " + selected
                assert {p.name for p in (views_dir / module).iterdir()} == {"main.dmv", selected + ".dmvf"}
            assert (config_dir / f"drivers/{module}/fixture.ini").is_file()
            packages = build / "packages" / kind
            assert (packages / f"{module}.dmd").is_file()
            assert (packages / f"{module}.dmr").is_file()
            assert (packages / "legacy-output/old-package/README").read_text() == "preserve me"
            assert (packages / "legacy-output/.download_complete").is_file()
            assert (build / f"modules/{kind}.download_complete").is_file()
        assert {p.name for p in (build / "sdcard").iterdir()} == {"bin", "cfg", "lic", "views"}
        assert not (build / "cfg/drivers/sdcardmod").exists()
        if screen_variants:
            # Only changing the CMake selection must invalidate all download markers.
            args = [a for a in args if not a.startswith("-DDMBOOT_SCREEN=")]
            run(*args, "-DDMBOOT_SCREEN=480x272", env=env)
            run("cmake", "--build", str(build), "--target", "download_modules",
                "download_sdcard_modules", "download_ext_modules", env=env)
            for kind, views in (("flash", build / "eviews"), ("sdcard", build / "sdcard/views"),
                                ("ext", build / "ext/views")):
                module = kind + "mod"
                assert (views / module / "main.dmv").read_text() == module + " 480x272"
                assert not (views / module / "320x240.dmvf").exists()
                assert not (views / module / "epaper-mono.dmvf").exists()
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
        for screen_variants in (False, True):
            check_layout(args.dmf_get.resolve(), explicit_manifest, screen_variants)
    print("Module layout tests passed (legacy and screen variants, explicit/default manifests, all storage targets).")
