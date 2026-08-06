#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Debianedara — an elegant KDE Plasma 6 theme with a deep-space identity
#
# Light + dark color schemes with a luminous nebula-blue accent, matching
# Kvantum widget themes (flat, blurred translucent menus), a nebula wallpaper,
# Inter as the system font, an optional macOS-like layout (thin top bar with
# global menu + centered floating dock), and an optional day/night auto cycle.
#
# Target:  Debian 13 (trixie) with KDE Plasma 6.3 on Wayland.
#          Should work on any Plasma 6.x, but only tested there.
#
# Usage:   bash install.sh
#          Run as your normal user (sudo is only invoked for apt).
#          Every choice can be preseeded via environment variables, e.g.:
#          WALLPAPER=nebula ICONS=yes MACOS_LAYOUT=yes BUTTONS_LEFT=yes \
#          CYCLE=no KONSOLE=yes DRACULA=yes CLOCK_SIZE=15 CLOCK_DATE=eu \
#          CLOCK_24H=yes MODE=dark bash install.sh
#
# What it touches (all user-level, nothing outside $HOME except apt):
#   ~/.local/share/color-schemes/Debianedara{Light,Dark}.colors
#   ~/.local/share/plasma/look-and-feel/org.debianedara.{light,dark}/
#   ~/.config/Kvantum/Debianedara{Light,Dark}/   + kvantum.kvconfig
#   ~/.local/share/wallpapers/debianedara-space.png
#   ~/.local/bin/debianedara-mode
#   ~/.config/systemd/user/debianedara.{service,timer}
#   ~/.config/autostart/debianedara.desktop        (only if cycle enabled)
#   ~/.config/kdeglobals, kwinrulesrc, kscreenlockerrc (via kwriteconfig6)
#   Panel layout via plasmashell scripting          (only if chosen)
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

# Where the repository's own assets live (wallpaper mirror, Konsole themes)
RAW_BASE="https://raw.githubusercontent.com/Nedara-Project/debianedara/main"

