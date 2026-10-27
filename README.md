<p align="center">
  <img src="docs/assets/brand/banner.png" alt="openbox-island" width="100%">
</p>

<p align="center">
  <strong>A Dynamic Island–style notch for Openbox, built with eww.</strong>
</p>

<p align="center">
  <a href="https://github.com/ardzz/openbox-island/actions/workflows/ci.yml"><img src="https://github.com/ardzz/openbox-island/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Openbox-window%20manager-3c3c3c" alt="Openbox">
  <img src="https://img.shields.io/badge/X11-only-f28834" alt="X11">
  <img src="https://img.shields.io/badge/eww-0.5-3ee6c4" alt="eww 0.5">
  <img src="https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/Python-3-3776AB?logo=python&logoColor=white" alt="Python 3">
  <img src="https://img.shields.io/badge/Arch%20Linux-1793D1?logo=archlinux&logoColor=white" alt="Arch Linux">
</p>

<p align="center">
  <a href="#highlights">Features</a> ·
  <a href="#gallery">Gallery</a> ·
  <a href="#install">Install</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#documentation">Docs</a>
</p>

<p align="center">
  <img src="docs/assets/live/live-demo.gif" alt="openbox-island on a real Openbox desktop: compact pill, card opening, switching tabs, collapsing" width="100%">
</p>

<p align="center">
  <img src="docs/assets/live/live-desktop.png" alt="The expanded card on the Music tab below the top bar" width="100%">
</p>

openbox-island sits at the top edge of monitor 0 like a notch: a 508×44 px compact pill that grows into a 508×218 px tabbed card. It shows what is playing, takes over dunst notifications, flashes short alerts for hardware and network changes, and keeps weather, a to-do list, shortcuts and AI plan quotas one hover away.

## Highlights

