#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Debianedara — an elegant KDE Plasma 6 theme with a deep-space identity
#
# Light + dark color schemes with a luminous nebula-blue accent, matching
# Kvantum widget themes (flat, blurred translucent menus), a choice of
# wallpapers for the desktop and the lock screen, Inter as the system font,
# an optional macOS-like layout (thin top bar with global menu + centered
# floating dock), and an optional day/night auto cycle.
#
# Target:  Debian 13 (trixie) with KDE Plasma 6.3 on Wayland.
#          Should work on any Plasma 6.x, but only tested there.
#
# Usage:   bash install.sh
#          Run as your normal user (sudo is only invoked for apt).
#          Every choice can be preseeded via environment variables, e.g.:
#          WALLPAPER=space LOCKSCREEN=follow STYLE=kvantum ICONS=yes \
#          MACOS_LAYOUT=yes BUTTONS_LEFT=yes CYCLE=no KONSOLE=dark \
#          DIRCOLORS=yes DRACULA=yes CLOCK_SIZE=15 CLOCK_DATE=macos \
#          CLOCK_24H=yes MODE=dark bash install.sh
#
# What it touches (all user-level, nothing outside $HOME except apt):
#   ~/.local/share/color-schemes/Debianedara{Light,Dark}.colors
#   ~/.local/share/plasma/look-and-feel/org.debianedara.{light,dark}/
#   ~/.config/Kvantum/Debianedara{Light,Dark}/   (only with STYLE=kvantum)
#   ~/.local/share/wallpapers/debianedara-*.{png,jpg}
#   ~/.local/share/konsole/Dracula*.{colorscheme,profile}  (only if chosen)
#   ~/.config/debianedara/theme.conf     what the mode switcher applies
#   ~/.config/debianedara/install.conf   the answers, reused as next defaults
#   ~/.config/debianedara/manifest.sha256  checksums of everything generated
#   ~/.config/debianedara/dircolors      (only with DIRCOLORS=yes)
#   ~/.local/bin/debianedara-mode, ~/.local/bin/debianedara-style
#   ~/.config/systemd/user/debianedara.{service,timer}
#   ~/.config/autostart/debianedara.desktop        (only if cycle enabled)
#   ~/.config/kdeglobals, kwinrulesrc, kscreenlockerrc (via kwriteconfig6)
#   ~/.bashrc                                      (only with DIRCOLORS=yes)
#   Panel layout via plasmashell scripting          (only if chosen)
#
# After the install, ~/.config/debianedara/theme.conf is the one place to
# change what light and dark mode look like; `debianedara-style` switches the
# application style.
#
# Re-running this script updates in place and keeps local changes: every file
# it generates is checksummed, so anything edited since is left alone and the
# new version is dropped beside it as <file>.new (listed at the end). The
# wallpapers already on disk are kept, and the panel layout is applied once.
# OVERWRITE=yes ignores all of that and reinstalls from scratch.
#
# Uninstall hints are printed at the end.
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Helpers ─────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ask VAR "question" default  → honors a preseeded env var, prompts on a tty,
# falls back to the default otherwise. Answers are yes/no.
ask() {
    local var="$1" question="$2" default="$3" answer
    local current="${!var:-}"
    if [[ -n "$current" ]]; then return 0; fi
    local prev="PREV_$var"
    default="${!prev:-$default}"
    if [[ -t 0 ]]; then
        local hint="[Y/n]"; [[ "$default" == "no" ]] && hint="[y/N]"
        read -r -p "$question $hint " answer || true
        answer="${answer,,}"
        case "$answer" in
            y|yes) printf -v "$var" yes ;;
            n|no)  printf -v "$var" no ;;
            *)     printf -v "$var" "$default" ;;
        esac
    else
        printf -v "$var" "$default"
    fi
}

command -v plasmashell   >/dev/null || die "plasmashell not found — is this a KDE Plasma session?"
command -v kwriteconfig6 >/dev/null || die "kwriteconfig6 not found — KDE Plasma 6 is required."

# ── Staying update-safe ─────────────────────────────────────────────────────
# Re-running the installer must not throw away hand edits. Every generated
# file's checksum goes into a manifest; on the next run a file that still
# matches is regenerated, and one that does not is left alone with the new
# version dropped beside it as <file>.new. OVERWRITE=yes ignores all that and
# reinstalls from scratch.
#
# The answers themselves are remembered too, so `bash install.sh` a second
# time offers what you picked the first time instead of the stock defaults.

CONFDIR="$HOME/.config/debianedara"
MANIFEST="$CONFDIR/manifest.sha256"
ANSWERS="$CONFDIR/install.conf"
mkdir -p "$CONFDIR"

OVERWRITE="${OVERWRITE:-no}"
KEPT=()   # files preserved because they had local changes

