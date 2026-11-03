import QtQuick
import qs.Commons

// Separate views of the original indicator implementations. Their service
// references come from the existing native Indicators widget; state/actions
// remain owned by Omarchy, not duplicated in this plugin.
Item {
  id: root
  property var nativeIndicators: null
  readonly property var nativeBar: nativeIndicators ? nativeIndicators.bar : null
  readonly property int indicatorCount: icons.count
  implicitHeight: Style.space(44)

  QtObject {
    id: indicatorHost
    readonly property bool revealInactiveIndicators: true
    function setIndicatorItemHovered(hovered) {}
    signal refreshRequested()
    function refresh() {
      if (root.nativeIndicators && typeof root.nativeIndicators.refresh === "function") root.nativeIndicators.refresh()
      else refreshRequested()
    }
  }
  Connections {
    target: root.nativeIndicators
    ignoreUnknownSignals: true
    function onRefreshRequested() { indicatorHost.refreshRequested() }
  }

  function actionRects() {
    var result = []
    for (var i = 0; i < icons.count; i++) {
      var cell = icons.itemAt(i)
      var item = cell ? cell.indicator : null
      if (!item) continue
      var point = item.mapToGlobal(0, 0)
      result.push({id: cell.indicatorId, active: item.active, x: point.x, y: point.y,
        width: item.width, height: item.height, tooltip: item.tooltipText, opacity: item.opacity,
        hovered: cell.hovered})
    }
    return result
  }

  Row {
    anchors.fill: parent
    anchors.topMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)

    Repeater {
      id: icons
      // Follow native defaults/configuration: RC removes Dictation and adds
      // PasswordlessSudo and RemoteSession. Never load removed implementations.
      model: root.nativeIndicators ? root.nativeIndicators.indicatorEntries : []

      delegate: Item {
        id: cell
        required property var modelData
        readonly property string indicatorId: typeof modelData === "string" ? modelData : modelData.id
        readonly property var indicator: indicatorLoader.item
        readonly property bool hovered: cellHover.hovered
        width: icons.count > 0 ? parent.width / icons.count : 0
        height: parent.height

        HoverHandler { id: cellHover }
        Binding {
          target: indicatorLoader.item
          property: "opacity"
          when: indicatorLoader.item !== null
          value: cellHover.hovered || (indicatorLoader.item && indicatorLoader.item.active) ? 1 : 0.45
          restoreMode: Binding.RestoreBindingOrValue
        }

        Loader {
          id: indicatorLoader
          anchors.fill: parent
          function load() {
            if (!root.nativeBar || source.toString()) return
            setSource("file:///usr/share/omarchy/shell/plugins/bar/indicators/" + cell.indicatorId + ".qml", {
              bar: root.nativeBar,
              moduleName: cell.indicatorId,
              settings: typeof cell.modelData === "object" ? root.nativeIndicators.entrySettings(cell.modelData) : {},
              indicatorHost: indicatorHost,
              indicatorBlock: "single",
              fontSize: Style.space(16),
              opticalSize: Style.space(20),
              fixedWidth: Qt.binding(function() { return cell.width }),
              fixedHeight: Qt.binding(function() { return cell.height })
            })
          }
          Component.onCompleted: load()
          Connections { target: root; function onNativeBarChanged() { indicatorLoader.load() } }
        }
      }
    }
  }
}
