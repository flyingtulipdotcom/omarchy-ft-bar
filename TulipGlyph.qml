import QtQuick
import QtQuick.Shapes

// Flying Tulip glyph (16x16 viewBox).
Item {
  id: root
  property color color: "#7559ff"
  property real size: 16
  implicitWidth: size
  implicitHeight: size
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: root.size / 16; yScale: root.size / 16 }
    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      PathSvg { path: "M5.08,11.36h0c0-.28.13-.55.36-.72l.67-.51c.7-.53,1.19-1.28,1.4-2.14l.02-.06c.32-1.29-.06-2.67-1.01-3.6-.02-.02-.03-.03-.05-.05h0s0,0,0,0c-.82-.77-1.92-1.25-3.13-1.26-.08,0-.19,0-.26,0v5.64c0,1.31.54,2.49,1.42,3.33.54.51,1.21.9,1.95,1.1l1.07-1.15c.2-.22.05-.58-.25-.58h-2.18Z" }
    }
    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      PathSvg { path: "M10.92,11.36h0c0-.28-.13-.55-.36-.72l-.67-.51c-.7-.53-1.19-1.28-1.4-2.14l-.02-.06c-.32-1.29.06-2.67,1.01-3.6.02-.02.03-.03.05-.05.82-.77,1.92-1.25,3.13-1.26.08,0,.19,0,.26,0v5.64c0,1.31-.54,2.49-1.42,3.33-.54.51-1.21.9-1.95,1.1l-1.07-1.15c-.2-.22-.05-.57.25-.58h2.18Z" }
    }
  }
}