PLASMA_VERSION=$(plasmashell --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
info "Detected Plasma $PLASMA_VERSION"
[[ "${PLASMA_VERSION%%.*}" == "6" ]] || warn "This theme targets Plasma 6.x — continuing anyway."

# ── Choices ─────────────────────────────────────────────────────────────────

echo
echo "Debianedara installer — answer a few questions (Enter = default):"
echo

# WALLPAPER: nebula (download) | path/URL to your own image | skip
if [[ -z "${WALLPAPER:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Wallpaper — 'nebula' to download the default (wallhaven, ~14 MB), a path/URL to your own image, or 'skip' [nebula]: " WALLPAPER || true
    fi
    WALLPAPER="${WALLPAPER:-nebula}"
fi
ask ICONS        "Install Tela-circle icon themes from GitHub (recommended)?"            yes
ask BUTTONS_LEFT "Move window buttons to the left, macOS order (close/min/max)?"         yes
ask MACOS_LAYOUT "Apply the macOS-like panel layout (thin top bar + centered dock)?"     yes
ask HIDE_XWVB    "Hide the Xwayland Video Bridge ghost window (fixes edge artifact)?"    yes
ask CYCLE        "Enable the automatic day/night cycle (light 07:00-19:00)?"             no
ask KONSOLE      "Install the Dracula color scheme and profile for Konsole?"             yes
ask CLIPBOARD    "Keep the clipboard manager (Klipper) in the system tray?"              yes
if command -v code >/dev/null || command -v codium >/dev/null; then
    ask DRACULA  "Install the Dracula theme extension in VS Code/VSCodium?"              yes
else
    DRACULA=no
fi
if [[ -z "${MODE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Initial mode — 'dark', 'light' or 'auto' [dark]: " MODE || true
    fi
    MODE="${MODE:-dark}"
fi
# Clock font size in the top bar (macOS layout only): a point size, or 'auto'
# to keep Plasma's automatic two-line sizing.
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_SIZE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Top bar clock font size (8-24, or 'auto') [15]: " CLOCK_SIZE || true
    fi
    CLOCK_SIZE="${CLOCK_SIZE:-15}"
fi
CLOCK_SIZE="${CLOCK_SIZE:-auto}"
if [[ "$CLOCK_SIZE" != "auto" ]] && ! [[ "$CLOCK_SIZE" =~ ^[0-9]+$ && "$CLOCK_SIZE" -ge 8 && "$CLOCK_SIZE" -le 24 ]]; then
    warn "Invalid clock size '$CLOCK_SIZE' — using 15."
    CLOCK_SIZE=15
fi
# Date format shown by the clock: 'locale' keeps the system default, 'eu' is
# day/month/year, 'iso' is year-month-day, anything else is a custom Qt
# date format string (https://doc.qt.io/qt-6/qdate.html#toString).
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_DATE:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Clock date format — 'locale', 'eu' (dd/MM/yy), 'iso', or custom [locale]: " CLOCK_DATE || true
    fi
    CLOCK_DATE="${CLOCK_DATE:-locale}"
fi
CLOCK_DATE="${CLOCK_DATE:-locale}"
# 24-hour time: 'locale' keeps the system default, 'yes' forces 24h.
if [[ "$MACOS_LAYOUT" == "yes" && -z "${CLOCK_24H:-}" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Force 24-hour time — 'yes' or 'locale' [locale]: " CLOCK_24H || true
    fi
    CLOCK_24H="${CLOCK_24H:-locale}"
fi
CLOCK_24H="${CLOCK_24H:-locale}"

echo
info "wallpaper=$WALLPAPER icons=$ICONS buttons-left=$BUTTONS_LEFT macos-layout=$MACOS_LAYOUT hide-xwvb=$HIDE_XWVB cycle=$CYCLE konsole=$KONSOLE clipboard=$CLIPBOARD dracula=$DRACULA clock-size=${CLOCK_SIZE:-auto} mode=$MODE"
echo

# ── Packages ────────────────────────────────────────────────────────────────

PKGS=(fonts-inter qt-style-kvantum qt-style-kvantum-themes)
[[ "$WALLPAPER" != "skip" || "$KONSOLE" == "yes" ]] && PKGS+=(curl)
[[ "$ICONS" == "yes" ]] && PKGS+=(git)
[[ "$KONSOLE" == "yes" ]] && PKGS+=(fonts-hack)
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
         "$HOME/.config/Kvantum"

# ── Wallpaper ───────────────────────────────────────────────────────────────

WALL="$HOME/.local/share/wallpapers/debianedara-space.png"
case "$WALLPAPER" in
    skip)
        warn "Wallpaper skipped — the theme will keep your current one."
        ;;
    nebula)
        info "Downloading the nebula wallpaper..."
        # Mirrored in this repository so the theme survives the source going
        # away; original: https://wallhaven.cc/w/mlgmjm
        curl -fL --retry 2 -o "$WALL" "$RAW_BASE/assets/debianedara-space.png" \
            || curl -fL --retry 2 -o "$WALL" "https://w.wallhaven.cc/full/ml/wallhaven-mlgmjm.png" \
            || warn "Download failed — wallpaper skipped, set one manually later."
        ;;
    http*)
        info "Downloading custom wallpaper..."
        curl -fL --retry 2 -o "$WALL" "$WALLPAPER" || warn "Download failed — wallpaper skipped."
        ;;
    *)
        [[ -f "$WALLPAPER" ]] && cp "$WALLPAPER" "$WALL" || warn "File not found: $WALLPAPER — wallpaper skipped."
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

cat > "$HOME/.local/share/color-schemes/DebianedaraDark.colors" <<'EOF'
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

cat > "$HOME/.local/share/color-schemes/DebianedaraLight.colors" <<'EOF'
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

info "Building Kvantum themes..."
[[ -d /usr/share/Kvantum/KvFlat ]] || die "KvFlat not found — is qt-style-kvantum-themes installed?"

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

# ── Global themes (Look and Feel packages) ──────────────────────────────────

info "Installing global themes..."
ICON_LIGHT=breeze; ICON_DARK=breeze-dark
[[ "$ICONS" == "yes" ]] && { ICON_LIGHT=Tela-circle; ICON_DARK=Tela-circle-dark; }

for v in light dark; do
    LNF="$HOME/.local/share/plasma/look-and-feel/org.debianedara.$v"
    mkdir -p "$LNF/contents/previews"
    if [[ "$v" == "light" ]]; then NAME="Debianedara Light"; SCHEME=DebianedaraLight; ICON=$ICON_LIGHT
    else NAME="Debianedara Dark"; SCHEME=DebianedaraDark; ICON=$ICON_DARK; fi

    cat > "$LNF/metadata.json" <<EOF
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

    cat > "$LNF/contents/defaults" <<EOF
[kdeglobals][KDE]
widgetStyle=kvantum

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
Image=$WALL
EOF

    if command -v magick >/dev/null && [[ -f "$WALL" ]]; then
        magick "$WALL" -resize 600x338 "$LNF/contents/previews/preview.png" 2>/dev/null || true
    fi
done

# ── Day/night switcher script ───────────────────────────────────────────────

info "Installing debianedara-mode..."
cat > "$HOME/.local/bin/debianedara-mode" <<'EOF'
#!/usr/bin/env bash
# Debianedara day/night switcher.
# Usage: debianedara-mode [auto|light|dark]   (default: auto — light 07:00-19:00)
set -u

MODE="${1:-auto}"
CHANGEICONS=$(ls /usr/lib/*/libexec/plasma-changeicons /usr/libexec/plasma-changeicons 2>/dev/null | head -1)

if [[ "$MODE" == "auto" ]]; then
    hour=$(date +%-H)
    if (( hour >= 7 && hour < 19 )); then MODE=light; else MODE=dark; fi
fi

case "$MODE" in
    light)
        SCHEME=DebianedaraLight
        ICONS=Tela-circle
        KVANTUM=DebianedaraLight
        ;;
    dark)
        SCHEME=DebianedaraDark
        ICONS=Tela-circle-dark
        KVANTUM=DebianedaraDark
        ;;
    *)
        echo "usage: debianedara-mode [auto|light|dark]" >&2
        exit 1
        ;;
esac

# One wallpaper for both modes: the nebula is the theme's identity.
WALL="$HOME/.local/share/wallpapers/debianedara-space.png"

# Skip if already in the right mode (avoids flicker when the timer fires)
current=$(grep -m1 '^ColorScheme=' "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2)
if [[ "$current" == "$SCHEME" && "${FORCE:-0}" != "1" ]]; then
    exit 0
fi

plasma-apply-colorscheme "$SCHEME"
if [[ -n "$CHANGEICONS" && -d "$HOME/.local/share/icons/$ICONS" ]]; then
    "$CHANGEICONS" "$ICONS"
fi
command -v kvantummanager >/dev/null && kvantummanager --set "$KVANTUM" >/dev/null 2>&1
if [[ -f "$WALL" ]]; then
    plasma-apply-wallpaperimage "$WALL"
    kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$WALL"
    kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "file://$WALL"
fi
EOF
chmod +x "$HOME/.local/bin/debianedara-mode"

# ── Day/night cycle units (installed always, enabled on request) ────────────

cat > "$HOME/.config/systemd/user/debianedara.service" <<'EOF'
[Unit]
Description=Debianedara day/night switch

[Service]
Type=oneshot
ExecStart=%h/.local/bin/debianedara-mode auto
EOF

cat > "$HOME/.config/systemd/user/debianedara.timer" <<'EOF'
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

# ── Konsole: Dracula color scheme and profile ───────────────────────────────
# https://draculatheme.com — MIT licensed, mirrored in this repository.

if [[ "$KONSOLE" == "yes" ]]; then
    info "Installing the Dracula Konsole theme..."
    mkdir -p "$HOME/.local/share/konsole"
    KONSOLE_OK=yes
    for f in "Dracula.colorscheme" "Dracula.profile" "Dracula Storm.colorscheme" "Dracula Storm.profile"; do
        curl -fL --retry 2 -o "$HOME/.local/share/konsole/$f" "$RAW_BASE/assets/konsole/${f// /%20}" \
            || { warn "Could not download $f"; KONSOLE_OK=no; }
    done
    if [[ "$KONSOLE_OK" == "yes" ]]; then
        kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Dracula.profile"
        info "Dracula set as the default Konsole profile."
    fi
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

if [[ "$MACOS_LAYOUT" == "yes" ]]; then
    info "Applying the macOS-like layout (backup: ~/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup)..."
    cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" \
       "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup" 2>/dev/null || true
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
    case "$CLOCK_DATE" in
        locale) ;;
        eu)  CLOCK_JS+="w.writeConfig('dateFormat', 'custom');w.writeConfig('customDateFormat', 'dd/MM/yy');" ;;
        iso) CLOCK_JS+="w.writeConfig('dateFormat', 'isoDate');" ;;
        *)   CLOCK_JS+="w.writeConfig('dateFormat', 'custom');w.writeConfig('customDateFormat', '$CLOCK_DATE');" ;;
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

info "Applying widget style and theme..."
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum

VARIANT=light
[[ "$MODE" == "dark" ]] && VARIANT=dark
plasma-apply-lookandfeel -a "org.debianedara.$VARIANT" 2>/dev/null || true
FORCE=1 "$HOME/.local/bin/debianedara-mode" "$MODE"
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true

echo
info "Done! Debianedara is installed."
echo "
  Switch modes any time:   debianedara-mode light|dark|auto
  Toggle the cycle:        systemctl --user enable|disable --now debianedara.timer
  Restore panel layout:    cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup \\
                              ~/.config/plasma-org.kde.plasma.desktop-appletsrc && systemctl --user restart plasma-plasmashell
  Log out and back in for every application to pick up the fonts and style.

  Wallpaper source: https://wallhaven.cc/w/mlgmjm (see the page for author and license).
"
