 #!/usr/bin/bash

set -euo pipefail

MODE="single"          # single | playlist | auto
SANITIZE="auto"        # auto | on | off
OUTDIR="Musik"
AUDIO_FORMAT="mp3"
AUDIO_QUALITY="0"

usage() {
  cat <<'EOF'
Usage:
  youtube-to-mp3.sh [--mode single|playlist|auto] [--sanitize auto|on|off] [--out DIR] <URL|FILE>

Examples:
  # single video (forces no-playlist)
  ./youtube-to-mp3.sh --mode single "https://www.youtube.com/watch?v=QZF0EEsUkzs&list=RDQZF0EEsUkzs&start_radio=1"

  # playlist
  ./youtube-to-mp3.sh --mode playlist "https://www.youtube.com/playlist?list=PLxxxx"

  # batch file (one URL per line, comments allowed)
  ./youtube-to-mp3.sh --mode single urls.txt

Notes:
  - sanitize= 'activated' or 'auto' will strip playlist/radio params out, so only a single song like within mode=single will be downloaded.
  - All quote URLs containing '&' or your shell will treat '&' as background operator.
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

sanitize_url() {
  local url="$1"

  # Strip CR if file has Windows line endings
  url="${url%$'\r'}"

  # For single-video downloads, remove playlist/radio context that confuses yt-dlp
  # Examples removed: &list=..., ?list=..., &start_radio=..., &index=...
  # Simple and effective: cut at list= if present.
  if [[ "$url" == *"&list="* ]]; then
    url="${url%%&list=*}"
  elif [[ "$url" == *"?list="* ]]; then
    url="${url%%\?list=*}"
  fi

  # Also remove a trailing &start_radio=... if someone has a weird URL without list=
  if [[ "$url" == *"&start_radio="* ]]; then
    url="${url%%&start_radio=*}"
  fi

  echo "$url"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

# -------- argument parsing --------
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode needs a value"
      MODE="$2"; shift 2;;
    --sanitize)
      [[ $# -ge 2 ]] || die "--sanitize needs a value"
      SANITIZE="$2"; shift 2;;
    --out)
      [[ $# -ge 2 ]] || die "--out needs a value"
      OUTDIR="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    -*)
      die "Unknown option: $1";;
    *)
      INPUT="$1"; shift;;
  esac
done

[[ -n "$INPUT" ]] || { usage; exit 1; }

case "$MODE" in
  single|playlist|auto) ;;
  *) die "Invalid --mode: $MODE (use single|playlist|auto)" ;;
esac

case "$SANITIZE" in
  auto|on|off) ;;
  *) die "Invalid --sanitize: $SANITIZE (use auto|on|off)" ;;
esac

# -------- deps / setup --------
need_cmd yt-dlp
need_cmd node

mkdir -p "$OUTDIR"

# Output template: change if you want playlist folders, indexing, etc.
# For playlists you might prefer: "$OUTDIR/%(playlist)s/%(playlist_index)03d - %(title)s.%(ext)s"
OUTPUT_TEMPLATE="$OUTDIR/%(title)s.%(ext)s"

# Build yt-dlp args
BASE_ARGS=(
  -x
  --audio-format "$AUDIO_FORMAT"
  --audio-quality "$AUDIO_QUALITY"
  --js-runtimes node
  --remote-components ejs:github
  -o "$OUTPUT_TEMPLATE"
)

MODE_ARGS=()
if [[ "$MODE" == "single" ]]; then
  MODE_ARGS+=(--no-playlist)
elif [[ "$MODE" == "playlist" ]]; then
  MODE_ARGS+=(--yes-playlist)
fi
# mode=auto adds nothing (yt-dlp decides)

should_sanitize() {
  [[ "$SANITIZE" == "on" ]] && return 0
  [[ "$SANITIZE" == "off" ]] && return 1
  # auto
  [[ "$MODE" == "single" ]] && return 0
  return 1
}

download_one() {
  local url="$1"
  [[ -n "$url" ]] || return 0

  # Skip comments and blank lines
  [[ "$url" =~ ^[[:space:]]*$ ]] && return 0
  [[ "$url" =~ ^[[:space:]]*# ]] && return 0

  # Trim leading/trailing whitespace (bash-ish but reliable enough here)
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"

  if should_sanitize; then
    url="$(sanitize_url "$url")"
  fi

  echo "Downloading ($MODE): $url"
  yt-dlp "${BASE_ARGS[@]}" "${MODE_ARGS[@]}" "$url"
}

# -------- run --------
if [[ -f "$INPUT" ]]; then
  # Read file: one URL per line
  while IFS= read -r line || [[ -n "$line" ]]; do
    download_one "$line"
  done < "$INPUT"
else
  # Single URL
  download_one "$INPUT"
fi
