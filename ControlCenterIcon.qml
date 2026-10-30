import QtQuick
import QtQuick.Shapes
import qs.Commons

// A filled upper switch and outlined lower switch, with opposing knobs.
// A 16px optical grid aligns the track edges with menu-bar pixels. The larger
// negative knob compensates optically for the smaller positive knob below.
// Even-odd cutouts stay transparent on any background.
Item {
  id: root
  property color foreground: Color.foreground
  implicitWidth: 16
  implicitHeight: 16

  Shape {
    width: 16
    height: 16
    anchors.centerIn: parent
    scale: Math.min(root.width / width, root.height / height)
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: -1
      fillColor: root.foreground
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M4.5 2 H11.5 A2.5 2.5 0 0 1 11.5 7 H4.5 A2.5 2.5 0 0 1 4.5 2 Z "
          + "M6.65 4.5 A1.65 1.65 0 1 0 3.35 4.5 A1.65 1.65 0 1 0 6.65 4.5 Z "
          + "M5 8.5 H11 A3 3 0 0 1 11 14.5 H5 A3 3 0 0 1 5 8.5 Z "
          + "M5 9.5 H11 A2 2 0 0 1 11 13.5 H5 A2 2 0 0 1 5 9.5 Z "
          + "M12.5 11.5 A1.5 1.5 0 1 0 9.5 11.5 A1.5 1.5 0 1 0 12.5 11.5 Z"
      }
    }
  }
}