# Previous answers become this run's defaults, as $PREV_<NAME>. Parsed by hand
# rather than sourced: this file is data, not code to execute.
if [[ -r "$ANSWERS" ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
        val="${BASH_REMATCH[2]}"
        val="${val%\"}"; val="${val#\"}"
        printf -v "PREV_${BASH_REMATCH[1]}" '%s' "$val"
    done < "$ANSWERS"
    info "Found a previous install — its answers are the defaults below."
fi

hash_of() { sha256sum "$1" | cut -d' ' -f1; }

# The hash we recorded for a path, if any. Paths can contain spaces, so split
# on sha256sum's two-space separator instead of on whitespace.
manifest_hash() {
    local want="$1" line
    [[ -r "$MANIFEST" ]] || return 1
    while IFS= read -r line; do
        if [[ "${line#*  }" == "$want" ]]; then printf '%s' "${line%%  *}"; return 0; fi
    done < "$MANIFEST"
    return 1
}

manifest_set() {
    local path="$1" tmp
    tmp=$(mktemp)
    if [[ -r "$MANIFEST" ]]; then
        while IFS= read -r line; do
            [[ "${line#*  }" == "$path" ]] || printf '%s\n' "$line"
        done < "$MANIFEST" > "$tmp"
    fi
    printf '%s  %s\n' "$(hash_of "$path")" "$path" >> "$tmp"
    mv "$tmp" "$MANIFEST"
}

# True when the file on disk is exactly what a previous run of this installer
# put there — i.e. nobody has edited it since.
untouched() {
    local path="$1" recorded
    [[ -e "$path" ]] || return 0
    recorded=$(manifest_hash "$path") || return 1
    [[ "$recorded" == "$(hash_of "$path")" ]]
}

# write_generated <path>   — content on stdin, honoring local changes.
write_generated() {
    local dest="$1" tmp
    tmp=$(mktemp); cat > "$tmp"
    if [[ -e "$dest" ]] && [[ "$(hash_of "$tmp")" == "$(hash_of "$dest")" ]]; then
        rm -f "$tmp"; manifest_set "$dest"; return 0      # already identical
    fi
    if [[ -e "$dest" && "$OVERWRITE" != "yes" ]] && ! untouched "$dest"; then
        mv "$tmp" "$dest.new"; KEPT+=("$dest")            # locally modified
        warn "Kept your $(basename "$dest") — new version beside it as .new"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$tmp" "$dest"
    manifest_set "$dest"
}

# Where the repository's own assets live (wallpaper mirror, Konsole themes)
RAW_BASE="https://raw.githubusercontent.com/Nedara-Project/debianedara/main"

PLASMA_VERSION=$(plasmashell --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
info "Detected Plasma $PLASMA_VERSION"
[[ "${PLASMA_VERSION%%.*}" == "6" ]] || warn "This theme targets Plasma 6.x — continuing anyway."

# ── Choices ─────────────────────────────────────────────────────────────────

echo
echo "Debianedara installer — answer a few questions (Enter = default):"
echo

# WALLPAPER: which desktop wallpaper the theme installs.
#   space   the deep-space nebula, the same image in both modes
#   aurora  a light/dark pair of soft gradients that follows the mode
#   a path or URL to your own image, or 'skip' to keep the current one
# ('nebula' is still accepted as the old name for 'space'.)
DEF_WALLPAPER="${PREV_WALLPAPER:-space}"
if [[ -z "${WALLPAPER:-}" ]]; then
    if [[ -t 0 ]]; then
        echo "Wallpaper:"
        echo "    space   deep-space nebula, same image in both modes (~14 MB download)"
        echo "    aurora  light/dark pair of soft gradients, follows the mode (~1.4 MB)"
        echo "    <path>  a path or URL to your own image"
        echo "    skip    keep the wallpaper you already have"
        read -r -p "  Choice [$DEF_WALLPAPER]: " WALLPAPER || true
    fi
    WALLPAPER="${WALLPAPER:-$DEF_WALLPAPER}"
fi
[[ "$WALLPAPER" == "nebula" ]] && WALLPAPER=space

# LOCKSCREEN: follow (same wallpaper as the desktop, per mode) | a path/URL of
# its own | skip (leave the lock screen alone).
DEF_LOCKSCREEN="${PREV_LOCKSCREEN:-follow}"
if [[ -z "${LOCKSCREEN:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Lock screen — 'follow' the desktop wallpaper, a path/URL of its own, or 'skip' [$DEF_LOCKSCREEN]: " LOCKSCREEN || true
    fi
    LOCKSCREEN="${LOCKSCREEN:-$DEF_LOCKSCREEN}"
fi

# STYLE: the Qt/KDE application style — "Application Style" in System Settings.
# 'kvantum' also builds the matching Debianedara widget themes; any other name
# is applied as-is and skips the Kvantum build entirely.
DEF_STYLE="${PREV_STYLE:-kvantum}"
if [[ -z "${STYLE:-}" ]]; then
    if [[ -t 0 ]]; then
        echo "Application style:"
        echo "    kvantum  matching Debianedara widget themes, translucent menus"
        echo "    breeze   the Plasma default, no extra packages"
        echo "    fusion   Qt's built-in neutral style"
        echo "    <name>   any other style installed on this machine"
        read -r -p "  Choice [$DEF_STYLE]: " STYLE || true
    fi
    STYLE="${STYLE:-$DEF_STYLE}"
fi
STYLE="${STYLE,,}"

ask ICONS        "Install Tela-circle icon themes from GitHub (recommended)?"            yes
ask BUTTONS_LEFT "Move window buttons to the left, macOS order (close/min/max)?"         yes
ask MACOS_LAYOUT "Apply the macOS-like panel layout (thin top bar + centered dock)?"     yes
ask HIDE_XWVB    "Hide the Xwayland Video Bridge ghost window (fixes edge artifact)?"    yes
ask CYCLE        "Enable the automatic day/night cycle (light 07:00-19:00)?"             no
ask CLIPBOARD    "Keep the clipboard manager (Klipper) in the system tray?"              yes
ask DIRCOLORS    "Fix ls colors that are unreadable on a light background?"              yes

# KONSOLE: which Dracula flavour Konsole opens with. All three schemes are
# installed unless this is 'no'; the answer only picks the default profile.
#   dark   the original Dracula          light  Alucard, Dracula's light theme
#   storm  a softer, lighter dark        auto   follows light/dark mode
#   no     do not touch Konsole
# ('yes' is still accepted as the old name for 'dark'.)
DEF_KONSOLE="${PREV_KONSOLE:-dark}"
if [[ -z "${KONSOLE:-}" ]]; then
    if [[ -t 0 ]]; then
        echo "Konsole theme:"
        echo "    dark   the original Dracula"
        echo "    light  Alucard, Dracula's light theme (warm cream background)"
        echo "    storm  a softer, lighter dark variant"
        echo "    auto   dark or light, following the mode"
        echo "    no     leave Konsole alone"
        read -r -p "  Choice [$DEF_KONSOLE]: " KONSOLE || true
    fi
    KONSOLE="${KONSOLE:-$DEF_KONSOLE}"
fi
KONSOLE="${KONSOLE,,}"
[[ "$KONSOLE" == "yes" ]] && KONSOLE=dark
case "$KONSOLE" in
    dark|light|storm|auto|no) ;;
    *) warn "Unknown Konsole choice '$KONSOLE' — using 'dark'."; KONSOLE=dark ;;
esac
if command -v code >/dev/null || command -v codium >/dev/null; then
    ask DRACULA  "Install the Dracula theme extension in VS Code/VSCodium?"              yes
else
    DRACULA=no
fi
DEF_MODE="${PREV_MODE:-dark}"
if [[ -z "${MODE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Initial mode — 'dark', 'light' or 'auto' [$DEF_MODE]: " MODE || true
    fi
    MODE="${MODE:-$DEF_MODE}"
fi
# Clock font size in the top bar (macOS layout only): a point size, or 'auto'
# to keep Plasma's automatic two-line sizing.
DEF_CLOCK_SIZE="${PREV_CLOCK_SIZE:-15}"
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_SIZE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Top bar clock font size (8-24, or 'auto') [$DEF_CLOCK_SIZE]: " CLOCK_SIZE || true
    fi
    CLOCK_SIZE="${CLOCK_SIZE:-$DEF_CLOCK_SIZE}"
fi
CLOCK_SIZE="${CLOCK_SIZE:-auto}"
if [[ "$CLOCK_SIZE" != "auto" ]] && ! [[ "$CLOCK_SIZE" =~ ^[0-9]+$ && "$CLOCK_SIZE" -ge 8 && "$CLOCK_SIZE" -le 24 ]]; then
    warn "Invalid clock size '$CLOCK_SIZE' — using 15."
    CLOCK_SIZE=15
fi
# Date format shown by the clock: 'macos' is the menu bar's weekday/month/day,
# 'locale' keeps the system default, 'eu' is day/month/year, 'iso' is
# year-month-day, anything else is a custom Qt date format string
# (https://doc.qt.io/qt-6/qdate.html#toString).
DEF_CLOCK_DATE="${PREV_CLOCK_DATE:-macos}"
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_DATE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Clock date format — 'macos' (Mon Apr 1), 'locale', 'eu' (dd/MM/yy), 'iso', or custom [$DEF_CLOCK_DATE]: " CLOCK_DATE || true
    fi
    CLOCK_DATE="${CLOCK_DATE:-$DEF_CLOCK_DATE}"
fi
CLOCK_DATE="${CLOCK_DATE:-locale}"
# 24-hour time: 'locale' keeps the system default, 'yes' forces 24h.
DEF_CLOCK_24H="${PREV_CLOCK_24H:-locale}"
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_24H:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Force 24-hour time — 'yes' or 'locale' [$DEF_CLOCK_24H]: " CLOCK_24H || true
    fi
    CLOCK_24H="${CLOCK_24H:-$DEF_CLOCK_24H}"
fi
CLOCK_24H="${CLOCK_24H:-locale}"

echo
info "wallpaper=$WALLPAPER lockscreen=$LOCKSCREEN style=$STYLE icons=$ICONS buttons-left=$BUTTONS_LEFT macos-layout=$MACOS_LAYOUT hide-xwvb=$HIDE_XWVB cycle=$CYCLE konsole=$KONSOLE clipboard=$CLIPBOARD dircolors=$DIRCOLORS dracula=$DRACULA clock-size=${CLOCK_SIZE:-auto} mode=$MODE"
echo

# ── Packages ────────────────────────────────────────────────────────────────

PKGS=(fonts-inter)
[[ "$STYLE" == kvantum* ]] && PKGS+=(qt-style-kvantum qt-style-kvantum-themes)
[[ "$WALLPAPER" != "skip" || "$KONSOLE" != "no" ]] && PKGS+=(curl)
[[ "$ICONS" == "yes" ]] && PKGS+=(git)
[[ "$KONSOLE" != "no" ]] && PKGS+=(fonts-hack)
MISSING=()
for p in "${PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
    info "Installing packages: ${MISSING[*]}"
    sudo apt-get install -y "${MISSING[@]}"
else
    info "All required packages already installed."
fi

mkdir -p "$HOME/.local/share/color-schemes" \
         "$HOME/.local/share/wallpapers" \
         "$HOME/.local/bin" \
         "$HOME/.config/systemd/user" \
         "$HOME/.config/autostart" \
         "$HOME/.config/Kvantum" \
         "$HOME/.config/debianedara"

# ── Wallpaper ───────────────────────────────────────────────────────────────

WALLDIR="$HOME/.local/share/wallpapers"
SPACE="$WALLDIR/debianedara-space.png"
AURORA_LIGHT="$WALLDIR/debianedara-aurora-light.jpg"
AURORA_DARK="$WALLDIR/debianedara-aurora-dark.jpg"
CUSTOM="$WALLDIR/debianedara-custom"

# An image already on disk is kept as it is — re-downloading 14 MB on every
# run is wasteful, and it would undo a wallpaper swapped in by hand.
have_wallpaper() {
    [[ -s "$1" && "$OVERWRITE" != "yes" ]] || return 1
    info "Keeping the wallpaper already at $(basename "$1")."
}

# fetch <destination> <asset name in the repository> [fallback URL]
fetch_asset() {
    local dest="$1" asset="$2" fallback="${3:-}"
    curl -fL --retry 2 -o "$dest" "$RAW_BASE/assets/${asset// /%20}" && return 0
    [[ -n "$fallback" ]] && curl -fL --retry 2 -o "$dest" "$fallback" && return 0
    return 1
}

# WALL_LIGHT / WALL_DARK are what the mode switcher applies; an empty value
# means "leave the wallpaper alone in that mode".
WALL_LIGHT=""; WALL_DARK=""
case "$WALLPAPER" in
    skip)
        warn "Wallpaper skipped — the theme will keep your current one."
        ;;
    space)
        # Mirrored in this repository so the theme survives the source going
        # away; original: https://wallhaven.cc/w/mlgmjm
        if have_wallpaper "$SPACE"; then
            WALL_LIGHT="$SPACE"; WALL_DARK="$SPACE"
        else
            info "Downloading the nebula wallpaper..."
            if fetch_asset "$SPACE" "debianedara-space.png" "https://w.wallhaven.cc/full/ml/wallhaven-mlgmjm.png"; then
                WALL_LIGHT="$SPACE"; WALL_DARK="$SPACE"
            else
                warn "Download failed — wallpaper skipped, set one manually later."
            fi
        fi
        ;;
    aurora)
        if have_wallpaper "$AURORA_LIGHT" && have_wallpaper "$AURORA_DARK"; then
            WALL_LIGHT="$AURORA_LIGHT"; WALL_DARK="$AURORA_DARK"
        else
            info "Downloading the aurora wallpapers..."
            if fetch_asset "$AURORA_LIGHT" "debianedara-aurora-light.jpg" \
               && fetch_asset "$AURORA_DARK" "debianedara-aurora-dark.jpg"; then
                WALL_LIGHT="$AURORA_LIGHT"; WALL_DARK="$AURORA_DARK"
            else
                warn "Download failed — wallpaper skipped, set one manually later."
            fi
        fi
        ;;
    http*)
        info "Downloading custom wallpaper..."
        if curl -fL --retry 2 -o "$CUSTOM" "$WALLPAPER"; then
            WALL_LIGHT="$CUSTOM"; WALL_DARK="$CUSTOM"
        else
            warn "Download failed — wallpaper skipped."
        fi
        ;;
    *)
        if [[ -f "$WALLPAPER" ]]; then
            cp "$WALLPAPER" "$CUSTOM"
            WALL_LIGHT="$CUSTOM"; WALL_DARK="$CUSTOM"
        else
            warn "File not found: $WALLPAPER — wallpaper skipped."
        fi
        ;;
