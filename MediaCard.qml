import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
  id: root
  property var nativeWidget: null
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  readonly property var service: nativeWidget ? nativeWidget.mediaService : null
  readonly property var player: nativeWidget ? nativeWidget.activePlayer : null
  readonly property bool hasTrack: !!player && !!(player.trackTitle || player.trackArtist)

  implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX * 2
  radius: Style.cornerRadius
  color: Style.normalFillFor(foreground, Commons.Color.accent)
  borderSpec: hover.hovered ? Border.controlSpec("hover-cursor", foreground, Commons.Color.accent) : Border.none()
  HoverHandler { id: hover }

  function action(name) {
    if (service && player) service.runAction(name, false, service.playerKey(player))
  }

  function controlRects() {
    var result = []
    var controls = [previous, playPause, next]
    var names = ["previous", "playPause", "next"]
    for (var i = 0; i < controls.length; i++) {
      var button = controls[i], point = button.mapToGlobal(0, 0)
      result.push({id: names[i], x: point.x, y: point.y, width: button.width, height: button.height, enabled: button.enabled})
    }
    return result
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.rowPaddingX
    spacing: Style.spacing.controlGap

    Item {
      width: parent.width
      implicitHeight: Math.max(cover.height, labels.implicitHeight)

      Rectangle {
        id: cover
        width: Style.space(52)
        height: width
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        Image {
          id: art
          anchors.fill: parent
          source: root.hasTrack ? (root.player.trackArtUrl || "") : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
        Text {
          anchors.centerIn: parent
          visible: art.status !== Image.Ready
          text: "󰝚"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }
      }

      Column {
        id: labels
        anchors.left: cover.right
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        PanelSectionHeader { text: root.hasTrack ? "NOW PLAYING" : "MEDIA"; foreground: root.foreground; fontFamily: root.fontFamily }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.hasTrack ? (root.player.trackTitle || root.player.identity || "Media") : "Nothing playing"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.player ? (root.player.trackArtist || root.player.identity || "") : "Play something in a media app"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

    }

    Row {
      id: playbackButtons
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap
      height: Math.max(previous.implicitHeight, playPause.implicitHeight, next.implicitHeight)
      Button {
        id: previous
        height: playbackButtons.height
        iconText: "󰒮"
        tooltipText: "Previous track"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !!root.player && root.player.canGoPrevious
        opacity: enabled ? 1 : 0.4
        focusable: true
        onClicked: root.action("previous")
      }
      Button {
        id: playPause
        height: playbackButtons.height
        iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
        tooltipText: root.player && root.player.isPlaying ? "Pause" : "Play"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        horizontalPadding: Style.spacing.panelGap
        enabled: !!root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
        opacity: enabled ? 1 : 0.4
        focusable: true
        onClicked: root.action("playPause")
      }
      Button {
        id: next
        height: playbackButtons.height
        iconText: "󰒭"
        tooltipText: "Next track"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !!root.player && root.player.canGoNext
        opacity: enabled ? 1 : 0.4
        focusable: true
        onClicked: root.action("next")
      }
    }
  }
}
