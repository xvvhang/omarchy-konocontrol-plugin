import QtQuick
import qs.Commons

// Separate views of the original indicator implementations. Their service
// references come from the existing native Indicators widget; state/actions
// remain owned by Omarchy, not duplicated in this plugin.
Item {
  id: root
  property var nativeIndicators: null
  readonly property var nativeBar: nativeIndicators ? nativeIndicators.bar : null
  implicitHeight: Style.space(44)

  QtObject {
    id: indicatorHost
    readonly property bool revealInactiveIndicators: true
    function setIndicatorItemHovered(hovered) {}
  }

  function actionRects() {
    var result = []
    for (var i = 0; i < icons.count; i++) {
      var cell = icons.itemAt(i)
      var item = cell ? cell.indicator : null
      if (!item) continue
      var point = item.mapToGlobal(0, 0)
      result.push({id: cell.modelData, active: item.active, x: point.x, y: point.y,
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
      model: ["Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake"]

      delegate: Item {
        id: cell
        required property string modelData
        readonly property var indicator: indicatorLoader.item
        readonly property bool hovered: cellHover.hovered
        width: parent.width / 6
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
            setSource("file:///usr/share/omarchy/shell/plugins/bar/indicators/" + cell.modelData + ".qml", {
              bar: root.nativeBar,
              moduleName: cell.modelData,
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