esac

# Whatever the Look and Feel packages advertise as their wallpaper (a single
# image each, so the light package gets the light one).
WALL="${WALL_DARK:-$WALL_LIGHT}"

# ── Lock screen ─────────────────────────────────────────────────────────────
# LOCK_LIGHT / LOCK_DARK follow the desktop by default, so locking the screen
# does not flip to a different image mid-theme.

LOCK_LIGHT=""; LOCK_DARK=""
case "$LOCKSCREEN" in
    skip)
        info "Lock screen left as it is."
        ;;
    follow)
        LOCK_LIGHT="$WALL_LIGHT"; LOCK_DARK="$WALL_DARK"
        ;;
    http*)
        info "Downloading the lock screen wallpaper..."
        if curl -fL --retry 2 -o "$WALLDIR/debianedara-lock" "$LOCKSCREEN"; then
            LOCK_LIGHT="$WALLDIR/debianedara-lock"; LOCK_DARK="$LOCK_LIGHT"
        else
            warn "Download failed — lock screen left as it is."
        fi
        ;;
    *)
        if [[ -f "$LOCKSCREEN" ]]; then
            cp "$LOCKSCREEN" "$WALLDIR/debianedara-lock"
            LOCK_LIGHT="$WALLDIR/debianedara-lock"; LOCK_DARK="$LOCK_LIGHT"
        else
            warn "File not found: $LOCKSCREEN — lock screen left as it is."
        fi
        ;;
esac

# ── Icons: Tela-circle ──────────────────────────────────────────────────────

if [[ "$ICONS" == "yes" ]] && [[ ! -d "$HOME/.local/share/icons/Tela-circle" ]]; then
    info "Installing Tela-circle icons (this can take a minute)..."
    TMPD=$(mktemp -d)
    if git clone --depth 1 https://github.com/vinceliuice/Tela-circle-icon-theme "$TMPD/tela"; then
        "$TMPD/tela/install.sh" -d "$HOME/.local/share/icons" standard >/dev/null
    else
        warn "Could not clone Tela-circle — keeping Breeze icons."
        ICONS=no
    fi
    rm -rf "$TMPD"
fi

# ── Color schemes ───────────────────────────────────────────────────────────

info "Installing color schemes..."

write_generated "$HOME/.local/share/color-schemes/DebianedaraDark.colors" <<'EOF'
# Debianedara Dark — deep-space navy scheme with a luminous nebula-blue accent
# Generated for KDE Plasma 6

[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=112,111,110
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=38,58,110
BackgroundNormal=31,37,54
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Complementary]
BackgroundAlternate=11,14,23
BackgroundNormal=16,19,30
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Header]
BackgroundAlternate=16,19,30
BackgroundNormal=11,14,23
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Header][Inactive]
BackgroundAlternate=13,16,26
BackgroundNormal=16,19,30
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Selection]
BackgroundAlternate=38,58,110
BackgroundNormal=46,99,201
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=255,255,255
ForegroundInactive=205,220,242
ForegroundLink=170,220,255
ForegroundNegative=255,205,210
ForegroundNeutral=255,224,178
ForegroundNormal=255,255,255
ForegroundPositive=200,230,201
ForegroundVisited=222,213,245

[Colors:Tooltip]
BackgroundAlternate=16,19,30
BackgroundNormal=24,29,46
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:View]
BackgroundAlternate=16,19,30
BackgroundNormal=11,14,23
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Window]
BackgroundAlternate=24,29,46
BackgroundNormal=16,19,30
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[General]
ColorScheme=DebianedaraDark
Name=Debianedara Dark
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground=11,14,23
activeBlend=11,14,23
activeForeground=213,217,230
inactiveBackground=16,19,30
inactiveBlend=16,19,30
inactiveForeground=126,134,160
EOF