**Now playing**
- YouTube Music only: [ytm-player](https://ytm-player.com) and ytermusic, plus Microsoft Edge when the bundled `browser/ytm-bridge` extension confirms the track comes from a `music.youtube.com` tab. Regular YouTube, other web media and other MPRIS players are ignored. Priority order is configurable (default `ytm_player,ytermusic,edge`).
- The Music tab has **Player**, **Lirik** and **Output** modes. Lirik shows up to six lyric lines around the current one; clicking a synced line seeks to it. Output lists audio sinks, and clicking one makes it the default and moves every playing stream to it.
- The Music tab background is tinted with the cover's dominant colour; grey covers keep the default background.
- Synced lyrics from LRCLIB with NetEase Cloud Music as a fallback; for ytm-player, YouTube Music lyrics are tried first.
- A real audio spectrum visualizer, processed at the island monitor's refresh rate and fed only by the active player's own output stream.
- Like/dislike buttons and an "up next" line for ytm-player.
- A grey skeleton keeps the music layout in place while the player switches tracks.
- Bluetooth or wired headphones show an icon on the pill, and the Music tab shows the device name and battery level.

**Notifications**
- Every dunst notification, critical ones included, appears in the island instead of a dunst popup; critical notifications get a red accent.
- Clicking a notification dismisses it and focuses or launches its app.
- A Notifications tab works as a notification center built on dunst history; an accent dot on its tab icon marks notifications you have not seen yet.

**Alerts**
- Temporary pill alerts for volume and mute, microphone, audio output switch, brightness, charging, battery (including Lenovo conservation mode), low battery, Wi-Fi, Bluetooth, VPN and Tailscale, new screenshots (with a thumbnail), CPU/GPU temperature, Caps Lock, and ACPI power profile.

**Tabs**
- The expanded card has **Music**, **Kalender**, **Weather**, **Notifications**, **To-do**, **Shortcuts** and **Kuota** tabs. The tab header shows one icon per tab; the selected tab adds its name and an accent count badge (events left today, notifications, open to-dos). Each tab appears only while it has content; To-do is always available and supports optional deadlines — set in an in-card date picker (month calendar, time steppers and presets) — with reminders the day before and on the day.
- Kalender lists iCal events — or Google Calendar API accounts (`google:<calendarId>`, see below) — from today through the next 30 days, with account colours, all-day summaries, Join buttons and meeting reminders.
- Meeting prep templates turn recurring meetings into To-do items before each occurrence: a `Prep N/M` chip on the Kalender tab, `· Prep N/M` on the left pill, and a reminder body that names unfinished prep.
- Kuota shows AI plan usage read from the local `omp usage` command (Codex, Claude, Copilot and the other providers omp reports): each account's limit windows with the percentage used and a reset countdown, refreshed every 5 minutes while the card is open. Providers listed in `ISLAND_KUOTA_SKIP` are hidden (default `google-antigravity`). The island only reads `omp usage`; without `omp` the tab stays hidden.

**Indicators**
- Dots on the pill for screen recording (red, with elapsed time), microphone in use (yellow) and camera in use (green), plus a crossed-out bell while dunst Do Not Disturb is on.

**Smart behaviour**
- Hides while a fullscreen window covers the island's monitor.
- Expands after the pointer rests on it for 0.3 s.
- Expands for 4 s on track change, then collapses.
- Scrolling over the compact pill changes the default output volume by ±5%.

**Left pill**
- A second, smaller pill in the top-left corner always shows the meeting to mind from the Kalender agenda — `sampai HH:MM` while it runs, a yellow `Nm` countdown (with **Join**) in the 15 minutes before it starts, its start time later today, or the day and time of the next meeting on a later day (e.g. `Besok 09:00`, `Sen 26 Okt 09:00`) — next to the nearest open To-do deadline with the same chip label as the To-do tab (red `terlambat` when overdue, yellow under 24 h, plus `+N` for other deadlines due within 24 h). With neither, it reads `Kosong hari ini`. Clicking the meeting opens the Kalender tab, clicking the deadline opens the To-do tab; a click whose tab is unavailable (no calendar configured yet) opens nothing. The pill hides and returns with the island in fullscreen.

<p align="center">
  <img src="docs/assets/screenshots/pill-upcoming.png" alt="Left pill: upcoming meeting with Join and nearest deadline" width="400">
</p>

Full behaviour reference: [docs/fitur.md](docs/fitur.md) (Indonesian).

## Demo

<p align="center">
  <img src="docs/assets/demo.gif" alt="Rendered demo: music pill with visualizer, card tabs, volume alert, notification" width="520">
  <br>
  <sub>Rendered from sample data with <code>tools/showcase</code>: music pill, card tabs Music → Weather → Notifications → To-do → Shortcuts, a volume alert and an email from Linus Torvalds.</sub>
</p>

## Gallery

All images below are rendered from sample states in `tools/samples/`.

### Cards

<table>
  <tr><th colspan="2">Music</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-music-ytm.png" alt="Music card with ytm-player" width="400"><br><sub>ytm-player: like/dislike and up next</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-music-plain.png" alt="Music card without like buttons" width="400"><br><sub>ytermusic or Edge via the bridge</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-music-lyrics.png" alt="Music card in Lirik mode" width="400"><br><sub>Lirik mode: synced lines, click to seek</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-music-output.png" alt="Music card in Output mode" width="400"><br><sub>Output mode: switch the audio sink</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-music-loading.png" alt="Music card skeleton" width="400"><br><sub>Skeleton between tracks</sub></td>
    <td></td>
  </tr>
  <tr><th colspan="2">Weather</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-weather.png" alt="Weather card, day" width="400"><br><sub>Day</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-weather-night.png" alt="Weather card, night" width="400"><br><sub>Night</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-weather-rain.png" alt="Weather card, rain" width="400"><br><sub>Rain</sub></td>
    <td></td>
  </tr>
  <tr><th colspan="2">Notifications</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-notif.png" alt="Notification center" width="400"><br><sub>Notification center</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-notif-critical.png" alt="Notification center with a critical notification" width="400"><br><sub>Critical notification</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-notif-scrolled.png" alt="Notification center scrolled" width="400"><br><sub>Scrolled to older notifications</sub></td>
    <td></td>
  </tr>
  <tr><th colspan="2">Kalender</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-kalender.png" alt="Calendar agenda with all-day events and meeting links" width="400"><br><sub>Today's agenda and meeting links</sub></td>
    <td></td>
  </tr>
  <tr><th colspan="2">To-do</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-todo.png" alt="To-do list" width="400"><br><sub>List</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-todo-full.png" alt="Full to-do list" width="400"><br><sub>Full list with “+N more”</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-todo-empty.png" alt="Empty to-do list" width="400"><br><sub>Empty</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-todo-picker.png" alt="Deadline picker in the To-do tab" width="400"><br><sub>Deadline picker</sub></td>
  </tr>
  <tr><th colspan="2">Shortcuts</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-shortcuts.png" alt="Shortcuts" width="400"><br><sub>Shortcuts</sub></td>
    <td align="center"><img src="docs/assets/screenshots/card-shortcuts-dnd.png" alt="Shortcuts with Do Not Disturb on" width="400"><br><sub>Do Not Disturb on</sub></td>
  </tr>
  <tr><th colspan="2">Kuota</th></tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/card-kuota.png" alt="Kuota tab with AI plan usage per account" width="400"><br><sub>Usage bars and reset countdowns per account</sub></td>
    <td></td>
  </tr>
</table>

### Compact pill

<table>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-music.png" alt="Music pill" width="100%"><br><sub>Music with lyrics and visualizer</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-music-paused.png" alt="Paused music pill" width="100%"><br><sub>Paused</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-music-wired.png" alt="Music pill with wired headphones" width="100%"><br><sub>Wired headphones</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-loading.png" alt="Loading pill" width="100%"><br><sub>Loading between tracks</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-indicators.png" alt="Pill with activity indicators" width="100%"><br><sub>Activity indicators</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-idle.png" alt="Idle pill with weather" width="100%"><br><sub>Idle with weather</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-notify.png" alt="Notification pill" width="100%"><br><sub>Notification</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-notify-critical.png" alt="Critical notification pill" width="100%"><br><sub>Critical notification</sub></td>
  </tr>
</table>

### Alerts

<details>
<summary>Show all 14 alerts</summary>

<table>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-volume.png" alt="Volume alert" width="100%"><br><sub>Volume</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-brightness.png" alt="Brightness alert" width="100%"><br><sub>Brightness</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-mic-muted.png" alt="Microphone muted alert" width="100%"><br><sub>Microphone muted</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-output.png" alt="Audio output alert" width="100%"><br><sub>Audio output switch</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-battery-low.png" alt="Low battery alert" width="100%"><br><sub>Low battery</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-charging.png" alt="Charging alert" width="100%"><br><sub>Charging</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-conservation.png" alt="Battery conservation alert" width="100%"><br><sub>Battery conservation mode</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-power.png" alt="Power profile alert" width="100%"><br><sub>Power profile</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-bluetooth.png" alt="Bluetooth alert" width="100%"><br><sub>Bluetooth</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-wifi.png" alt="Wi-Fi alert" width="100%"><br><sub>Wi-Fi</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-vpn.png" alt="VPN alert" width="100%"><br><sub>VPN</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-temp.png" alt="Temperature alert" width="100%"><br><sub>Temperature</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-capslock.png" alt="Caps Lock alert" width="100%"><br><sub>Caps Lock</sub></td>
    <td align="center"><img src="docs/assets/screenshots/pill-alert-shot.png" alt="Screenshot alert" width="100%"><br><sub>Screenshot with thumbnail</sub></td>
  </tr>
</table>

</details>

## Install

Requires an Openbox session on X11 with eww 0.5 and dunst.

```bash
git clone https://github.com/ardzz/openbox-island.git && cd openbox-island
sudo pacman -S --needed playerctl jq curl xdotool xorg-xprop xorg-xrandr cava pipewire-audio libpulse inotify-tools python dbus light upower networkmanager inter-font ttf-nerd-fonts-symbols
ln -s "$PWD/eww" ~/.config/eww-island
ln -s "$PWD/openbox/island.sh" ~/.config/openbox/island.sh
```

The visualizer also needs an active PipeWire session with `pipewire-pulse`. The Music tab cover tint optionally needs ImageMagick: `magick` (ImageMagick 7, Arch package `imagemagick`) or `convert` (ImageMagick 6, e.g. Ubuntu); without either, the tab is not tinted.

To show YouTube Music played in Microsoft Edge, load `browser/ytm-bridge` as an unpacked extension at `edge://extensions`, copy its extension ID, run `browser/ytm-bridge/install.sh <extension-id>`, then reload the extension and the YouTube Music tab. See [Edge bridge setup](docs/konfigurasi.md#bridge-youtube-music-untuk-edge).

Kalender optionally needs `python-icalendar` and `python-recurring-ical-events` (Arch packages). See [calendar setup](docs/fitur.md#menyiapkan-kalender) for the private iCal configuration, or for Google Calendar API accounts (`google:<calendarId>` with a one-time `agenda login NAME`) as an alternative to iCal.

Kuota optionally needs the `omp` CLI, logged in to your AI providers; without it the tab stays hidden. See [Kuota](docs/fitur.md#kuota).

**Start and stop**

```bash
~/.config/openbox/island.sh        # start (or restart) the island
~/.config/openbox/island.sh stop   # stop only the island daemon; safe to repeat
```

`openbox/eww.sh` from openbox-omp starts the island automatically every time the eww bar opens, including theme switches.

Full setup is in [docs/konfigurasi.md](docs/konfigurasi.md). It covers optional dependencies, the picom shadow rule, bar palette, player priority, the Edge YouTube Music bridge, ytm-player login, shortcuts, dunst integration, weather location and environment variables. The docs are in Indonesian for now; English versions are coming.

## Architecture

The island is a separate eww configuration (`~/.config/eww-island`) with three windows: the `island` pill, the `island-expanded` card and the top-left `island-upcoming` pill. Data flows from **listeners → eww variables → yuck**: each `deflisten` runs one script that prints a JSON line per change, and widgets render those variables. User actions call scripts that update state and signal the listeners through FIFOs or `eww update`. Shared shell framework lives in `eww/scripts/lib/`: `core`, `store` (locked atomic JSON), `paged` (scrolling windows), `listener` (FIFO-driven loops) and `monitor` (event monitors and workers). Tabs come from a numbered registry in `eww/scripts/lib/tabs/`, and `tools/` holds the lint gate, preview renderer and showcase generator.

```mermaid
flowchart LR
  L[openbox/island.sh] --> D[eww daemon]
  D -->|deflisten| S[listener scripts]
  S -->|JSON line| D
  D --> W[yuck: island / island-expanded / island-upcoming]
  W -->|onclick / onscroll / onhover| C[action scripts]
  C -->|FIFO signal| S
  C -->|eww update| D
  DU[dunst] -->|notify-hook| S
```

Details, area contracts and recipes for adding a tab, alert or listener: [docs/architecture.md](docs/architecture.md) (Indonesian).

## Development

```bash
bats -r tests/                                          # 442 bats tests
python3 -m unittest discover -s tests -p 'test_*.py'    # 65 Python tests
tools/check                                             # file-size gate + shellcheck + py_compile
```

`tools/check` warns above 200 lines and fails above 300 lines per tracked file in `eww/`, `openbox/`, `tools/` and `tests/`, runs `shellcheck` on bash scripts and `py_compile` on Python. CI runs all three on every push and pull request.

```bash
tools/preview eww tools/samples/card-todo.vars /tmp/card-todo.png   # render one window from a sample
tools/showcase docs/assets                                          # regenerate the gallery and demo.gif
```

## Documentation

| Page | Contents | Language |
| --- | --- | --- |
| [Features](docs/fitur.md) | Pill and card, tabs, YouTube Music (Player, Lirik and Output modes), visualizer, lyrics, alerts, notifications, indicators, weather, to-do, shortcuts, AI quota | Indonesian |
| [Configuration](docs/konfigurasi.md) | Dependencies, start/stop, picom, palette, players, Edge YouTube Music bridge, dunst integration, weather location, environment variables (including `ISLAND_KUOTA_INTERVAL` and `ISLAND_KUOTA_SKIP`) | Indonesian |
| [Debugging and tests](docs/debug.md) | Running tests and previews, logs and runtime state, known limitations, troubleshooting | Indonesian |
| [Architecture](docs/architecture.md) | Data flow, folder layout, shell framework, area contracts, recipes | Indonesian |

## License

[MIT](LICENSE) © 2026 Naufal Reky Ardhana
