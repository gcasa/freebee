#!/bin/sh

set -eu

usage() {
	cat <<'EOF'
Usage: scripts/create-macos-app.sh [options]

Create a macOS FreeBee.app wrapper around the FreeBee executable.

Options:
  --executable PATH  Executable to bundle (default: project-root/freebee)
  --data-dir PATH    Directory containing .freebee.toml, ROMs, and disks
                     (default: current directory)
  --disk-image PATH  Default writable hard-disk seed (.img or .zip)
                     (default: project-root/3b1-hd.zip, then hd.img)
  --no-disk-image    Build without a bundled hard-disk seed
  --output PATH      App bundle to create (default: project-root/FreeBee.app)
  --force            Replace an existing bundle at the output path
  --no-sign          Do not ad-hoc sign the finished bundle
  -h, --help         Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")
executable="$project_dir/freebee"
data_dir=$(pwd)
output="$project_dir/FreeBee.app"
if [ -f "$project_dir/3b1-hd.zip" ]; then
	disk_image="$project_dir/3b1-hd.zip"
else
	disk_image="$project_dir/hd.img"
fi
force=0
sign=1

while [ "$#" -gt 0 ]; do
	case "$1" in
		--executable)
			[ "$#" -ge 2 ] || { echo "Missing value for --executable" >&2; exit 2; }
			executable=$2
			shift 2
			;;
		--data-dir)
			[ "$#" -ge 2 ] || { echo "Missing value for --data-dir" >&2; exit 2; }
			data_dir=$2
			shift 2
			;;
		--output)
			[ "$#" -ge 2 ] || { echo "Missing value for --output" >&2; exit 2; }
			output=$2
			shift 2
			;;
		--disk-image)
			[ "$#" -ge 2 ] || { echo "Missing value for --disk-image" >&2; exit 2; }
			disk_image=$2
			shift 2
			;;
		--no-disk-image)
			disk_image=
			shift
			;;
		--force)
			force=1
			shift
			;;
		--no-sign)
			sign=0
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This script must be run on macOS." >&2; exit 1; }
[ -f "$executable" ] && [ -x "$executable" ] || {
	echo "FreeBee executable not found or not executable: $executable" >&2
	echo "Build it first with 'make'." >&2
	exit 1
}
[ -d "$data_dir" ] || { echo "Data directory not found: $data_dir" >&2; exit 1; }
if [ -n "$disk_image" ] && [ ! -f "$disk_image" ]; then
	echo "Hard-disk seed not found: $disk_image" >&2
	exit 1
fi

executable=$(CDPATH= cd -- "$(dirname -- "$executable")" && printf '%s/%s\n' "$(pwd)" "$(basename -- "$executable")")
data_dir=$(CDPATH= cd -- "$data_dir" && pwd)
output_parent=$(dirname -- "$output")
mkdir -p "$output_parent"
output_parent=$(CDPATH= cd -- "$output_parent" && pwd)
output="$output_parent/$(basename -- "$output")"

if [ -e "$output" ]; then
	if [ "$force" -ne 1 ]; then
		echo "Output already exists: $output (use --force to replace it)" >&2
		exit 1
	fi
	rm -rf -- "$output"
fi

staging=$(mktemp -d "${TMPDIR:-/tmp}/freebee-app.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT HUP INT TERM
app="$staging/FreeBee.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"

cp "$executable" "$contents/Resources/freebee"
chmod 755 "$contents/Resources/freebee"
cp "$project_dir/assets/macos/freebee.icns" "$contents/Resources/freebee.icns"
printf '%s\n' "$data_dir" > "$contents/Resources/data-directory"
if [ -n "$disk_image" ]; then
	case "$disk_image" in
		*.zip) cp "$disk_image" "$contents/Resources/default-hd.zip" ;;
		*) cp "$disk_image" "$contents/Resources/default-hd.img" ;;
	esac
fi

cat > "$contents/MacOS/FreeBee" <<'EOF'
#!/bin/sh
set -eu
contents=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
data_dir=$(sed -n '1p' "$contents/Resources/data-directory")
support_dir="$HOME/Library/Application Support/FreeBee"
working_disk="$support_dir/hd.img"
mkdir -p "$support_dir"

# Never run against the signed, read-only seed in the app bundle. Install a
# private writable copy once, using a temporary path so interruption cannot
# leave a partial root disk behind.
if [ ! -f "$working_disk" ]; then
	tmp_dir=$(mktemp -d "$support_dir/.install.XXXXXX")
	trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM
	if [ -f "$contents/Resources/default-hd.zip" ]; then
		/usr/bin/ditto -x -k "$contents/Resources/default-hd.zip" "$tmp_dir"
		seed=$(find "$tmp_dir" -type f -name '*.img' -print -quit)
		[ -n "$seed" ] || { echo "Bundled disk archive contains no .img file" >&2; exit 1; }
		mv "$seed" "$working_disk"
	elif [ -f "$contents/Resources/default-hd.img" ]; then
		cp "$contents/Resources/default-hd.img" "$tmp_dir/hd.img"
		mv "$tmp_dir/hd.img" "$working_disk"
	fi
	rm -rf -- "$tmp_dir"
	trap - EXIT HUP INT TERM
fi

if [ -f "$working_disk" ]; then
	export FREEBEE_DEFAULT_HD="$working_disk"
fi
cd "$data_dir"
exec "$contents/Resources/freebee" "$@"
EOF
chmod 755 "$contents/MacOS/FreeBee"

cat > "$contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>FreeBee</string>
	<key>CFBundleExecutable</key><string>FreeBee</string>
	<key>CFBundleIconFile</key><string>freebee</string>
	<key>CFBundleIdentifier</key><string>org.philpem.freebee</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>FreeBee</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>10.13</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

if command -v plutil >/dev/null 2>&1; then
	plutil -lint "$contents/Info.plist" >/dev/null
fi
if [ "$sign" -eq 1 ] && command -v codesign >/dev/null 2>&1; then
	codesign --force --deep --sign - "$app" >/dev/null
fi

mv "$app" "$output"
echo "Created $output"
echo "FreeBee data directory: $data_dir"
if [ -n "$disk_image" ]; then
	echo "Bundled hard-disk seed: $disk_image"
fi