write_generated "$HOME/.local/share/color-schemes/DebianedaraLight.colors" <<'EOF'
# Debianedara Light — cool paper scheme with a deep nebula-blue accent
# Generated for KDE Plasma 6

[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=112,111,110
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=201,220,246
BackgroundNormal=248,250,252
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[Colors:Complementary]
BackgroundAlternate=11,14,23
BackgroundNormal=16,19,30
DecorationFocus=77,141,255
DecorationHover=77,141,255
ForegroundActive=77,141,255
ForegroundInactive=126,134,160
ForegroundLink=111,199,255
ForegroundNegative=240,97,109
ForegroundNeutral=245,171,83
ForegroundNormal=213,217,230
ForegroundPositive=94,199,132
ForegroundVisited=176,138,230

[Colors:Header]
BackgroundAlternate=236,239,245
BackgroundNormal=226,230,238
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[Colors:Header][Inactive]
BackgroundAlternate=231,235,242
BackgroundNormal=236,239,245
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[Colors:Selection]
BackgroundAlternate=201,220,246
BackgroundNormal=46,99,201
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=255,255,255
ForegroundInactive=214,227,245
ForegroundLink=195,225,255
ForegroundNegative=255,205,210
ForegroundNeutral=255,224,178
ForegroundNormal=255,255,255
ForegroundPositive=200,230,201
ForegroundVisited=222,213,245

[Colors:Tooltip]
BackgroundAlternate=236,239,245
BackgroundNormal=247,249,252
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[Colors:View]
BackgroundAlternate=242,244,248
BackgroundNormal=251,252,254
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[Colors:Window]
BackgroundAlternate=228,232,240
BackgroundNormal=240,242,246
DecorationFocus=36,86,179
DecorationHover=36,86,179
ForegroundActive=36,86,179
ForegroundInactive=116,121,136
ForegroundLink=27,102,201
ForegroundNegative=191,42,60
ForegroundNeutral=176,105,0
ForegroundNormal=33,36,46
ForegroundPositive=24,132,74
ForegroundVisited=106,90,205

[General]
ColorScheme=DebianedaraLight
Name=Debianedara Light
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground=226,230,238
activeBlend=226,230,238
activeForeground=33,36,46
inactiveBackground=240,242,246
inactiveBlend=240,242,246
inactiveForeground=116,121,136
EOF

# ── Kvantum themes (derived from KvFlat / KvFlatLight) ──────────────────────

# Only built for the Kvantum style; any other application style skips it.
KVANTUM_LIGHT=""; KVANTUM_DARK=""
KV_D="$HOME/.config/Kvantum/DebianedaraDark/DebianedaraDark.kvconfig"
KV_L="$HOME/.config/Kvantum/DebianedaraLight/DebianedaraLight.kvconfig"
if [[ "$STYLE" == kvantum* && "$OVERWRITE" != "yes" ]] && { ! untouched "$KV_D" || ! untouched "$KV_L"; }; then
    warn "Kvantum themes have local changes — keeping them (OVERWRITE=yes rebuilds)."
    KVANTUM_LIGHT=DebianedaraLight; KVANTUM_DARK=DebianedaraDark
    KEPT+=("$HOME/.config/Kvantum/Debianedara{Light,Dark}/")
elif [[ "$STYLE" == kvantum* ]]; then
    info "Building Kvantum themes..."
    [[ -d /usr/share/Kvantum/KvFlat ]] || die "KvFlat not found — is qt-style-kvantum-themes installed?"
    KVANTUM_LIGHT=DebianedaraLight; KVANTUM_DARK=DebianedaraDark

    OPAQUE="kaffeine kmplayer subtitlecomposer kdenlive vlc smplayer smplayer2 avidemux kamoso QtCreator VirtualBox trojita mediainfo-gui qmlscene qml plasmashell krunner ksmserver kscreenlocker_greet"

    rm -rf "$HOME/.config/Kvantum/DebianedaraDark" "$HOME/.config/Kvantum/DebianedaraLight"
    cp -r /usr/share/Kvantum/KvFlat "$HOME/.config/Kvantum/DebianedaraDark"
    mv "$HOME/.config/Kvantum/DebianedaraDark/KvFlat.kvconfig" "$HOME/.config/Kvantum/DebianedaraDark/DebianedaraDark.kvconfig"
    mv "$HOME/.config/Kvantum/DebianedaraDark/KvFlat.svg" "$HOME/.config/Kvantum/DebianedaraDark/DebianedaraDark.svg"
    cp -r /usr/share/Kvantum/KvFlatLight "$HOME/.config/Kvantum/DebianedaraLight"
    mv "$HOME/.config/Kvantum/DebianedaraLight/KvFlatLight.kvconfig" "$HOME/.config/Kvantum/DebianedaraLight/DebianedaraLight.kvconfig"
    mv "$HOME/.config/Kvantum/DebianedaraLight/KvFlatLight.svg" "$HOME/.config/Kvantum/DebianedaraLight/DebianedaraLight.svg"

    D="$HOME/.config/Kvantum/DebianedaraDark/DebianedaraDark.kvconfig"
    sed -i \
     -e 's/^window\.color=.*/window.color=#10131E/' \
     -e 's/^base\.color=.*/base.color=#0B0E17/' \
     -e 's/^alt\.base\.color=.*/alt.base.color=#10131E/' \
     -e 's/^button\.color=.*/button.color=#1F2536/' \
     -e 's/^light\.color=.*/light.color=#2E3752/' \
     -e 's/^mid\.light\.color=.*/mid.light.color=#252D45/' \
     -e 's/^dark\.color=.*/dark.color=#060810/' \
     -e 's/^mid\.color=.*/mid.color=#1A2033/' \
     -e 's/^highlight\.color=.*/highlight.color=#2E63C9/' \
     -e 's/^inactive\.highlight\.color=.*/inactive.highlight.color=#22488F/' \
     -e 's/^text\.color=.*/text.color=#D5D9E6/' \
     -e 's/^window\.text\.color=.*/window.text.color=#D5D9E6/' \
     -e 's/^button\.text\.color=.*/button.text.color=#D5D9E6/' \
     -e 's/^disabled\.text\.color=.*/disabled.text.color=#7E86A0/' \
     -e 's/^tooltip\.text\.color=.*/tooltip.text.color=#D5D9E6/' \
     -e 's/^link\.color=.*/link.color=#6FC7FF/' \
     -e 's/^link\.visited\.color=.*/link.visited.color=#B08AE6/' \
     -e 's/^comment=.*/comment=Debianedara Dark — flat, translucent menus/' \
     -e 's/^author=.*/author=Debianedara/' \
     -e 's/^menu_shadow_depth=.*/menu_shadow_depth=20/' "$D"

    L="$HOME/.config/Kvantum/DebianedaraLight/DebianedaraLight.kvconfig"
    sed -i \
     -e 's/^window\.color=.*/window.color=#F0F2F6/' \
     -e 's/^base\.color=.*/base.color=#FBFCFE/' \
     -e 's/^alt\.base\.color=.*/alt.base.color=#F2F4F8/' \
     -e 's/^button\.color=.*/button.color=#F8FAFC/' \
     -e 's/^mid\.light\.color=.*/mid.light.color=#E8EBF2/' \
     -e 's/^dark\.color=.*/dark.color=#B0B6C4/' \
     -e 's/^mid\.color=.*/mid.color=#D5DAE4/' \
     -e 's/^highlight\.color=.*/highlight.color=#2456B3/' \
     -e 's/^inactive\.highlight\.color=.*/inactive.highlight.color=#7EA0D6/' \
     -e 's/^text\.color=.*/text.color=#21242E/' \
     -e 's/^window\.text\.color=.*/window.text.color=#21242E/' \
     -e 's/^button\.text\.color=.*/button.text.color=#21242E/' \
     -e 's/^link\.color=.*/link.color=#1B66C9/' \
     -e 's/^link\.visited\.color=.*/link.visited.color=#8854B5/' \
     -e 's/^comment=.*/comment=Debianedara Light — flat, translucent menus/' \
     -e 's/^author=.*/author=Debianedara/' \
     -e 's/^menu_shadow_depth=.*/menu_shadow_depth=20/' "$L"

    # Blurred translucent popups; windows themselves stay opaque (and Kvantum
    # window translucency does not work on Wayland anyway).
    for f in "$D" "$L"; do
        sed -i '/^\(translucent_windows\|reduce_window_opacity\|blurring\|popup_blurring\|opaque\|reduce_menu_opacity\)=/d' "$f"
    done
    sed -i "/^\[%General\]/a popup_blurring=true\nreduce_menu_opacity=12\nopaque=$OPAQUE" "$D"
    sed -i "/^\[%General\]/a popup_blurring=true\nreduce_menu_opacity=10\nopaque=$OPAQUE" "$L"
    manifest_set "$D"; manifest_set "$L"
else
    info "Application style is '$STYLE' — skipping the Kvantum themes."
fi

# ── Global themes (Look and Feel packages) ──────────────────────────────────

info "Installing global themes..."
ICON_LIGHT=breeze; ICON_DARK=breeze-dark
[[ "$ICONS" == "yes" ]] && { ICON_LIGHT=Tela-circle; ICON_DARK=Tela-circle-dark; }

for v in light dark; do
    LNF="$HOME/.local/share/plasma/look-and-feel/org.debianedara.$v"
    mkdir -p "$LNF/contents/previews"
    if [[ "$v" == "light" ]]; then
        NAME="Debianedara Light"; SCHEME=DebianedaraLight; ICON=$ICON_LIGHT
        WALL_V="${WALL_LIGHT:-$WALL}"
    else
        NAME="Debianedara Dark"; SCHEME=DebianedaraDark; ICON=$ICON_DARK
        WALL_V="${WALL_DARK:-$WALL}"
    fi

    write_generated "$LNF/metadata.json" <<EOF
{
    "KPlugin": {
        "Id": "org.debianedara.$v",
        "Name": "$NAME",
        "Description": "Elegant deep-space theme with a luminous nebula-blue accent",
        "Authors": [ { "Name": "Debianedara" } ],
        "Category": "",
        "License": "MIT",
        "Version": "1.0"
    },
    "KPackageStructure": "Plasma/LookAndFeel",
    "X-Plasma-APIVersion": "2"
}
EOF

    write_generated "$LNF/contents/defaults" <<EOF
[kdeglobals][KDE]
widgetStyle=$STYLE

[kdeglobals][General]
ColorScheme=$SCHEME

[kdeglobals][Icons]
Theme=$ICON

[plasmarc][Theme]
name=default

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
NoPlugin=false

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[Wallpaper]
Image=$WALL_V
EOF

    if command -v magick >/dev/null && [[ -n "$WALL_V" && -f "$WALL_V" ]]; then
        magick "$WALL_V" -resize 600x338 "$LNF/contents/previews/preview.png" 2>/dev/null || true
    fi
done

# ── What each mode looks like ───────────────────────────────────────────────
# One file drives the switcher, so light/dark can be retuned afterwards
# without reinstalling anything. Empty value = leave that setting alone.

KONSOLE_LIGHT=""; KONSOLE_DARK=""
case "$KONSOLE" in
    dark)  KONSOLE_LIGHT="Dracula";       KONSOLE_DARK="Dracula" ;;
    light) KONSOLE_LIGHT="Dracula Light"; KONSOLE_DARK="Dracula Light" ;;
    storm) KONSOLE_LIGHT="Dracula Storm"; KONSOLE_DARK="Dracula Storm" ;;
    auto)  KONSOLE_LIGHT="Dracula Light"; KONSOLE_DARK="Dracula" ;;
