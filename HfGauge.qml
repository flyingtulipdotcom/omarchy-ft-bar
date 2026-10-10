import QtQuick

// One chain's HF: name, track with fill (green/amber/red), the 1.25 liquidation line, value.
Item {
  id: root
  property string name: ""
  property var hf: null
  property real liqHf: 1.25
  property real warnHf: 1.4
  property real critHf: 1.3
  property color textColor: "#e4e4e7"
  property color subColor: "#a1a1aa"
  property color okColor: "#0fd727"
  property color warnColor: "#f5a524"
  property color badColor: "#ef4444"
  property string fontFamilies: "Noto Sans"
  readonly property real scaleMax: 3.0
  readonly property real shown: hf === null ? 0 : Math.min(scaleMax, hf)
  readonly property color fillColor: hf === null ? subColor : (hf <= critHf ? badColor : (hf <= warnHf ? warnColor : okColor))
  implicitHeight: 22
  property real fillW: 0
  onShownChanged: fillW = xAt(shown)
  Behavior on fillW { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
  Component.onCompleted: fillW = xAt(shown)

  function xAt(v) { return Math.max(0, Math.min(1, (v - 1.0) / (scaleMax - 1.0))) * track.width }

  Text { id: label; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 66; text: root.name; textFormat: Text.PlainText; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 11; elide: Text.ElideRight }
  Rectangle {
    id: track
    anchors.left: label.right
    anchors.right: value.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 6
    radius: 3
    color: Qt.rgba(1, 1, 1, 0.07)
    onWidthChanged: root.fillW = root.xAt(root.shown)
    Rectangle { visible: root.hf !== null; height: parent.height; width: root.fillW; radius: 3; color: root.fillColor }
    Rectangle { x: root.xAt(root.liqHf) - 1; y: -4; width: 2; height: parent.height + 8; radius: 1; color: root.badColor }
  }
  Text {
    id: value
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 52
    horizontalAlignment: Text.AlignRight
    text: root.hf === null ? "no debt" : (root.hf >= 100 ? ">100" : root.hf.toFixed(2))
    textFormat: Text.PlainText
    color: root.hf === null ? root.subColor : root.fillColor
    font.family: root.fontFamilies
    font.pixelSize: root.hf === null ? 10 : 12
    font.weight: root.hf === null ? Font.Normal : Font.Bold
  }
}
