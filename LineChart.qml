import QtQuick

// Smooth line + gradient area chart on a Canvas. values: oldest first.
Item {
  id: root
  property var values: []
  property color lineColor: "#9385ff"
  property color textColor: "#71717a"
  property string startLabel: ""
  property string endLabel: ""
  property string fontFamilies: "Noto Sans"
  property var formatValue: function (v) { return String(v) }
  property real reveal: 0
  implicitHeight: 84
  onValuesChanged: { reveal = 0; revealAnim.restart(); canvas.requestPaint() }
  onRevealChanged: canvas.requestPaint()
  NumberAnimation { id: revealAnim; target: root; property: "reveal"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }

  readonly property real lo: { var v = values || [], m = Infinity; for (var i = 0; i < v.length; i++) if (v[i] < m) m = v[i]; return isFinite(m) ? m : 0 }
  readonly property real hi: { var v = values || [], m = -Infinity; for (var i = 0; i < v.length; i++) if (v[i] > m) m = v[i]; return isFinite(m) ? m : 0 }

  Canvas {
    id: canvas
    anchors.left: parent.left
    anchors.leftMargin: root.hi > 0 ? Math.max(hiLabel.implicitWidth, loLabel.implicitWidth) + 6 : 0   // the axis labels' gutter
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height - 16
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var v = root.values || [], n = v.length
      if (n < 2) return
      var span = root.hi - root.lo
      if (span <= 0) span = Math.abs(root.hi) || 1
      var pad = 4
      function px(i) { return pad + i * (width - pad * 2) / (n - 1) }
      function py(x) { return height - pad - (x - root.lo) / span * (height - pad * 2) }
      var last = Math.max(1, Math.round((n - 1) * root.reveal))
      ctx.beginPath()
      ctx.moveTo(px(0), height)
      for (var i = 0; i <= last; i++) ctx.lineTo(px(i), py(v[i]))
      ctx.lineTo(px(last), height)
      ctx.closePath()
      var g = ctx.createLinearGradient(0, 0, 0, height)
      g.addColorStop(0, Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.32))
      g.addColorStop(1, Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0))
      ctx.fillStyle = g
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (var j = 1; j <= last; j++) ctx.lineTo(px(j), py(v[j]))
      ctx.lineWidth = 1.8
      ctx.lineJoin = "round"
      ctx.strokeStyle = root.lineColor
      ctx.stroke()
      ctx.fillStyle = "#b7b1ff"
      ctx.beginPath()
      ctx.arc(px(last), py(v[last]), 3, 0, Math.PI * 2)
      ctx.fill()
    }
  }
  Text { id: hiLabel; anchors.top: parent.top; anchors.left: parent.left; text: root.hi > 0 ? root.formatValue(root.hi) : ""; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
  Text { id: loLabel; anchors.bottom: parent.bottom; anchors.bottomMargin: 18; anchors.left: parent.left; text: root.hi > 0 ? root.formatValue(root.lo) : ""; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
  Text { anchors.bottom: parent.bottom; anchors.left: parent.left; text: root.startLabel; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
  Text { anchors.bottom: parent.bottom; anchors.right: parent.right; text: root.endLabel; color: root.textColor; font.family: root.fontFamilies; font.pixelSize: 9 }
}