esac

info "Writing ~/.config/debianedara/theme.conf..."
write_generated "$CONFDIR/theme.conf" <<EOF
# Debianedara — what light and dark mode apply.
#
# Edit any value here, then run \`debianedara-mode light\` or \`dark\` (add
# FORCE=1 to reapply the mode you are already in). An empty value means the
# switcher leaves that setting alone.

# Application style, as in System Settings > Appearance > Application Style.
# Use \`debianedara-style\` to list and change it — it rewrites this line.
STYLE="$STYLE"

# Plasma color schemes (~/.local/share/color-schemes/*.colors)
SCHEME_LIGHT="DebianedaraLight"
SCHEME_DARK="DebianedaraDark"

# Kvantum widget themes (~/.config/Kvantum/*/), only used when STYLE=kvantum
KVANTUM_LIGHT="$KVANTUM_LIGHT"
KVANTUM_DARK="$KVANTUM_DARK"

# Icon themes
ICONS_LIGHT="$ICON_LIGHT"
ICONS_DARK="$ICON_DARK"

# Desktop wallpapers
WALL_LIGHT="$WALL_LIGHT"
WALL_DARK="$WALL_DARK"

# Lock screen wallpapers (same as the desktop by default)
LOCK_LIGHT="$LOCK_LIGHT"
LOCK_DARK="$LOCK_DARK"

# Konsole profiles, by name (~/.local/share/konsole/*.profile)
KONSOLE_LIGHT="$KONSOLE_LIGHT"
KONSOLE_DARK="$KONSOLE_DARK"
EOF

# ── Day/night switcher script ───────────────────────────────────────────────

info "Installing debianedara-mode..."
write_generated "$HOME/.local/bin/debianedara-mode" <<'EOF'
#!/usr/bin/env bash
# Debianedara day/night switcher.
# Usage: debianedara-mode [auto|light|dark]   (default: auto — light 07:00-19:00)
#
# Everything it applies is read from ~/.config/debianedara/theme.conf; edit
# that file to retune either mode. FORCE=1 reapplies the current mode.
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/debianedara/theme.conf"

# Defaults, so the script still works if the config file is missing.
STYLE=kvantum
SCHEME_LIGHT=DebianedaraLight;      SCHEME_DARK=DebianedaraDark
KVANTUM_LIGHT=DebianedaraLight;     KVANTUM_DARK=DebianedaraDark
ICONS_LIGHT=Tela-circle;            ICONS_DARK=Tela-circle-dark
WALL_LIGHT="$HOME/.local/share/wallpapers/debianedara-space.png"
WALL_DARK="$WALL_LIGHT"
LOCK_LIGHT="$WALL_LIGHT";           LOCK_DARK="$WALL_DARK"
KONSOLE_LIGHT="";                   KONSOLE_DARK=""
# shellcheck source=/dev/null
[[ -r "$CONF" ]] && . "$CONF"

MODE="${1:-auto}"
if [[ "$MODE" == "auto" ]]; then
    hour=$(date +%-H)
    if (( hour >= 7 && hour < 19 )); then MODE=light; else MODE=dark; fi
fi

case "$MODE" in
    light) SCHEME=$SCHEME_LIGHT; ICONS=$ICONS_LIGHT; KVANTUM=$KVANTUM_LIGHT
           WALL=$WALL_LIGHT; LOCK=$LOCK_LIGHT; KONSOLE=$KONSOLE_LIGHT ;;
    dark)  SCHEME=$SCHEME_DARK;  ICONS=$ICONS_DARK;  KVANTUM=$KVANTUM_DARK
           WALL=$WALL_DARK;  LOCK=$LOCK_DARK;  KONSOLE=$KONSOLE_DARK ;;
    *)     echo "usage: debianedara-mode [auto|light|dark]" >&2; exit 1 ;;
esac

