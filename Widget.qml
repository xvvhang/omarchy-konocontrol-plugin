import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "konochi.konocontrol"
  ipcTarget: "konochi.konocontrol"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property bool configuring: false
  property var slots: []
  property string saveError: ""
  property var returnOwner: null
  property var escapeOwner: null
  property real returnScrollY: 0
  property bool restoreScrollOnOpen: false
  readonly property var configSlots: slots.slice().sort(function(a, b) {
    var priority = {"omarchy.indicators": -2, "omarchy.system-update": -1}
    return (priority[a.moduleName] || 0) - (priority[b.moduleName] || 0)
      || root.label(a.moduleName).localeCompare(root.label(b.moduleName))
  })
  readonly property var collected: setting("collected", [
    "omarchy.audio", "omarchy.bluetooth", "omarchy.network", "omarchy.monitor", "omarchy.power"
  ]).filter(function(id) { return id.indexOf("omarchy.") === 0 && id !== "omarchy.tray" })
  readonly property color foreground: bar ? bar.foreground : "white"
  readonly property string textFont: bar ? bar.fontFamily : "monospace"
  readonly property var nativeIndicators: {
    for (var i = 0; i < slots.length; i++) if (slots[i].moduleName === "omarchy.indicators") return slots[i].activeItem
    return null
  }
  readonly property bool indicatorsCollected: nativeIndicators !== null && isCollected("omarchy.indicators")
  readonly property bool menuCollected: isCollected("omarchy.menu") && slots.some(function(slot) { return slot.moduleName === "omarchy.menu" })
  readonly property var nativeKeyboard: nativeWidgetFor("omarchy.keyboard-layout")
  readonly property bool keyboardCollected: nativeKeyboard !== null && isCollected("omarchy.keyboard-layout")
  readonly property bool showKeyboardAction: keyboardCollected && nativeKeyboard.multipleLayouts && nativeKeyboard.layoutLabel !== ""
  readonly property int dockedInlineCount: (indicatorsCollected ? 1 : 0) + (menuCollected ? 1 : 0) + (keyboardCollected ? 1 : 0)

  HoverHandler {
    id: barHover
    parent: root.QsWindow.window ? root.QsWindow.window.contentItem : null
  }
  readonly property int collectedCount: {
    var count = 0
    for (var i = 0; i < slots.length; i++) if (isCollected(slots[i].moduleName)) count++
    return count
  }
  readonly property int inlineCount: {
    var count = 0
    for (var i = 0; i < slots.length; i++) {
      var item = slots[i].activeItem
      if (isCollected(slots[i].moduleName) && inlineWidget(slots[i].moduleName, item)) count++
    }
    return count
  }
  readonly property int specialCount: slots.filter(function(slot) { return isCollected(slot.moduleName) && specialWidget(slot.moduleName) }).length

  function isCollected(id) { return collected.indexOf(id) !== -1 }
  function specialWidget(id) { return id === "omarchy.media" }
  function inlineWidget(id, item) { return id !== "omarchy.microphone" && !specialWidget(id) && (id === "omarchy.menu" || (item !== null && typeof item.open !== "function")) }
  function nativeWidgetFor(id) {
    for (var i = 0; i < slots.length; i++) if (slots[i].moduleName === id) return slots[i].activeItem
    return null
  }
  function openInputPanel() {
    var audio = nativeWidgetFor("omarchy.audio")
    if (!audio || typeof audio.open !== "function") return
    captureChild(audio)
    audio.open()
    audio.focusSection = "input"
    audio.selectedIndex = -1
    audio.cursorActive = true
  }

  function captureChild(owner) {
    if (!opened || !owner) return
    returnOwner = owner
    returnScrollY = contentScroll.contentY
  }
  function childClosed(owner) {
    Qt.callLater(function() {
      if (root.returnOwner === owner && root.escapeOwner !== owner && owner && !owner.opened && !owner.popupOpen)
        root.returnOwner = null
    })
  }
  function returnFromEscape(owner) {
    if (returnOwner !== owner) return
    escapeOwner = owner
    Qt.callLater(function() {
      if (root.escapeOwner === owner) root.escapeOwner = null
      if (root.returnOwner !== owner || !owner || owner.opened || owner.popupOpen) return
      root.returnOwner = null
      root.configuring = false
      root.restoreScrollOnOpen = true
      root.open()
    })
  }

  function setCollected(id, enabled) {
    if (id === "omarchy.tray") return false
    // Placement controls are intentionally limited to genuine first-party slots.
    var supported = false
    for (var i = 0; i < slots.length; i++) if (slots[i].moduleName === id && slots[i].firstParty) supported = true
    if (!supported) return false
    var ids = collected.slice()
    var index = ids.indexOf(id)
    if ((index !== -1) === enabled) { saveError = ""; return true }
    if (enabled && index === -1) ids.push(id)
    if (!enabled && index !== -1) ids.splice(index, 1)
    var next = {}
    for (var key in settings) next[key] = settings[key]
    next.collected = ids
    if (!bar || !bar.shell || !bar.shell.updateEntryInline(moduleName, next)) {
      saveError = "Could not save placement"
      return false
    }
    saveError = ""
    settings = next
    return true
  }

  function label(id) {
    var labels = {"omarchy.network": "Wi-Fi", "omarchy.monitor": "Display", "omarchy.power": "Battery"}
    if (labels[id]) return labels[id]
    var name = id.split(".").pop().replace(/-/g, " ")
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  // This prototype uses visual scene internals, not a public nested-widget API.
  // Only inspect ModuleSlot UI objects in our own bar window. Native services,
  // settings facades, IPC handlers and component ownership remain untouched.
  function discover() {
    var window = root.QsWindow.window
    if (!window || !window.contentItem) return
    var found = []
    function walk(item) {
      if (!item) return
      if ("activeItem" in item && "entry" in item && "region" in item) {
        if (item.firstParty === true && item.moduleName && item.moduleName.indexOf("omarchy.") === 0 && item.moduleName !== "omarchy.spacer" && item.moduleName !== "omarchy.tray" && item.activeItem)
          found.push(item)
        return
      }
      var children = item.children || []
      for (var i = 0; i < children.length; i++) walk(children[i])
    }
    walk(window.contentItem)
    if (found.length === slots.length) {
      var same = true
      for (var i = 0; i < found.length; i++) if (found[i] !== slots[i]) same = false
      if (same) return
    }
    // Release borrowed visuals before replacing Repeater delegates.
    for (var j = 0; j < hosts.count; j++) {
      var host = hosts.itemAt(j)
      if (host) host.release()
    }
    slots = found
  }

  function closeDetails() {
    for (var i = 0; i < slots.length; i++) {
      var item = slots[i].activeItem
      if (item && typeof item.close === "function") item.close()
    }
  }

  onOpenedChanged: {
    if (opened) { returnOwner = null; escapeOwner = null; closeDetails(); discover(); viewReset.restart() }
    else if (returnOwner) childClosed(returnOwner)
  }
  onConfiguringChanged: { restoreScrollOnOpen = false; viewReset.restart() }
  // Flickable can preserve its old bottom anchor while the new page is being
  // laid out. Reset after that resize, not before, so the header stays visible.
  Timer {
    id: viewReset
    interval: 32
    onTriggered: {
      contentScroll.contentY = root.restoreScrollOnOpen ? Math.max(0, Math.min(root.returnScrollY, contentScroll.contentHeight - contentScroll.height)) : 0
      root.restoreScrollOnOpen = false
    }
  }
  Component.onCompleted: Qt.callLater(discover)
  Timer { interval: 500; running: true; repeat: true; onTriggered: root.discover() }

  IpcHandler {
    target: "konocontrol-debug"
    function status(): string {
      var widgets = []
      for (var i = 0; i < hosts.count; i++) {
        var host = hosts.itemAt(i)
        if (host) widgets.push({id: host.widgetId, collected: host.collected,
          inline: host.inlineAction,
          quickAction: host.parent === keyboardDock || host.parent === menuDock,
          keyboardLayout: host.widgetId === "omarchy.keyboard-layout" && host.nativeItem ? {label: host.nativeItem.layoutLabel, multiple: host.nativeItem.multipleLayouts} : null,
          special: host.specialCard,
          controls: host.specialCardControls(),
          escapeTargets: host.escapeTargets.length,
          actions: host.inlineAction ? host.actionRects() : [],
          moved: host.borrowed !== null, opened: host.nativeItem ? !!(host.nativeItem.opened || host.nativeItem.popupOpen) : false,
          geometry: {x: host.mapToGlobal(0, 0).x, y: host.mapToGlobal(0, 0).y, width: host.width, height: host.height},
          nativeWidth: host.nativeItem ? host.nativeItem.width : 0,
          nativeHeight: host.nativeItem ? host.nativeItem.height : 0,
          nativeVisible: host.nativeItem ? host.nativeItem.visible : false,
          alwaysShow: host.nativeItem && "alwaysShowIndicators" in host.nativeItem ? host.nativeItem.alwaysShowIndicators : null,
          inactiveWidth: host.inactiveIndicatorArea ? host.inactiveIndicatorArea.implicitWidth : null,
          volume: host.nativeItem && "outputVolume" in host.nativeItem ? host.nativeItem.outputVolume : null,
          brightness: host.nativeItem && "brightnessPercent" in host.nativeItem ? host.nativeItem.brightnessPercent : null,
          muted: host.nativeItem && "muted" in host.nativeItem ? host.nativeItem.muted : null,
          inputVolume: host.widgetId === "omarchy.microphone" && host.nativeItem ? host.nativeItem.volume : null,
          hasPlayer: host.widgetId === "omarchy.media" && host.nativeItem ? !!host.nativeItem.activePlayer : null,
          nativeX: host.nativeItem ? host.nativeItem.mapToGlobal(0, 0).x : 0,
          nativeY: host.nativeItem ? host.nativeItem.mapToGlobal(0, 0).y : 0})
      }
      var rows = []
      for (var j = 0; j < configurationRows.count; j++) {
        var row = configurationRows.itemAt(j)
        if (row) rows.push({id: row.modelData.moduleName, x: row.mapToGlobal(0, 0).x,
          y: row.mapToGlobal(0, 0).y, width: row.width, height: row.height})
      }
      return JSON.stringify({drawer: root.opened, configuring: root.configuring, widgets: widgets,
        configuration: rows, indicatorActions: indicatorStrip.actionRects(), barHovered: barHover.hovered,
        panel: {x: drawer.cardOrigin.x, y: drawer.cardOrigin.y, width: drawer.contentWidth, height: drawer.contentHeight},
        headerAction: {x: optionsButton.mapToGlobal(0, 0).x, y: optionsButton.mapToGlobal(0, 0).y,
          width: optionsButton.width, height: optionsButton.height},
        scrollY: contentScroll.contentY,
        returnOwner: root.returnOwner ? root.returnOwner.moduleName : "",
        referenceIcon: {width: button.implicitWidth, fontSize: button.fontSize},
        error: root.saveError})
    }
    function placement(id: string, collected: bool): bool { return root.setCollected(id, collected) }
    function configure(): void { root.configuring = true; root.open() }
    function overview(): void { root.configuring = false; root.open() }
    function scroll(delta: int): void { contentScroll.contentY = Math.max(0, contentScroll.contentY + delta) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      ControlCenterIcon { foreground: button.foreground }
    }
    tooltipText: "Konocontrol · Right-click to choose widgets"
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.configuring = true; root.open() }
      else if (b === Qt.LeftButton) { root.configuring = false; root.toggle() }
    }
  }

  KeyboardPanel {
    id: drawer
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(drawerColumn.implicitHeight, Style.space(620))
    focusTarget: drawerKeys

    Item {
      id: drawerKeys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      Flickable {
        id: contentScroll
        anchors.fill: parent
        contentHeight: drawerColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: drawerColumn
          width: parent.width
          spacing: Style.spacing.panelGap

          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight, optionsButton.implicitHeight)
            Item {
              id: headerIcon
              implicitWidth: Style.font.display
              implicitHeight: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              ControlCenterIcon {
                anchors.fill: parent
                visible: !root.configuring
                foreground: root.foreground
              }
              Text {
                anchors.centerIn: parent
                visible: root.configuring
                textFormat: Text.PlainText
                text: "\uf013"
                color: root.foreground
                font.family: root.textFont
                font.pixelSize: Style.font.display
              }
            }
            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.spacing.panelGap
              anchors.right: optionsButton.left
              anchors.rightMargin: Style.spacing.xl
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs
              Text {
                textFormat: Text.PlainText
                text: root.configuring ? "Configure" : "Konocontrol"
                width: parent.width
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.textFont
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: root.configuring ? "WIDGET PLACEMENT" : "CONTROL CENTER"
                width: parent.width
                elide: Text.ElideRight
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.textFont
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
            PanelActionButton {
              id: optionsButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.configuring ? "\uf060" : "\uf013"
              tooltipText: root.configuring ? "Back to control center" : "Configure widgets"
              foreground: root.foreground
              fontFamily: root.textFont
              size: Style.space(32)
              focusable: true
              onClicked: root.configuring = !root.configuring
            }
          }

          PanelSeparator { foreground: root.foreground }

          Text {
            visible: root.configuring
            text: "Choose where each widget appears."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.textFont
            font.pixelSize: Style.font.bodySmall
          }

          PanelSectionHeader {
            visible: !root.configuring && root.specialCount > 0
            text: "MEDIA"
            foreground: root.foreground
            fontFamily: root.textFont
          }

          Column {
            id: mediaCards
            width: parent.width
            spacing: Style.spacing.panelGap
            visible: !root.configuring && root.specialCount > 0
            Item {
              id: mediaCardSlot
              width: parent.width
              height: childrenRect.height
              visible: root.isCollected("omarchy.media") && root.nativeWidgetFor("omarchy.media") !== null
            }
          }

          Column {
            visible: !root.configuring && (root.indicatorsCollected || root.menuCollected || root.showKeyboardAction)
            width: parent.width
            spacing: Style.spacing.panelGap

            PanelSectionHeader {
              text: "QUICK ACTIONS"
              foreground: root.foreground
              fontFamily: root.textFont
            }

            BorderSurface {
              id: quickActions
              width: parent.width
              height: Style.space(64)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: quickHover.hovered ? Border.controlSpec("hover-cursor", root.foreground, Color.accent) : Border.none()
              HoverHandler { id: quickHover }

              Item {
                id: menuDock
                anchors.left: parent.left
                height: parent.height
                width: root.menuCollected ? (root.indicatorsCollected ? (parent.width - keyboardDock.width) / 7 : Style.space(44)) : 0
                visible: root.menuCollected
              }

              Item {
                id: keyboardDock
                x: root.indicatorsCollected || root.menuCollected ? parent.width - width : 0
                height: parent.height
                width: root.showKeyboardAction ? Style.space(48) : 0
                visible: root.showKeyboardAction
              }

              IndicatorStrip {
                id: indicatorStrip
                anchors.left: menuDock.right
                anchors.right: keyboardDock.left
                anchors.bottom: parent.bottom
                height: parent.height
                visible: root.indicatorsCollected
                nativeIndicators: root.nativeIndicators
              }
            }
          }

          PanelSectionHeader {
            visible: root.configuring || root.collectedCount > root.inlineCount + root.specialCount || root.inlineCount > root.dockedInlineCount
            text: root.configuring ? "BAR WIDGETS" : "CONTROLS"
            foreground: root.foreground
            fontFamily: root.textFont
          }

          Flow {
            id: actionsFlow
            width: parent.width
            spacing: Style.space(8)
            visible: !root.configuring && root.inlineCount > root.dockedInlineCount
          }

          Flow {
            id: cardsFlow
            width: parent.width
            visible: !root.configuring && root.collectedCount > root.inlineCount + root.specialCount
            spacing: Style.spacing.xl

            Repeater {
              id: hosts
              model: root.slots

              delegate: Item {
                id: host
                required property var modelData
                readonly property var slot: modelData
                readonly property string widgetId: slot ? slot.moduleName : ""
                readonly property bool collected: root.isCollected(widgetId)
                readonly property var nativeItem: slot ? slot.activeItem : null
                readonly property bool inlineAction: root.inlineWidget(widgetId, nativeItem)
                readonly property bool specialCard: root.specialWidget(widgetId)
                parent: widgetId === "omarchy.media" ? mediaCardSlot : widgetId === "omarchy.menu" ? menuDock : widgetId === "omarchy.keyboard-layout" ? keyboardDock : inlineAction ? actionsFlow : cardsFlow
                property var borrowed: null
                property var originalParent: null
                property var originalSlotParent: null
                property var savedAnchors: []
                property var inactiveIndicatorArea: null
                property var sizedIcons: []
                property var escapeTargets: []
                visible: !root.configuring && collected && widgetId !== "omarchy.indicators"
                width: collected && widgetId !== "omarchy.indicators" ? (specialCard || widgetId === "omarchy.menu" || widgetId === "omarchy.keyboard-layout" ? parent.width : inlineAction ? Math.min(parent.width, Math.max(Style.space(44), visual.implicitWidth + Style.space(24))) : Math.floor((parent.width - parent.spacing) / 2)) : 0
                height: collected && widgetId !== "omarchy.indicators" ? (specialCard ? (specialView.item ? specialView.item.implicitHeight : Style.space(120)) : widgetId === "omarchy.menu" || widgetId === "omarchy.keyboard-layout" ? parent.height : inlineAction ? Style.space(44) : Style.space(64)) : 0

                Binding {
                  target: host.widgetId === "omarchy.keyboard-layout" ? host.nativeButton() : null
                  property: "fontSize"
                  when: host.collected && host.widgetId === "omarchy.keyboard-layout" && host.nativeItem !== null
                  value: Style.font.body
                  restoreMode: Binding.RestoreBindingOrValue
                }

                function specialCardControls() {
                  return specialView.item && typeof specialView.item.controlRects === "function" ? specialView.item.controlRects() : []
                }

                Loader {
                  id: specialView
                  anchors.fill: parent
                  active: host.specialCard && host.collected
                  sourceComponent: mediaCardComponent
                  onLoaded: {
                    item.nativeWidget = Qt.binding(function() { return host.nativeItem })
                    item.foreground = Qt.binding(function() { return root.foreground })
                    item.fontFamily = Qt.binding(function() { return root.textFont })
                  }
                }

                function findEscapeTargets() {
                  var found = [], seen = []
                  function walk(object, depth) {
                    if (!object || depth > 8 || seen.indexOf(object) !== -1) return
                    seen.push(object)
                    if ("focusTarget" in object && object.focusTarget && typeof object.focusTarget.closeRequested === "function") {
                      found.push(object.focusTarget)
                      return
                    }
                    if ("item" in object && object.item) walk(object.item, depth + 1)
                    var data = object.data || []
                    for (var i = 0; i < data.length; i++) walk(data[i], depth + 1)
                  }
                  walk(nativeItem, 0)
                  if (found.length) escapeTargets = found
                }
                Timer {
                  interval: 100
                  running: host.nativeItem !== null && typeof host.nativeItem.open === "function" && (root.opened || root.returnOwner === host.nativeItem) && host.escapeTargets.length === 0
                  triggeredOnStart: true
                  repeat: true
                  onTriggered: host.findEscapeTargets()
                }
                Repeater {
                  model: host.escapeTargets
                  delegate: Item {
                    required property var modelData
                    width: 0
                    height: 0
                    Connections {
                      target: modelData
                      function onCloseRequested() { root.returnFromEscape(host.nativeItem) }
                    }
                  }
                }

                function activate(button) {
                  if (widgetId === "omarchy.microphone") {
                    if (button === Qt.RightButton) { if (nativeItem) nativeItem.toggleMute() }
                    else root.openInputPanel()
                    return
                  }
                  var target = nativeButton()
                  if (root.opened && nativeItem && typeof nativeItem.open === "function") root.captureChild(nativeItem)
                  if (target) target.triggerPress(button)
                }

                // Reveal inactive indicator switches while collected, without
                // changing their saved Bar settings or reimplementing actions.
                Binding {
                  target: host.nativeItem
                  property: "settings"
                  when: host.widgetId === "omarchy.indicators" && host.nativeItem !== null
                  value: {
                    var settings = {}
                    var source = host.slot ? host.slot.moduleSettings : {}
                    for (var key in source) settings[key] = source[key]
                    settings.alwaysShow = !host.collected
                    settings.items = ["Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake"]
                    return settings
                  }
                  restoreMode: Binding.RestoreBindingOrValue
                }

                Binding {
                  target: host.nativeItem
                  property: "visible"
                  when: host.widgetId === "omarchy.indicators" && host.nativeItem !== null
                  value: host.collected || barHover.hovered
                  restoreMode: Binding.RestoreBindingOrValue
                }

                // Keep the native active block in the Bar. The inactive block
                // still reports state, but never consumes Bar space if collected.
                Binding {
                  target: host.inactiveIndicatorArea
                  property: "visible"
                  when: host.inactiveIndicatorArea !== null
                  // Explicit true on return avoids restoring an inherited false
                  // visibility snapshot captured while the Bar was not hovered.
                  value: !host.collected
                  restoreMode: Binding.RestoreBindingOrValue
                }
                Binding {
                  target: host.inactiveIndicatorArea
                  property: "implicitWidth"
                  when: host.collected && host.inactiveIndicatorArea !== null && host.nativeItem && !host.nativeItem.vertical
                  value: 0
                  restoreMode: Binding.RestoreBindingOrValue
                }
                Binding {
                  target: host.inactiveIndicatorArea
                  property: "implicitHeight"
                  when: host.collected && host.inactiveIndicatorArea !== null && host.nativeItem && host.nativeItem.vertical
                  value: 0
                  restoreMode: Binding.RestoreBindingOrValue
                }

                function findInactiveIndicators(item) {
                  if (!item) return null
                  var children = item.children || []
                  for (var i = 0; i < children.length; i++) {
                    var child = children[i]
                    if (item.clip === true && child.indicatorBlock === "inactive") return item
                    var found = findInactiveIndicators(child)
                    if (found) return found
                  }
                  return null
                }
                Timer {
                  interval: 250
                  running: host.widgetId === "omarchy.indicators" || host.widgetId === "omarchy.system-update"
                  repeat: true
                  triggeredOnStart: true
                  onTriggered: {
                    if (host.widgetId === "omarchy.indicators") host.inactiveIndicatorArea = host.findInactiveIndicators(host.nativeItem)
                    host.syncIconSizes()
                  }
                }

                function syncIconSizes() {
                  var found = []
                  function walk(item) {
                    if (!item) return
                    if (typeof item.triggerPress === "function" && "opticalSize" in item) { found.push(item); return }
                    var children = item.children || []
                    for (var i = 0; i < children.length; i++) walk(children[i])
                  }
                  walk(nativeItem)
                  var changed = found.length !== sizedIcons.length
                  for (var i = 0; !changed && i < found.length; i++) if (found[i] !== sizedIcons[i]) changed = true
                  if (changed) sizedIcons = found
                }

                Repeater {
                  model: host.sizedIcons
                  delegate: Item {
                    required property var modelData
                    width: 0
                    height: 0
                    Binding { target: modelData; property: "fontSize"; value: Style.bar.iconFont; restoreMode: Binding.RestoreBindingOrValue }
                    Binding { target: modelData; property: "opticalSize"; value: Style.bar.iconCanvas; restoreMode: Binding.RestoreBindingOrValue }
                    Binding { target: modelData; property: "fixedWidth"; value: host.nativeItem && host.nativeItem.vertical ? -1 : Style.bar.iconSlot; restoreMode: Binding.RestoreBindingOrValue }
                    Binding { target: modelData; property: "fixedHeight"; value: host.nativeItem && host.nativeItem.vertical ? Style.bar.iconSlot : -1; restoreMode: Binding.RestoreBindingOrValue }
                  }
                }

                // An explicitly collected update button should remain available
                // even when no pending-update indicator is present on the Bar.
                Binding {
                  target: host.nativeItem
                  property: "visible"
                  when: host.collected && host.widgetId === "omarchy.system-update" && host.nativeItem !== null
                  value: true
                  restoreMode: Binding.RestoreBindingOrValue
                }

                function nativeButton() {
                  function find(item) {
                    if (!item) return null
                    if (typeof item.triggerPress === "function") return item
                    var children = item.children || []
                    for (var i = 0; i < children.length; i++) {
                      var target = find(children[i])
                      if (target) return target
                    }
                    return null
                  }
                  // Indicators contains multiple unrelated actions; only its
                  // actual icons should trigger them, not the card background.
                  return widgetId === "omarchy.indicators" ? null : find(nativeItem)
                }

                function actionRects() {
                  var result = []
                  function walk(item) {
                    if (!item || item.visible === false || (item.clip && (item.width <= 0 || item.height <= 0))) return
                    if (typeof item.triggerPress === "function" && item.visible && item.width > 0 && item.height > 0) {
                      var point = item.mapToGlobal(0, 0)
                      result.push({id: item.moduleName || host.widgetId, x: point.x, y: point.y,
                        width: item.width, height: item.height, tooltip: item.tooltipText, fontSize: item.fontSize})
                      return
                    }
                    var children = item.children || []
                    for (var i = 0; i < children.length; i++) walk(children[i])
                  }
                  walk(nativeItem)
                  return result
                }

                function repairAnchors() {
                  if (!borrowed) return
                  function walk(object, depth) {
                    if (!object || depth > 8) return
                    if ("anchorItem" in object && "bar" in object) {
                      var known = false
                      for (var k = 0; k < savedAnchors.length; k++) if (savedAnchors[k].object === object) known = true
                      if (!known) savedAnchors.push({object: object, anchor: object.anchorItem})
                      object.anchorItem = button
                      return
                    }
                    if ("item" in object && object.item) walk(object.item, depth + 1)
                    var data = object.data || []
                    for (var i = 0; i < data.length; i++) walk(data[i], depth + 1)
                  }
                  walk(borrowed, 0)
                }

                function release() {
                  if (!borrowed) return
                  // Restore the visual parent before restoring native anchors:
                  // KeyboardPanel.contentItem is a list, not a bar content Item.
                  if (originalParent) {
                    originalParent.anchors.fill = null
                    originalParent.parent = originalSlotParent
                    originalParent.anchors.fill = originalSlotParent
                  }
                  for (var i = 0; i < savedAnchors.length; i++) {
                    var entry = savedAnchors[i]
                    if (entry.object) entry.object.anchorItem = entry.anchor
                  }
                  savedAnchors = []
                  if (slot) {
                    slot.width = Qt.binding(function() { return slot.implicitWidth })
                    slot.height = Qt.binding(function() { return slot.implicitHeight })
                  }
                  borrowed = null
                  originalParent = null
                  originalSlotParent = null
                }

                function sync() {
                  if (widgetId === "omarchy.indicators") { release(); return }
                  if (!collected || !nativeItem) { release(); return }
                  if (borrowed === nativeItem) { repairAnchors(); return }
                  release()
                  borrowed = nativeItem
                  // QQuickLoader owns its item's geometry even after the item
                  // is visually reparented. Move that Loader, not its item.
                  originalParent = borrowed.parent
                  originalSlotParent = originalParent.parent
                  repairAnchors()
                  originalParent.anchors.fill = null
                  originalParent.parent = widgetId === "omarchy.microphone" ? microphoneParking : visual
                  originalParent.anchors.fill = originalParent.parent
                  slot.width = 0
                  slot.height = 0
                  repairAnchors()
                }

                onCollectedChanged: syncTimer.restart()
                onNativeItemChanged: { escapeTargets = []; syncTimer.restart() }
                Component.onCompleted: syncTimer.restart()
                Component.onDestruction: { syncTimer.stop(); release() }

                Timer { id: syncTimer; interval: 0; onTriggered: host.sync() }

                Connections {
                  target: host.nativeItem
                  ignoreUnknownSignals: true
                  function onOpenedChanged() {
                    if (host.nativeItem.opened) {
                      if (root.opened) root.captureChild(host.nativeItem)
                      host.repairAnchors()
                      root.close()
                    } else root.childClosed(host.nativeItem)
                  }
                  function onPopupOpenChanged() { if (host.nativeItem.popupOpen) { host.repairAnchors(); root.close() } }
                  function onSettingsChanged() { if (host.collected) Qt.callLater(host.repairAnchors) }
                }
                Connections {
                  target: host.widgetId === "omarchy.menu" ? host.nativeButton() : null
                  ignoreUnknownSignals: true
                  function onPressed() { root.close() }
                }

                HoverHandler { id: cardHover }
                TapHandler {
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  onPressedChanged: if (pressed && root.opened && host.nativeItem && typeof host.nativeItem.open === "function") root.captureChild(host.nativeItem)
                }

                BorderSurface {
                  anchors.fill: parent
                  visible: !root.configuring && !host.specialCard && host.widgetId !== "omarchy.menu" && host.widgetId !== "omarchy.keyboard-layout"
                  radius: Style.cornerRadius
                  color: cardHover.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : Style.normalFillFor(root.foreground, Color.accent)
                  borderSpec: cardHover.hovered ? Border.controlSpec("hover-cursor", root.foreground, Color.accent) : Border.none()
                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                // A wheel-only overlay must be above the borrowed native icon:
                // its own MouseArea otherwise consumes wheel before the card.
                MouseArea {
                  anchors.fill: parent
                  z: 10
                  enabled: !root.configuring && host.collected && (host.widgetId === "omarchy.audio" || host.widgetId === "omarchy.monitor" || host.widgetId === "omarchy.microphone")
                  acceptedButtons: Qt.NoButton
                  onWheel: function(event) { event.accepted = true }
                }

                MouseArea {
                  id: cardMouse
                  anchors.fill: parent
                  enabled: !root.configuring && !host.specialCard
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                  cursorShape: host.nativeButton() ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: function(mouse) {
                    host.activate(mouse.button)
                  }
                  onWheel: function(wheel) {
                    if (host.widgetId === "omarchy.audio" || host.widgetId === "omarchy.monitor" || host.widgetId === "omarchy.microphone") { wheel.accepted = true; return }
                    var target = host.nativeButton()
                    if (target && typeof target.wheelMoved === "function") target.wheelMoved(wheel.angleDelta.y)
                  }
                }

                Item {
                  id: microphoneParking
                  visible: false
                  width: host.nativeItem ? host.nativeItem.implicitWidth : 0
                  height: host.nativeItem ? host.nativeItem.implicitHeight : 0
                }

                Item {
                  id: visual
                  visible: !root.configuring && !host.specialCard
                  x: host.widgetId === "omarchy.menu" || host.widgetId === "omarchy.keyboard-layout" ? Math.round((parent.width - width) / 2) : Style.spacing.rowPaddingX
                  y: Math.round((parent.height - height) / 2)
                  implicitWidth: host.borrowed ? host.borrowed.implicitWidth : 0
                  width: host.widgetId === "omarchy.menu" || host.widgetId === "omarchy.keyboard-layout" ? implicitWidth : Math.max(0, Math.min(implicitWidth, parent.width - Style.spacing.rowPaddingX * 2))
                  height: host.borrowed ? host.borrowed.implicitHeight : Style.bar.sizeHorizontal
                  opacity: host.widgetId === "omarchy.menu" && !cardHover.hovered ? 0.65 : 1
                  BarIconButton {
                    anchors.fill: parent
                    visible: host.widgetId === "omarchy.microphone"
                    bar: root.bar
                    text: host.nativeItem && host.nativeItem.muted ? "󰍭" : "󰍬"
                    onPressed: function(button) { host.activate(button) }
                  }
                }

                Text {
                  id: caption
                  visible: !root.configuring && !host.inlineAction && !host.specialCard
                  x: visual.x + visual.width + Style.spacing.xl
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - x - Style.spacing.rowPaddingX)
                  text: root.label(host.widgetId)
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.textFont
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

              }
            }
          }

          Column {
            id: configurationList
            visible: root.configuring
            width: parent.width
            spacing: Style.spacing.rowGap

            Repeater {
              id: configurationRows
              model: root.configSlots
              delegate: Toggle {
                required property var modelData
                width: configurationList.width
                label: root.label(modelData.moduleName)
                description: root.isCollected(modelData.moduleName) ? "Control center" : "Bar"
                checked: root.isCollected(modelData.moduleName)
                foreground: root.foreground
                fontFamily: root.textFont
                borderSpec: activeFocus ? Border.controlSpec("focus", root.foreground, Color.accent) : _hot ? Border.controlSpec("hover-cursor", root.foreground, Color.accent) : Border.none()
                color: Style.controlFill(activeFocus, _hot, root.foreground, Color.accent)
                onClicked: root.setCollected(modelData.moduleName, !checked)
              }
            }
          }

          Text {
            visible: !root.configuring && root.collectedCount === 0
            text: "No widgets collected. Click Configure."
            width: parent.width
            wrapMode: Text.WordWrap
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.textFont
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            visible: root.saveError !== ""
            text: root.saveError
            width: parent.width
            wrapMode: Text.WordWrap
            color: Color.urgent
            font.family: root.textFont
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

    }
  }

  Component { id: mediaCardComponent; MediaCard {} }
}
