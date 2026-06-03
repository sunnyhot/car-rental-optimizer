#!/usr/bin/env python3
import os
import shutil
import sys
import zipfile


SYMLINK_MODE = 0o120777 << 16
FILE_MODE = 0o100644 << 16
EXECUTABLE_MODE = 0o100755 << 16
DIRECTORY_MODE = 0o040755 << 16

def create_zip(app_path, output_path):
    """Create a ZIP archive from an .app bundle."""
    print(f"Source: {app_path}")
    print(f"Source exists: {os.path.exists(app_path)}")
    print(f"Source is dir: {os.path.isdir(app_path)}")
    print(f"CWD: {os.getcwd()}")
    
    if not os.path.isdir(app_path):
        # Try listing build/ to help debug
        build_dir = os.path.dirname(app_path)
        if os.path.isdir(build_dir):
            print(f"Contents of {build_dir}:")
            for item in os.listdir(build_dir):
                print(f"  - {item}")
        print(f"ERROR: Source directory not found: {app_path}", file=sys.stderr)
        sys.exit(1)

    if shutil.which("ditto"):
        create_zip_with_ditto(app_path, output_path)
        return

    create_zip_with_python(app_path, output_path)


def create_zip_with_ditto(app_path, output_path):
    """Use macOS ditto so framework symlinks and metadata survive extraction."""
    import subprocess

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    subprocess.run(
        ["ditto", "-c", "-k", "--keepParent", app_path, output_path],
        check=True
    )

    size = os.path.getsize(output_path)
    print(f"Created {output_path} with ditto ({size} bytes)")


def create_zip_with_python(app_path, output_path):
    """Portable ZIP fallback that preserves symlink entries."""
    # Get just the app name (e.g., "租车比价助手.app")
    app_name = os.path.basename(app_path)
    parent_dir = os.path.dirname(app_path)

    count = 0
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for root, dirs, files in os.walk(app_path, followlinks=False):
            arc_root = os.path.relpath(root, parent_dir)
            directory_info = zipfile.ZipInfo(f"{arc_root}/")
            directory_info.external_attr = DIRECTORY_MODE
            zf.writestr(directory_info, b"")

            for name in dirs + files:
                full_path = os.path.join(root, name)
                arcname = os.path.relpath(full_path, parent_dir)
                if os.path.islink(full_path):
                    info = zipfile.ZipInfo(arcname)
                    info.external_attr = SYMLINK_MODE
                    zf.writestr(info, os.readlink(full_path).encode("utf-8"))
                else:
                    info = zipfile.ZipInfo.from_file(full_path, arcname)
                    if os.access(full_path, os.X_OK):
                        info.external_attr = EXECUTABLE_MODE
                    elif os.path.isfile(full_path):
                        info.external_attr = FILE_MODE
                    with open(full_path, "rb") as file:
                        zf.writestr(info, file.read(), compress_type=zipfile.ZIP_DEFLATED)
                count += 1

    size = os.path.getsize(output_path)
    print(f"Created {output_path} ({count} files, {size} bytes)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <app_bundle_path> <output_zip_path>", file=sys.stderr)
        sys.exit(1)
    create_zip(sys.argv[1], sys.argv[2])