# Skip if already in the right mode (avoids flicker when the timer fires)
current=$(grep -m1 '^ColorScheme=' "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2)
if [[ "$current" == "$SCHEME" && "${FORCE:-0}" != "1" ]]; then
    exit 0
fi

[[ -n "$SCHEME" ]] && plasma-apply-colorscheme "$SCHEME"

CHANGEICONS=$(ls /usr/lib/*/libexec/plasma-changeicons /usr/libexec/plasma-changeicons 2>/dev/null | head -1)
if [[ -n "$ICONS" && -n "$CHANGEICONS" ]] \
   && [[ -d "$HOME/.local/share/icons/$ICONS" || -d "/usr/share/icons/$ICONS" ]]; then
    "$CHANGEICONS" "$ICONS"
fi

if [[ "$STYLE" == kvantum* && -n "$KVANTUM" ]] && command -v kvantummanager >/dev/null; then
    kvantummanager --set "$KVANTUM" >/dev/null 2>&1
fi

if [[ -n "$WALL" && -f "$WALL" ]]; then
    plasma-apply-wallpaperimage "$WALL"
fi

if [[ -n "$LOCK" && -f "$LOCK" ]]; then
    for key in Image PreviewImage; do
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper \
            --group org.kde.image --group General --key "$key" "file://$LOCK"
    done
fi

# Konsole: the default profile decides what new windows look like; already
# open sessions are switched over D-Bus when Konsole is running.
if [[ -n "$KONSOLE" ]]; then
    kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "$KONSOLE.profile"
    if command -v qdbus6 >/dev/null; then
        for svc in $(qdbus6 2>/dev/null | awk '/^org\.kde\.konsole/ {print $1}'); do
            for sess in $(qdbus6 "$svc" 2>/dev/null | grep '^/Sessions/'); do
                qdbus6 "$svc" "$sess" org.kde.konsole.Session.setProfile "$KONSOLE" >/dev/null 2>&1
            done
        done
    fi
fi
EOF
chmod +x "$HOME/.local/bin/debianedara-mode"

# ── Application style picker ────────────────────────────────────────────────

info "Installing debianedara-style..."
write_generated "$HOME/.local/bin/debianedara-style" <<'EOF'
#!/usr/bin/env bash
# Debianedara application-style picker — the "Application Style" page of
# System Settings, from the command line.
#
# Usage: debianedara-style             list the styles found on this machine
#        debianedara-style <name>      apply one (breeze, kvantum, fusion, ...)
#
# The choice is written to ~/.config/debianedara/theme.conf too, so the
# day/night switcher keeps it instead of forcing Kvantum back.
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/debianedara/theme.conf"

# Fusion and Windows are built into Qt; Breeze ships with Plasma. Everything
# else comes from a style plugin: breeze6.so -> breeze, libkvantum.so -> kvantum.
list_styles() {
    { echo breeze; echo fusion; echo windows
      command -v kvantummanager >/dev/null && { echo kvantum; echo kvantum-dark; }
      for so in /usr/lib/*/qt6/plugins/styles/*.so "$HOME/.local/lib/qt6/plugins/styles/"*.so; do
          [[ -e "$so" ]] || continue
          name=$(basename "$so" .so); name=${name#lib}; name=${name%%[0-9]*}
          [[ -n "$name" ]] && echo "${name,,}"
      done
    } | sort -u
}

current=$(grep -m1 '^widgetStyle=' "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2)

if (( $# == 0 )); then
    echo "Application styles available here (current: ${current:-unset}):"
    list_styles | sed 's/^/  /'
    echo
    echo "Apply one with: debianedara-style <name>"
    exit 0
fi

STYLE="${1,,}"
if ! list_styles | grep -qx "$STYLE"; then
    echo "!! '$STYLE' is not among the styles found here — trying it anyway." >&2
    echo "   Run debianedara-style with no argument to see the list." >&2
fi

kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$STYLE"

# Keep the switcher in step, and hand Kvantum the theme for the current mode.
if [[ -w "$CONF" ]] && grep -q '^STYLE=' "$CONF"; then
    sed -i "s|^STYLE=.*|STYLE=\"$STYLE\"|" "$CONF"
    # Re-record the file so the installer does not mistake this edit for a
    # hand-tuned config and refuse to refresh it later.
    MANIFEST="${CONF%/theme.conf}/manifest.sha256"
    if [[ -w "$MANIFEST" ]]; then
        tmp=$(mktemp)
        while IFS= read -r line; do
            [[ "${line#*  }" == "$CONF" ]] || printf '%s\n' "$line"
        done < "$MANIFEST" > "$tmp"
        printf '%s  %s\n' "$(sha256sum "$CONF" | cut -d' ' -f1)" "$CONF" >> "$tmp"
        mv "$tmp" "$MANIFEST"
    fi
fi
# And remember it as the answer for the next install.
ANSWERS="${CONF%/theme.conf}/install.conf"
if [[ -w "$ANSWERS" ]] && grep -q '^STYLE=' "$ANSWERS"; then
    sed -i "s|^STYLE=.*|STYLE=\"$STYLE\"|" "$ANSWERS"
fi
if [[ "$STYLE" == kvantum* ]] && command -v kvantummanager >/dev/null; then
    scheme=$(grep -m1 '^ColorScheme=' "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2)
    theme=DebianedaraDark; [[ "$scheme" == *Light ]] && theme=DebianedaraLight
    [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum/$theme" ]] \
        && kvantummanager --set "$theme" >/dev/null 2>&1
fi

qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
echo ":: Application style set to '$STYLE'."
echo "   Already-running applications keep the old style until they restart."
EOF
chmod +x "$HOME/.local/bin/debianedara-style"

# ── Day/night cycle units (installed always, enabled on request) ────────────

write_generated "$HOME/.config/systemd/user/debianedara.service" <<'EOF'
[Unit]
Description=Debianedara day/night switch

[Service]
Type=oneshot
ExecStart=%h/.local/bin/debianedara-mode auto
EOF

write_generated "$HOME/.config/systemd/user/debianedara.timer" <<'EOF'
[Unit]
Description=Debianedara day/night switch at 07:00 and 19:00

[Timer]
OnCalendar=*-*-* 07:00:00
OnCalendar=*-*-* 19:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
if [[ "$CYCLE" == "yes" ]]; then
    systemctl --user enable --now debianedara.timer
    cat > "$HOME/.config/autostart/debianedara.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Debianedara day/night mode
Exec=debianedara-mode auto
X-KDE-autostart-after=panel
OnlyShowIn=KDE;
EOF
    info "Day/night cycle enabled (timer + login autostart)."
else
    systemctl --user disable --now debianedara.timer 2>/dev/null || true
    rm -f "$HOME/.config/autostart/debianedara.desktop"
fi

# ── Fonts: Inter ────────────────────────────────────────────────────────────

if fc-list 2>/dev/null | grep -qi "Inter:style\|Inter,"; then
    info "Setting Inter as the system font..."
    kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key menuFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key toolBarFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1"
else
    warn "Inter font not found — keeping current fonts."
fi

# ── Konsole: the Dracula family ─────────────────────────────────────────────
# https://draculatheme.com — MIT licensed, mirrored in this repository.
# Dracula (the original), Dracula Storm (a softer dark) and Dracula Light
# (built on Alucard, Dracula's light theme, on a warm cream background so it
# stays readable without glare) are all installed; the choice picks which
# profile Konsole opens with.

if [[ "$KONSOLE" != "no" ]]; then
    info "Installing the Dracula Konsole themes..."
    mkdir -p "$HOME/.local/share/konsole"
    KONSOLE_OK=yes
    for f in "Dracula.colorscheme"       "Dracula.profile" \
             "Dracula Storm.colorscheme" "Dracula Storm.profile" \
             "Dracula Light.colorscheme" "Dracula Light.profile"; do
        KTMP=$(mktemp)
        if fetch_asset "$KTMP" "konsole/$f"; then
            write_generated "$HOME/.local/share/konsole/$f" < "$KTMP"
        else
            warn "Could not download $f"; KONSOLE_OK=no
        fi
        rm -f "$KTMP"
    done
    if [[ "$KONSOLE_OK" == "yes" ]]; then
        # The switcher applies the profile for the mode; set it here too so
        # Konsole is right even when the switcher is never run.
        DEFAULT_PROFILE="$KONSOLE_DARK"
        [[ "$MODE" == "light" ]] && DEFAULT_PROFILE="$KONSOLE_LIGHT"
        kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "$DEFAULT_PROFILE.profile"
        info "'$DEFAULT_PROFILE' set as the default Konsole profile."
    fi
fi

# ── ls colors that survive a light background ───────────────────────────────
# GNU ls paints other-writable and sticky directories on a *green* background
# (OTHER_WRITABLE 34;42, STICKY_OTHER_WRITABLE 30;42) and setuid/setgid files
# on red and yellow ones. A terminal has a single palette for text and
# backgrounds, so a green dark enough to read as text is a terrible background
# — those entries come out as unreadable blocks in any light theme (and are
# not pretty in dark ones either). This drops the backgrounds and keeps the
# distinction in the foreground color instead.

if [[ "$DIRCOLORS" == "yes" ]] && command -v dircolors >/dev/null; then
    info "Installing readable ls colors..."
    # Rewritten in place, so each keyword keeps exactly one definition:
    #   o+w dirs      34;42 -> underlined bold blue (still flagged, no fill)
    #   setuid/setgid 37;41 / 30;43 -> bold red / bold yellow text
    #   broken links  40;31;01 -> bold red text
    DC="$CONFDIR/dircolors"
    DCTMP=$(mktemp)
    dircolors -p | sed -E \
        -e 's/^(OTHER_WRITABLE|STICKY_OTHER_WRITABLE)[[:space:]]+[0-9;]+/\1 04;01;34/' \
        -e 's/^(STICKY)[[:space:]]+[0-9;]+/\1 01;34/' \
        -e 's/^(SETUID|ORPHAN|MISSING)[[:space:]]+[0-9;]+/\1 01;31/' \
        -e 's/^(SETGID)[[:space:]]+[0-9;]+/\1 01;33/' > "$DCTMP"
    write_generated "$DC" < "$DCTMP"
    rm -f "$DCTMP"

    MARK="# Debianedara ls colors"
    if ! grep -qF "$MARK" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF'

# Debianedara ls colors — remove this block to go back to the defaults
if [[ -r "$HOME/.config/debianedara/dircolors" ]] && command -v dircolors >/dev/null; then
    eval "$(dircolors -b "$HOME/.config/debianedara/dircolors")"
fi
EOF
        info "Added the dircolors block to ~/.bashrc (open a new shell to see it)."
    else
        info "~/.bashrc already sources the dircolors file."
    fi
    warn "Over SSH the colors come from the remote host — send the file along:"
    echo '     scp ~/.config/debianedara/dircolors user@host:~/.dircolors'
    echo '     # then, in the remote ~/.bashrc:'
    echo '     eval "$(dircolors -b ~/.dircolors)"'
fi

# ── VS Code / VSCodium: Dracula theme extension ─────────────────────────────
# https://marketplace.visualstudio.com/items?itemName=dracula-theme.theme-dracula

if [[ "$DRACULA" == "yes" ]]; then
    for editor in code codium; do
        if command -v "$editor" >/dev/null; then
            info "Installing the Dracula extension in $editor..."
            "$editor" --install-extension dracula-theme.theme-dracula --force >/dev/null \
                && info "Done — pick 'Dracula Theme' in $editor via Ctrl+K Ctrl+T." \
                || warn "Extension install failed in $editor (marketplace unreachable?)."
        fi
    done
fi

# ── Window buttons on the left (macOS order) ────────────────────────────────

if [[ "$BUTTONS_LEFT" == "yes" ]]; then
    info "Moving window buttons to the left..."
    kwriteconfig6 --file kdeglobals --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
    kwriteconfig6 --file kdeglobals --group org.kde.kdecoration2 --key ButtonsOnRight ""
fi

# ── KWin rule: hide the Xwayland Video Bridge ghost window ──────────────────

if [[ "$HIDE_XWVB" == "yes" ]]; then
    RULE=hide-xwaylandvideobridge
    RULES=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
    if [[ ",$RULES," != *",$RULE,"* ]]; then
        info "Adding KWin rule to hide Xwayland Video Bridge..."
        NEWRULES="${RULES:+$RULES,}$RULE"
        kwriteconfig6 --file kwinrulesrc --group General --key rules "$NEWRULES"
        kwriteconfig6 --file kwinrulesrc --group General --key count "$(awk -F, '{print NF}' <<< "$NEWRULES")"
        for kv in "Description=Hide Xwayland Video Bridge" "above=false" "aboverule=2" \
                  "desktopfile=xwaylandvideobridge" "minimize=true" "minimizerule=3" \
                  "skippager=true" "skippagerrule=2" "skipswitcher=true" "skipswitcherrule=2" \
                  "skiptaskbar=true" "skiptaskbarrule=2" "wmclass=xwaylandvideobridge" "wmclassmatch=1"; do
            kwriteconfig6 --file kwinrulesrc --group "$RULE" --key "${kv%%=*}" "${kv#*=}"
        done
    fi
fi

# ── macOS-like panel layout ─────────────────────────────────────────────────

# Applied once: re-running the panel script would strip whatever widgets have
# been added to the dock since, and the layout is not something a second pass
# improves. OVERWRITE=yes (or LAYOUT_APPLIED=no) applies it again.
if [[ "$MACOS_LAYOUT" == "yes" && "${PREV_LAYOUT_APPLIED:-no}" == "yes" && "$OVERWRITE" != "yes" ]]; then
    info "Panel layout already applied — leaving it alone."
    LAYOUT_APPLIED=yes
elif [[ "$MACOS_LAYOUT" == "yes" ]]; then
    info "Applying the macOS-like layout (backup: ~/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup)..."
    # Only ever the pre-Debianedara layout: overwriting it on a second run
    # would leave nothing to restore.
    BACKUP="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup"
    [[ -e "$BACKUP" ]] || cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$BACKUP" 2>/dev/null || true
    LAYOUT_APPLIED=yes
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
        var pl = panels();
        var hasTop = false;
        for (var i = 0; i < pl.length; i++) {
            if (pl[i].location == "top") hasTop = true;
        }
        for (var i = 0; i < pl.length; i++) {
            var p = pl[i];
            if (p.location != "bottom") continue;
            var ws = p.widgets();
            for (var j = 0; j < ws.length; j++) {
                if (ws[j].type != "org.kde.plasma.icontasks") { ws[j].remove(); }
            }
            p.lengthMode = "fit";
            p.alignment = "center";
            p.height = 56;
            p.floating = true;
            p.opacity = "translucent";
        }
        if (!hasTop) {
            var top = new Panel;
            top.location = "top";
            top.height = 30;
            top.floating = false;
            top.opacity = "translucent";
            top.addWidget("org.kde.plasma.kickoff");
            top.addWidget("org.kde.plasma.appmenu");
            top.addWidget("org.kde.plasma.panelspacer");
            top.addWidget("org.kde.plasma.systemtray");
            top.addWidget("org.kde.plasma.digitalclock");
        }
    '
    # Clock appearance. A fixed size only reads well on one line, so the date
    # moves beside the time (two stacked lines stay tiny in a 30 px bar).
    CLOCK_JS=""
    if [[ "$CLOCK_SIZE" != "auto" ]]; then
        CLOCK_JS+="w.writeConfig('autoFontAndSize', false);"
        CLOCK_JS+="w.writeConfig('fontFamily', 'Inter');"
        CLOCK_JS+="w.writeConfig('fontSize', $CLOCK_SIZE);"
        CLOCK_JS+="w.writeConfig('fontWeight', 500);"
        CLOCK_JS+="w.writeConfig('dateDisplayFormat', 'BesideTime');"
    fi
    # The macOS menu bar shows weekday, month and day beside the time — "Mon Apr
    # 1 09:42 AM" in the US, "lun. 1 avr. 09:42" in Belgium. Qt translates ddd
    # and MMM on its own but keeps the order it is given, so read that off the
    # short date format of the locale. That locale is the one plasmashell runs
    # with, not the one in plasma-localerc: the region settings only reach Qt
    # once the session exports them, so ask the process itself when it is up.
    macos_date_format() {
        local pid vars loc order
        pid="$(pgrep -u "$UID" -x plasmashell | head -n1)"
        if [[ -n "$pid" && -r "/proc/$pid/environ" ]]; then
            vars="$(tr '\0' '\n' < "/proc/$pid/environ")"
        else
            vars="$(env)"
        fi
        for key in LC_ALL LC_TIME LANG; do
            loc="$(grep -m1 "^$key=" <<< "$vars")" && break
        done
        order="$(LC_ALL="${loc#*=}" locale d_fmt 2>/dev/null \
                 | sed 's|%F|%Y-%m-%d|g; s|%D|%m/%d/%y|g' \
                 | grep -o '%-\?[a-zA-Z]' | tr -d '%-' | tr -cd 'dem')"
        # 'd'/'e' first means day before month (fr, de), 'm' first the reverse
        # (en_US, ja); an unknown locale falls back to the US order.
        case "${order:0:1}" in
            d|e) echo 'ddd d MMM' ;;
            *)   echo 'ddd MMM d' ;;
        esac
    }
    case "$CLOCK_DATE" in
        locale) ;;
        macos)  CLOCK_JS+="w.writeConfig('dateFormat', 'custom');w.writeConfig('customDateFormat', '$(macos_date_format)');"
                # the date belongs on the time's line, whatever the font size
                CLOCK_JS+="w.writeConfig('dateDisplayFormat', 'BesideTime');" ;;
        eu)     CLOCK_JS+="w.writeConfig('dateFormat', 'custom');w.writeConfig('customDateFormat', 'dd/MM/yy');" ;;
        iso)    CLOCK_JS+="w.writeConfig('dateFormat', 'isoDate');" ;;
        *)      CLOCK_JS+="w.writeConfig('dateFormat', 'custom');w.writeConfig('customDateFormat', '$CLOCK_DATE');" ;;
    esac
    [[ "$CLOCK_24H" == "yes" ]] && CLOCK_JS+="w.writeConfig('use24hFormat', 2);"
    if [[ -n "$CLOCK_JS" ]]; then
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            var pl = panels();
            for (var i = 0; i < pl.length; i++) {
                if (pl[i].location != 'top') continue;
                var ws = pl[i].widgets();
                for (var j = 0; j < ws.length; j++) {
                    if (ws[j].type == 'org.kde.plasma.digitalclock') {
                        var w = ws[j];
                        w.currentConfigGroup = ['Appearance'];
                        $CLOCK_JS
                        w.reloadConfig();
                    }
                }
            }
        "
    fi
fi

# ── Clipboard manager (Klipper) ─────────────────────────────────────────────
# The clipboard applet lives inside the system tray's own containment, which
# plasmashell scripting cannot reach — so opting out edits the panel config
# directly (with plasmashell stopped, or it would overwrite the file on exit).

if [[ "$CLIPBOARD" == "no" ]]; then
    info "Removing the clipboard manager from the system tray..."
    APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    systemctl --user stop plasma-plasmashell 2>/dev/null || true
    python3 - "$APPLETSRC" <<'EOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

# Containment ids whose plugin is the system tray
tray_ids, section = set(), None
for line in lines:
    m = re.match(r'\[Containments\]\[(\d+)\]\n?$', line)
    if m:
        section = m.group(1)
    elif line.startswith('['):
        section = None
    elif section and line.strip() == 'plugin=org.kde.plasma.private.systemtray':
        tray_ids.add(section)

CLIP = 'org.kde.plasma.clipboard'
out, in_general, seen_hidden = [], None, set()
for line in lines:
    m = re.match(r'\[Containments\]\[(\d+)\]\[General\]\n?$', line)
    if m and m.group(1) in tray_ids:
        in_general = m.group(1)
        out.append(line)
        continue
    if line.startswith('['):
        if in_general and in_general not in seen_hidden:
            out.append(f'hiddenItems={CLIP}\n')
            seen_hidden.add(in_general)
        in_general = None
        out.append(line)
        continue
    if in_general:
        key = line.split('=', 1)[0]
        if key in ('extraItems', 'knownItems'):
            items = [i for i in line.split('=', 1)[1].strip().split(',') if i and i != CLIP]
            out.append(f'{key}={",".join(items)}\n')
            continue
        if key == 'hiddenItems':
            items = [i for i in line.split('=', 1)[1].strip().split(',') if i]
            if CLIP not in items:
                items.append(CLIP)
            out.append(f'{key}={",".join(items)}\n')
            seen_hidden.add(in_general)
            continue
    out.append(line)
if in_general and in_general not in seen_hidden:
    out.append(f'hiddenItems={CLIP}\n')

with open(path, 'w') as f:
    f.writelines(out)
EOF
    systemctl --user start plasma-plasmashell 2>/dev/null || true
fi

# ── Apply ───────────────────────────────────────────────────────────────────

info "Applying the application style and theme..."
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$STYLE"

VARIANT=light
[[ "$MODE" == "dark" ]] && VARIANT=dark
plasma-apply-lookandfeel -a "org.debianedara.$VARIANT" 2>/dev/null || true
FORCE=1 "$HOME/.local/bin/debianedara-mode" "$MODE"
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true

# ── Remember the answers ────────────────────────────────────────────────────
# Read back as the defaults of the next run, so an update is just
# `bash install.sh` and Enter through the questions.

cat > "$ANSWERS" <<EOF
# Debianedara — the answers of the last install, used as the defaults of the
# next one. Environment variables still win over anything in here.
WALLPAPER="$WALLPAPER"
LOCKSCREEN="$LOCKSCREEN"
STYLE="$STYLE"
ICONS="$ICONS"
BUTTONS_LEFT="$BUTTONS_LEFT"
MACOS_LAYOUT="$MACOS_LAYOUT"
HIDE_XWVB="$HIDE_XWVB"
CYCLE="$CYCLE"
KONSOLE="$KONSOLE"
CLIPBOARD="$CLIPBOARD"
DIRCOLORS="$DIRCOLORS"
DRACULA="$DRACULA"
CLOCK_SIZE="${CLOCK_SIZE:-auto}"
CLOCK_DATE="$CLOCK_DATE"
CLOCK_24H="$CLOCK_24H"
MODE="$MODE"
LAYOUT_APPLIED="${LAYOUT_APPLIED:-no}"
EOF

echo
info "Done! Debianedara is installed."

if ((${#KEPT[@]})); then
    echo
    warn "Left untouched because they had local changes (new version beside them as *.new):"
    for f in "${KEPT[@]}"; do echo "     $f"; done
    echo "     Compare with: diff <file> <file>.new     Reinstall from scratch: OVERWRITE=yes bash install.sh"
fi
echo "
  Switch modes any time:   debianedara-mode light|dark|auto
  Change what a mode does: \$EDITOR ~/.config/debianedara/theme.conf
                           then: FORCE=1 debianedara-mode light|dark
  Change the app style:    debianedara-style           # lists what is available
                           debianedara-style breeze
  Toggle the cycle:        systemctl --user enable|disable --now debianedara.timer
  Restore panel layout:    cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup \\
                              ~/.config/plasma-org.kde.plasma.desktop-appletsrc && systemctl --user restart plasma-plasmashell
  Log out and back in for every application to pick up the fonts and style.

  Wallpaper source: https://wallhaven.cc/w/mlgmjm (see the page for author and license).
"
