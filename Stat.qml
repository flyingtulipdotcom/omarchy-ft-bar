import QtQuick

// Stat: tiny uppercase label over a bold tabular value (+ optional sub line).
// With a url set it is a link: pointer cursor, hover underline, click signal.
Item {
  id: root
  implicitHeight: col.implicitHeight
  height: implicitHeight
  property string url: ""
  property string label: ""
  property string value: ""
  property string sub: ""
  property color valueColor: "#e4e4e7"
  property color labelColor: "#71717a"
  property color subColor: "#a1a1aa"
  property int valueSize: 16
  property string fontFamilies: "Noto Sans"
  Column {
    id: col
    width: root.width
    spacing: 2
  Text {
    text: root.label.toUpperCase()
    textFormat: Text.PlainText
    color: root.labelColor
    font.family: root.fontFamilies
    font.pixelSize: 9
    font.letterSpacing: 0.8
    width: root.width
    elide: Text.ElideRight
  }
  Text {
    text: root.value
    textFormat: Text.PlainText
    color: root.valueColor
    font.family: root.fontFamilies
    font.pixelSize: root.valueSize
    font.weight: Font.Bold
    width: root.width
    elide: Text.ElideRight
  }
  Text {
    visible: root.sub !== ""
    text: root.sub
    textFormat: Text.PlainText
    color: root.subColor
    font.family: root.fontFamilies
    font.pixelSize: 10
    width: root.width
    elide: Text.ElideRight
  }
  }
  MouseArea {
    id: statMa
    anchors.fill: parent
    enabled: root.url !== ""
    hoverEnabled: true
    cursorShape: root.url !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: Qt.openUrlExternally(root.url)
  }
  opacity: root.url !== "" && statMa.containsMouse ? 0.8 : 1
  Behavior on opacity { NumberAnimation { duration: 120 } }
}
