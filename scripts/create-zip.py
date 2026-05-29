#!/usr/bin/env python3
"""Create a ZIP archive of a macOS .app bundle with proper Unicode handling."""
import zipfile
import os
import sys

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
    
    # Get just the app name (e.g., "租车总成本比较.app")
    app_name = os.path.basename(app_path)
    parent_dir = os.path.dirname(app_path)
    
    count = 0
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for root, dirs, files in os.walk(app_path):
            for f in files:
                full_path = os.path.join(root, f)
                arcname = os.path.relpath(full_path, parent_dir)
                zf.write(full_path, arcname)
                count += 1
    
    size = os.path.getsize(output_path)
    print(f"Created {output_path} ({count} files, {size} bytes)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <app_bundle_path> <output_zip_path>", file=sys.stderr)
        sys.exit(1)
    create_zip(sys.argv[1], sys.argv[2])
