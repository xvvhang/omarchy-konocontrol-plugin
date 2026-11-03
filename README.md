# Konocontrol

A native control center for Omarchy. Part of [Konochi](https://github.com/xvvhang/konochi),
a collection of native Omarchy plugins.

## Screenshot

[<img src="preview.png" alt="Konocontrol with Media, Quick Actions, and native controls" width="420">](preview.png)

## Features

- Collect built-in bar widgets into one panel, or restore them to the bar.
- Scrollable **Media → Quick Actions → Controls** sections with native actions
  and detail panels.
- Standalone media controls, audio and microphone cards, and compact Menu,
  Indicators, and keyboard-layout actions. Single keyboard layouts auto-hide.
- Escape from a detail panel returns to the control center and restores its
  scroll position; clicking outside dismisses it.
- Collected System Update appears in Quick Actions only when updates are pending;
  its native update indicator also remains visible in the bar while pending.
- Collect the native Elsewhen world clock (`omarchy.elsewhen`) as a **World Clock**
  control, opening its existing city clocks and globe panel without duplicating
  its settings or data sources.

## Installation

Requires **Omarchy Quattro** and its native shell widgets.

```sh
omarchy plugin add https://github.com/xvvhang/omarchy-konocontrol-plugin --enable
```

## Usage

Left-click the bar icon to open the control center. Right-click it, or select
**Configure**, to choose which widgets are collected. Changes save automatically.
Click a control to open its native panel; right-click Microphone to toggle mute.

Only existing, enabled **built-in Omarchy widgets** are supported. Tray and
third-party plugins stay in the bar. Keep collected widgets in `bar.layout`:
Konocontrol moves their existing instances rather than replacing them.

This plugin depends on Omarchy's native shell internals; future shell changes,
vertical bars, and multi-monitor setups may require compatibility updates.

### World Clock

On shells with Elsewhen, keep `omarchy.elsewhen` enabled in `bar.layout` and
choose **Configure → World Clock → Control center**. Click its card to open the
native panel. Escape first unwinds the clock's own search, shifted time or globe
view; when the panel closes through Escape, it returns to the control center.
Switch the placement back to **Bar** to restore the original world-clock button.

World Clock is included in the default collection for new configurations only;
existing saved placement choices are preserved. Shells without Elsewhen simply
omit it. City settings and any network requests remain managed by the native
widget; see Omarchy's world-clock documentation for its data sources.

### Omarchy RC compatibility

Supports the split `ModuleSlot` / `WidgetHost` bar layout in Omarchy 4.5.0rc3
as well as the earlier combined slots. Collected widgets release their bar
layout space and restore their original loader anchors when returned to Bar.
Quick Actions follows the native indicator list rather than hardcoding removed
indicators; available actions depend on the installed Omarchy version.

If an update still shows an empty control center, run `omarchy restart shell`
once: plugin rescanning can retain cached QML components.

Discovery regression checks (development only, requires Node.js):

```sh
node test_compat.cjs
omarchy plugin validate .
```

## Removal

In **Configure**, switch collected widgets back to **Bar**, then run:

```sh
omarchy plugin remove konochi.konocontrol
```

## License

[MIT](LICENSE). Built for [Omarchy](https://omarchy.org/) and
[Quickshell](https://quickshell.org/); an independent community plugin.
