# Debianedara

An elegant KDE Plasma 6 theme with a deep-space identity, built for
**Debian 13 (trixie) + Plasma 6.3** — light and dark variants, a luminous
nebula-blue accent, and an optional macOS-like layout.

[![Debianedara desktop — dark mode, macOS-like layout](assets/desktop-example-preview.jpg)](assets/desktop-example.png)

*Dark mode with the macOS-like layout: thin top bar, centered floating dock —
click for full resolution.*

## What you get

- **Two color schemes** — *Debianedara Dark* (deep-space navy, `#0B0E17`–`#10131E`)
  and *Debianedara Light* (cool paper whites), both accented with nebula blue
- **Two global themes** (Look and Feel packages) selectable in System Settings
- **Matching Kvantum widget themes** — flat & modern, blurred translucent menus,
  derived from KvFlat at install time
- **Nebula wallpaper** (downloaded from [wallhaven](https://wallhaven.cc/w/mlgmjm)),
  applied to the desktop and lock screen — or bring your own image
- **Inter** as the system font
- **Optional macOS-like layout** — thin translucent top bar (app launcher,
  global menu, system tray, clock) + centered floating dock, window buttons
  on the left in macOS order
- **Optional day/night cycle** — light 07:00–19:00, dark otherwise, driven by
  a systemd user timer; switches colors, icons, Kvantum theme in one go
- **Tela-circle icons** (optional, cloned from the
  [official repo](https://github.com/vinceliuice/Tela-circle-icon-theme))
- A KWin rule that hides the
  [Xwayland Video Bridge ghost window](https://bugs.kde.org/show_bug.cgi?id=473946)
  (the 1×1 px artifact visible at the screen edge)
- **Optional Konsole theme** — the [Dracula](https://draculatheme.com) color
  scheme and profile (with the Hack font), set as the default profile
- **Optional editor theme** — the official
  [Dracula extension](https://marketplace.visualstudio.com/items?itemName=dracula-theme.theme-dracula)
  installed into VS Code and/or VSCodium when detected

## Install

```sh
bash <(curl -sL https://raw.githubusercontent.com/Nedara-Project/debianedara/main/install.sh)
```

Run as your normal user — `sudo` is only invoked for `apt`. The script asks a
few questions (wallpaper, icons, layout, cycle, initial mode); every answer
can be preseeded for a non-interactive install:

```sh
WALLPAPER=nebula ICONS=yes BUTTONS_LEFT=yes MACOS_LAYOUT=yes \
HIDE_XWVB=yes CYCLE=no MODE=dark bash install.sh
```

| Variable       | Values                          | Default  | What it does                                  |
|----------------|---------------------------------|----------|-----------------------------------------------|
| `WALLPAPER`    | `nebula`, path/URL, `skip`      | `nebula` | Wallpaper to install                           |
| `ICONS`        | `yes` / `no`                    | `yes`    | Install Tela-circle icon themes                |
| `BUTTONS_LEFT` | `yes` / `no`                    | `yes`    | Window buttons on the left (close/min/max)     |
| `MACOS_LAYOUT` | `yes` / `no`                    | `yes`    | Top bar + centered floating dock               |
| `HIDE_XWVB`    | `yes` / `no`                    | `yes`    | Hide the Xwayland Video Bridge ghost window    |
| `CYCLE`        | `yes` / `no`                    | `no`     | Automatic day/night switching                  |
| `KONSOLE`      | `yes` / `no`                    | `yes`    | Dracula color scheme + profile for Konsole     |
| `DRACULA`      | `yes` / `no`                    | `yes`*   | Dracula extension for VS Code/VSCodium         |
| `CLOCK_SIZE`   | `8`–`24` or `auto`              | `15`†    | Top bar clock font size (one-line date+time)   |
| `CLOCK_DATE`   | `locale` / `eu` / `iso` / custom| `locale`†| Clock date format (`eu` = dd/MM/yy; custom = any [Qt format](https://doc.qt.io/qt-6/qdate.html#toString)) |
| `CLOCK_24H`    | `yes` / `locale`                | `locale`†| Force 24-hour time on the clock                |
| `MODE`         | `dark` / `light` / `auto`       | `dark`   | Mode applied at the end of the install         |

\* only offered when `code` or `codium` is found on the machine.
† only asked/applied with `MACOS_LAYOUT=yes` (they configure the top bar clock).

Log out and back in afterwards so every application picks up the fonts and
widget style.

## Daily use

```sh
debianedara-mode dark     # switch to dark
debianedara-mode light    # switch to light
debianedara-mode auto     # pick by time of day (light 07:00-19:00)

systemctl --user enable --now debianedara.timer    # turn the cycle on
systemctl --user disable --now debianedara.timer   # turn it off
```

## Uninstall

```sh
systemctl --user disable --now debianedara.timer 2>/dev/null
rm -rf ~/.local/share/color-schemes/Debianedara*.colors \
       ~/.local/share/plasma/look-and-feel/org.debianedara.* \
       ~/.config/Kvantum/Debianedara* \
       ~/.local/share/wallpapers/debianedara-space.png \
       ~/.local/bin/debianedara-mode \
       ~/.config/systemd/user/debianedara.* \
       ~/.config/autostart/debianedara.desktop
# then pick another Global Theme in System Settings, and restore the panel
# layout backup if you applied the macOS layout:
#   cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc.debianedara-backup \
#      ~/.config/plasma-org.kde.plasma.desktop-appletsrc
#   systemctl --user restart plasma-plasmashell
```

## Notes

- Plasma 6.3 has no native day/night theme switching (it landed in 6.4),
  which is why the cycle is a systemd user timer.
- Kvantum window translucency does not work on Wayland; this theme keeps
  windows opaque and only makes menus/popups translucent (which does work).
- The global menu in the top bar only fills in for applications that export
  their menu (KDE/Qt apps do; Chrome, Electron and most GTK apps do not).
## Credits

- **Wallpaper**: mirrored in [`assets/`](assets/) so the theme keeps working if
  the source goes away — original found on
  [wallhaven (mlgmjm)](https://wallhaven.cc/w/mlgmjm); all rights remain with
  its author, see the source page for details.
- **[Dracula](https://draculatheme.com)** Konsole scheme and editor extension —
  MIT licensed, by Zeno Rocha and contributors.
- **[Tela-circle icons](https://github.com/vinceliuice/Tela-circle-icon-theme)**
  by vinceliuice, cloned from the official repository at install time.
- **[Kvantum](https://github.com/tsujan/Kvantum)** by Tsu Jan — the Debianedara
  widget themes are generated locally from its KvFlat/KvFlatLight themes.

## License

MIT — see [LICENSE](LICENSE). The Kvantum themes are generated locally from
KvFlat/KvFlatLight (part of the GPL-licensed
[Kvantum](https://github.com/tsujan/Kvantum) themes package) and are not
redistributed here.
