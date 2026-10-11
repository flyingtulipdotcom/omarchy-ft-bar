import QtQuick

// Rounded-top bar chart on a Canvas. values: oldest first.
Item {
  id: root
  property var values: []
  property color barColor: "#7559ff"
  property color lastColor: "#b7b1ff"
  property color gridColor: Qt.rgba(1, 1, 1, 0.06)
  property color textColor: "#71717a"
  property string startLabel: ""
  property string endLabel: ""
  property string maxLabel: ""
  property string fontFamilies: "Noto Sans"
  property real reveal: 0
  implicitHeight: 84
  onValuesChanged: { reveal = 0; revealAnim.restart(); canvas.requestPaint() }
  onBarColorChanged: canvas.requestPaint()
  onRevealChanged: canvas.requestPaint()
  NumberAnimation { id: revealAnim; target: root; property: "reveal"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

  Canvas {
    id: canvas
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: root.maxLabel !== "" ? 13 : 0   // room for the max label above the bars
    height: parent.height - 16 - anchors.topMargin
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var v = root.values || [], n = v.length
      if (n === 0) return
      var max = 0
      for (var i = 0; i < n; i++) if (v[i] > max) max = v[i]
      if (max <= 0) max = 1
      ctx.fillStyle = root.gridColor
      ctx.fillRect(0, 0, width, 1)
      ctx.fillRect(0, Math.round(height / 2), width, 1)
      var gap = 3
      var bw = Math.max(2, (width - gap * (n - 1)) / n)
      for (var j = 0; j < n; j++) {
        var h = Math.max(2, Math.round(v[j] / max * (height - 4) * root.reveal))
        var x = j * (bw + gap), y = height - h, r = Math.min(3, bw / 2)
        ctx.fillStyle = j === n - 1 ? root.lastColor : root.barColor
        ctx.globalAlpha = j === n - 1 ? 1 : 0.85
        ctx.beginPath()
        ctx.moveTo(x, height)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.lineTo(x + bw - r, y)
        ctx.quadraticCurveTo(x + bw, y, x + bw, y + r)
        ctx.lineTo(x + bw, height)
        ctx.closePath()
        ctx.fill()
      }
    }
  }
  Text { anchors.top: parent.top; anchors.right: parent.right; text: root.maxLabel; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
  Text { anchors.bottom: parent.bottom; anchors.left: parent.left; text: root.startLabel; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
  Text { anchors.bottom: parent.bottom; anchors.right: parent.right; text: root.endLabel; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
}
