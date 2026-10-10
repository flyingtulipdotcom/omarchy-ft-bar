import QtQuick

// Card: translucent fill, 1px soft border, 12px radius.
Rectangle {
  id: root
  property real pad: 12
  default property alias content: holder.children
  property color fill: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.65)
  property color stroke: Qt.rgba(76 / 255, 76 / 255, 82 / 255, 0.5)
  property color hoverStroke: Qt.rgba(117 / 255, 89 / 255, 255, 0.55)
  property bool hoverable: false
  implicitHeight: holder.childrenRect.height + pad * 2
  radius: 12
  color: fill
  border.width: 1
  border.color: hoverable && hover.hovered ? hoverStroke : stroke
  Behavior on border.color { ColorAnimation { duration: 140 } }
  HoverHandler { id: hover; enabled: root.hoverable }
  Item {
    id: holder
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    height: childrenRect.height
  }
}
