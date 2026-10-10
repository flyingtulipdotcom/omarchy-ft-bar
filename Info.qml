import QtQuick
import "Model.js" as Model

// Info panel content: header, hero stats, charts, account cards.
// `h` is the widget root that owns data and actions.
Item {
  id: root
  property var h
  implicitHeight: col.implicitHeight + 28
  readonly property string fam: "Noto Sans"
  readonly property var productColors: [h.cTulip, h.cTulip400, h.cTulip300, h.cGreen, "#5587f3", h.cRed]

  // gentle open animation
  opacity: h.mode === "info" ? 1 : 0
  y: h.mode === "info" ? 0 : 10
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
  Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

  component Cap: Text {
    textFormat: Text.PlainText
    color: h.cFaint
    font.family: root.fam
    font.pixelSize: 9
    font.letterSpacing: 0.8
    font.capitalization: Font.AllUppercase
  }
  component Body: Text {
    textFormat: Text.PlainText
    color: h.cSub
    font.family: root.fam
    font.pixelSize: 11
    elide: Text.ElideRight
  }
  component Pill: Rectangle {
    id: pill
    property string text: ""
    property bool selected: false
    signal clicked()
    width: pt.implicitWidth + 20; height: 24; radius: 12
    color: selected ? Qt.rgba(117 / 255, 89 / 255, 255, 0.22) : (pma.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
    border.width: 1
    border.color: selected ? h.cTulip : h.cBorder
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Text { id: pt; anchors.centerIn: parent; textFormat: Text.PlainText; text: pill.text; color: pill.selected ? h.cTulip300 : h.cSub; font.family: root.fam; font.pixelSize: 11; font.weight: pill.selected ? Font.DemiBold : Font.Normal }
    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
  }
  component IconBtn: Rectangle {
    id: btn
    property string glyph: ""
    signal clicked()
    width: 30; height: 30; radius: 8
    color: ma.containsMouse ? Qt.rgba(117 / 255, 89 / 255, 255, 0.16) : "transparent"
    border.width: 1
    border.color: ma.containsMouse ? h.cTulip : h.cBorder
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: ma.containsMouse ? h.cTulip300 : h.cSub
      font.family: h.nerdFont
      font.pixelSize: 14
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  Column {
    id: col
    x: 14
    y: 14
    width: root.width - 28
    spacing: 10

    // ---- header
    Item {
      width: parent.width
      height: 34
      Row {
        id: headLink
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9
        opacity: headMa.containsMouse ? 0.8 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Rectangle {
          width: 30; height: 30; radius: 9
          color: "#0c091a"
          border.width: 1
          border.color: Qt.rgba(117 / 255, 89 / 255, 255, 0.4)
          TulipGlyph { anchors.centerIn: parent; size: 20; color: h.cTulip }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text { textFormat: Text.PlainText; text: "Flying Tulip"; color: h.cText; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
          Text { textFormat: Text.PlainText; text: h.walletValid ? Model.shortAddr(h.wallet) : "Market, fees and your account"; color: h.cFaint; font.family: root.fam; font.pixelSize: 10 }
        }
      }
      MouseArea {
        id: headMa
        anchors.fill: headLink
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: h.openUrl(Model.SITE)
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        IconBtn { glyph: ""; onClicked: h.openEditor() }
        IconBtn { glyph: ""; onClicked: { h.refresh(); h.refreshSlow(true) } }
      }
    }
    Rectangle { width: parent.width; height: 1; color: h.cBorder }

    // ---- hero stats
    Card {
      width: parent.width
      Row {
        width: parent.width
        spacing: 8
        Stat { width: (parent.width - 16) / 3; url: Model.PAGES.fees; label: "Fees last 24h"; value: h.fees ? Model.fmtUsd(h.fees.period24h) : "—"; valueColor: h.cText; labelColor: h.cFaint; subColor: h.cSub; fontFamilies: root.fam }
        Stat {
          width: (parent.width - 16) / 3
          url: h.marketLink
          label: "FT price"
          value: h.price ? Model.fmtPrice(h.price.price) : "—"
          sub: h.price && isFinite(h.price.changePct24h) ? Model.fmtPct(h.price.changePct24h) + " 24h" : ""
          subColor: h.price ? h.deltaColor(h.price.changePct24h) : h.cSub
          valueColor: h.cText; labelColor: h.cFaint; fontFamilies: root.fam
        }
        Stat {
          width: (parent.width - 16) / 3
          url: Model.PAGES.fees
          label: "Day / day"
          readonly property real d: Model.feesDayOverDay(h.feesSeries)
          value: isFinite(d) ? Model.fmtPct(d) : "—"
          valueColor: isFinite(d) ? h.deltaColor(d) : h.cSub
          labelColor: h.cFaint; subColor: h.cSub; fontFamilies: root.fam
        }
      }
    }

    // ---- daily fees
    Card {
      width: parent.width
      url: Model.PAGES.fees
      Column {
        width: parent.width
        spacing: 8
        Cap { text: "Daily fees · last " + (h.feesSeries ? h.feesSeries.length : 31) + " days" }
        BarChart {
          width: parent.width
          height: 92
          visible: h.feesSeries !== null
          values: h.feesSeries ? h.feesSeries.map(function (d) { return d.total }) : []
          barColor: h.cTulip
          lastColor: h.cTulip300
          textColor: h.cFaint
          fontFamilies: root.fam
          maxLabel: h.feesSeries ? "max " + Model.fmtUsd(Math.max.apply(null, h.feesSeries.map(function (d) { return d.total }))) : ""
          startLabel: h.feesSeries ? h.feesSeries[0].date.slice(5) : ""
          endLabel: h.feesSeries ? h.feesSeries[h.feesSeries.length - 1].date.slice(5) : ""
        }
        Body { visible: h.feesSeries === null; text: "loading…" }
        // per-product split: stacked bar + legend
        Row {
          id: stack
          visible: h.fees !== null && h.fees.period24h > 0
          width: parent.width
          height: 6
          spacing: 2
          Repeater {
            model: h.fees ? h.fees.products.filter(function (p) { return p.usd > 0 }) : []
            Rectangle {
              width: Math.max(2, (stack.width - 2 * Math.max(0, stack.children.length - 2)) * modelData.usd / h.fees.period24h)
              height: 6
              radius: 3
              color: root.productColors[index % root.productColors.length]
            }
          }
        }
        Flow {
          width: parent.width
          spacing: 12
          visible: h.fees !== null
          Repeater {
            model: h.fees ? h.fees.products.filter(function (p) { return p.usd > 0 }) : []
            Row {
              spacing: 5
              Rectangle { width: 7; height: 7; radius: 3.5; color: root.productColors[index % root.productColors.length]; anchors.verticalCenter: parent.verticalCenter }
              Body { text: modelData.name.replace("_", " ") + " " + Model.fmtUsd(modelData.usd) }
            }
          }
        }
      }
    }

    // ---- FT market price
    Card {
      width: parent.width
      url: h.marketLink
      Column {
        width: parent.width
        spacing: 8
        Cap { text: "FT market price · 30 days" }
        LineChart {
          width: parent.width
          height: 92
          visible: h.klines !== null
          values: h.klines ? h.klines.map(function (k) { return k.close }) : []
          lineColor: h.cTulip400
          textColor: h.cFaint
          fontFamilies: root.fam
          formatValue: Model.fmtPrice
          startLabel: h.klines ? h.klines[0].date.slice(5) : ""
          endLabel: h.klines ? h.klines[h.klines.length - 1].date.slice(5) : ""
        }
        Body { visible: h.klines === null; text: "loading…" }
      }
    }

    // ---- no wallet: friendly prompt
    Card {
      visible: !h.walletValid
      width: parent.width
      url: Model.SITE
      Row {
        width: parent.width
        spacing: 12
        Column {
          width: parent.width - 120
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text { textFormat: Text.PlainText; text: "Add your wallet"; color: h.cText; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
          Text { width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText; text: "See health factor, PnL, FT earned, points and ftPUT gains here."; color: h.cSub; font.family: root.fam; font.pixelSize: 11 }
        }
        Rectangle {
          width: 100; height: 32; radius: 9
          anchors.verticalCenter: parent.verticalCenter
          color: setMa.containsMouse ? h.cTulip400 : h.cTulip
          Behavior on color { ColorAnimation { duration: 120 } }
          Text { anchors.centerIn: parent; text: "Set wallet"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
          MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: h.openEditor() }
        }
      }
    }

    // ---- wallet cards
    Column {
      visible: h.walletValid
      width: parent.width
      spacing: 10

      Card {
        width: parent.width
        url: Model.PAGES.health
        Column {
          width: parent.width
          spacing: 8
          Row {
            width: parent.width
            Cap { text: "Health factor"; width: parent.width - 120 }
            Body { text: "red line = liquidation < 1.25"; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; width: 120; color: h.cFaint }
          }
          Body { visible: h.accountAt === 0; text: "loading…" }
          Repeater {
            model: h.walletValid ? h.chains : []
            HfGauge {
              width: parent.width
              name: modelData.name
              hf: modelData.hf
              liqHf: modelData.liqHf
              warnHf: h.hfWarn
              critHf: h.hfCritical
              textColor: h.cText; subColor: h.cFaint
              okColor: h.cGreen; warnColor: h.cAmber; badColor: h.cRed
              fontFamilies: root.fam
            }
          }
        }
      }

      Grid {
        width: parent.width
        columns: 2
        spacing: 10
        readonly property real cw: (width - 10) / 2
        Card {
          width: parent.cw; url: Model.PAGES.portfolio
          Stat {
            width: parent.width
            label: "PnL (unrealized)"
            value: Model.fmtSignedUsd(h.totalPnl)
            valueColor: h.deltaColor(h.totalPnl)
            sub: Object.keys(h.pnlByChain).filter(function (k) { return Math.abs(h.pnlByChain[k]) >= 0.005 }).map(function (k) { return (Model.HF_CHAINS[k] || k) + " " + Model.fmtSignedUsd(h.pnlByChain[k]) }).join("  ")
            labelColor: h.cFaint; subColor: h.cSub; fontFamilies: root.fam; valueSize: 18
          }
        }
        Card {
          width: parent.cw; url: Model.PAGES.rewards
          Stat {
            width: parent.width
            label: "FT earned"
            value: Model.fmtFt(h.rewards ? h.rewards.totalFt : NaN) + " FT"
            sub: h.rewards && h.price && isFinite(h.rewards.totalFt) ? "≈ " + Model.fmtUsd(h.rewards.totalFt * h.price.price) + " at market" + (h.rewards.claimableFt > 0 ? "  ·  claim " + Model.fmtFt(h.rewards.claimableFt) : "") : ""
            valueColor: h.cTulip300
            labelColor: h.cFaint; subColor: h.cSub; fontFamilies: root.fam; valueSize: 18
          }
        }
        Card {
          width: parent.cw; url: Model.PAGES.points
          Stat {
            width: parent.width
            label: "Points"
            value: Model.fmtPoints(h.points ? h.points.total : NaN)
            sub: (h.rank ? "rank #" + h.rank.rank + " of " + h.rank.total : "") + (h.points && h.points.unclaimed > 0 && !h.rank ? "unclaimed " + Model.fmtPoints(h.points.unclaimed) : "")
            valueColor: h.cText
            labelColor: h.cFaint; subColor: h.cSub; fontFamilies: root.fam; valueSize: 18
          }
        }
        Card {
          width: parent.cw; url: Model.PAGES.put
          visible: h.putGain !== null
          Stat {
            width: parent.width
            label: "ftPUT gain"
            value: h.putGain ? Model.fmtSignedUsd(h.putGain.gainUsd) : "—"
            sub: h.putGain ? Model.fmtPct(h.putGain.gainPct) + "  ·  value " + Model.fmtUsd(h.putGain.valueUsd) : ""
            valueColor: h.putGain ? h.deltaColor(h.putGain.gainUsd) : h.cSub
            subColor: h.putGain ? h.deltaColor(h.putGain.gainUsd) : h.cSub
            labelColor: h.cFaint; fontFamilies: root.fam; valueSize: 18
          }
        }
      }

      Card {
        width: parent.width
        url: Model.PAGES.rewards
        Column {
          width: parent.width
          spacing: 8
          Row {
            width: parent.width
            Cap { text: "FT earned over time"; width: parent.width - 70 }
            Body { text: "all chains"; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; width: 70; color: h.cFaint }
          }
          Row {
            spacing: 6
            Pill { text: "Total earned"; selected: h.histSeries === "earned"; onClicked: h.histSeries = "earned" }
            Pill { text: "Claimed"; selected: h.histSeries === "claimed"; onClicked: h.histSeries = "claimed" }
          }
          LineChart {
            width: parent.width
            height: 96
            visible: h.rewardsSeries !== null && h.rewardsSeries.length > 1
            values: h.rewardsSeries ? h.rewardsSeries.map(function (d) { return d[h.histSeries] }) : []
            lineColor: h.histSeries === "earned" ? h.cTulip : "#249c91"
            textColor: h.cFaint
            fontFamilies: root.fam
            formatValue: Model.fmtFt
            startLabel: h.rewardsSeries ? h.rewardsSeries[0].date.slice(5) : ""
            endLabel: h.rewardsSeries ? h.rewardsSeries[h.rewardsSeries.length - 1].date.slice(5) : ""
          }
          Body { visible: h.rewardsSeries === null; text: "loading…"; color: h.cFaint }
          Body { visible: h.rewardsSeries !== null && h.rewardsSeries.length <= 1; text: "Not enough history yet."; color: h.cFaint }
          Row {
            spacing: 6
            Repeater {
              model: ["7d", "30d", "90d", "all"]
              Pill { text: modelData === "all" ? "All" : modelData; selected: h.histRange === modelData; onClicked: h.setHistRange(modelData) }
            }
          }
        }
      }

      Card {
        width: parent.width
        url: Model.PAGES.rewards
        visible: h.rewardsHist !== null && h.rewardsHist.length > 0
        Column {
          width: parent.width
          spacing: 8
          Cap { text: "Daily FT earned · last " + (h.rewardsHist ? h.rewardsHist.length : 30) + " days" }
          BarChart {
            width: parent.width
            height: 80
            values: h.rewardsHist ? h.rewardsHist.map(function (d) { return d.gain }) : []
            barColor: h.cTulip400
            lastColor: h.cTulip300
            textColor: h.cFaint
            fontFamilies: root.fam
            maxLabel: h.rewardsHist ? "max " + Model.fmtFt(Math.max.apply(null, h.rewardsHist.map(function (d) { return d.gain }))) + " FT" : ""
            startLabel: h.rewardsHist ? h.rewardsHist[0].date.slice(5) : ""
            endLabel: h.rewardsHist ? h.rewardsHist[h.rewardsHist.length - 1].date.slice(5) : ""
          }
        }
      }

      Card {
        width: parent.width
        url: Model.PAGES.portfolio
        Column {
          width: parent.width
          spacing: 8
          Row {
            width: parent.width
            Cap { text: "Positions"; width: parent.width - 80 }
            Body { text: h.positions.length > 0 ? h.positions.length + " open" : ""; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; width: 80; color: h.cFaint }
          }
          Body { visible: h.positionsLoaded && h.positions.length === 0; text: "No open positions."; color: h.cFaint }
          Body { visible: !h.positionsLoaded; text: "loading…"; color: h.cFaint }
          Flickable {
            visible: h.positions.length > 0
            width: parent.width
            height: Math.min(posCol.implicitHeight, 236)
            contentWidth: width
            contentHeight: posCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Column {
              id: posCol
              width: parent.width
              spacing: 6
              Repeater {
                model: h.positions
                Rectangle {
                  id: prow
                  width: posCol.width
                  height: 46
                  radius: 9
                  color: rowMa.containsMouse ? Qt.rgba(117 / 255, 89 / 255, 255, 0.10) : Qt.rgba(1, 1, 1, 0.025)
                  Behavior on color { ColorAnimation { duration: 120 } }
                  MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(Model.marketUrl(modelData.market || (modelData.symbol + "-ftUSD"), modelData.chainId)) }
                  Rectangle {
                    id: badge
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    color: Qt.rgba(117 / 255, 89 / 255, 255, 0.18)
                    border.width: 1; border.color: Qt.rgba(117 / 255, 89 / 255, 255, 0.4)
                    Text { anchors.centerIn: parent; visible: logo.status !== Image.Ready; text: modelData.symbol.slice(0, 1).toUpperCase(); color: h.cTulip300; font.family: root.fam; font.pixelSize: 12; font.weight: Font.Bold }
                    Image {
                      id: logo
                      anchors.centerIn: parent
                      width: 20; height: 20
                      sourceSize.width: 40; sourceSize.height: 40
                      asynchronous: true
                      source: "https://flyingtulip.com/assets/icons/chains-tokens/" + modelData.symbol.toLowerCase() + ".svg"
                    }
                  }
                  Column {
                    x: 44; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.40 - 44
                    spacing: 2
                    Row {
                      spacing: 5
                      Text { textFormat: Text.PlainText; text: modelData.symbol; color: h.cText; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                      Rectangle {
                        width: sideT.implicitWidth + 8; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.side === "long" ? Qt.rgba(15 / 255, 215 / 255, 39 / 255, 0.14) : Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.14)
                        Text { id: sideT; anchors.centerIn: parent; textFormat: Text.PlainText; text: modelData.side + (isFinite(modelData.leverage) && modelData.leverage > 0 ? " " + modelData.leverage.toFixed(modelData.leverage >= 10 ? 0 : 1) + "x" : ""); color: modelData.side === "long" ? h.cGreen : h.cRed; font.family: root.fam; font.pixelSize: 9; font.weight: Font.DemiBold }
                      }
                    }
                    Text { textFormat: Text.PlainText; text: modelData.network + "  " + Model.fmtSize(modelData.size); color: h.cFaint; font.family: root.fam; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                  }
                  Column {
                    x: parent.width * 0.40
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.32
                    spacing: 2
                    Text { textFormat: Text.PlainText; text: "mark " + Model.fmtPrice(modelData.mark); color: h.cSub; font.family: root.fam; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                    Text { textFormat: Text.PlainText; text: "entry " + Model.fmtPrice(modelData.entry); color: h.cFaint; font.family: root.fam; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                  }
                  Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.26
                    spacing: 2
                    Text { width: parent.width; horizontalAlignment: Text.AlignRight; textFormat: Text.PlainText; text: Model.fmtSignedUsd(modelData.pnlUsd); color: h.deltaColor(modelData.pnlUsd); font.family: root.fam; font.pixelSize: 12; font.weight: Font.Bold }
                    Text { width: parent.width; horizontalAlignment: Text.AlignRight; textFormat: Text.PlainText; text: Model.fmtPct(modelData.pnlPct); color: h.deltaColor(modelData.pnlUsd); font.family: root.fam; font.pixelSize: 10 }
                  }
                }
              }
            }
          }
        }
      }

      Card {
        width: parent.width
        url: Model.PAGES.pointsActivity
        visible: h.pointsRows.length > 0
        Column {
          width: parent.width
          spacing: 6
          Cap { text: "Points positions" }
          Repeater {
            model: h.pointsRows.slice(0, 6)
            Row {
              width: parent.width
              Body { width: parent.width * 0.5; text: modelData.label; color: h.cText }
              Body { width: parent.width * 0.3; text: Model.fmtUsd(modelData.positionUsd); horizontalAlignment: Text.AlignRight }
              Body { width: parent.width * 0.2; text: "x" + (isFinite(modelData.multiplier) ? modelData.multiplier.toFixed(2) : "?"); horizontalAlignment: Text.AlignRight; color: h.cTulip300 }
            }
          }
        }
      }

      Card {
        width: parent.width
        url: Model.PAGES.put
        visible: h.puts !== null
        Column {
          width: parent.width
          spacing: 6
          Cap { text: "ftPUT positions · cost = capital x price at investment" }
          Repeater {
            model: h.puts ? h.puts.rows.slice(0, 5) : []
            Row {
              width: parent.width
              Body { width: parent.width * 0.4; text: "#" + modelData.nft + " " + modelData.symbol; color: h.cText }
              Body { width: parent.width * 0.35; text: Model.fmtUsd(modelData.costUsd) + " @ " + Model.fmtPrice(modelData.strike); horizontalAlignment: Text.AlignRight }
              Body { width: parent.width * 0.25; text: modelData.since.slice(2); horizontalAlignment: Text.AlignRight }
            }
          }
          Body { visible: h.puts && h.puts.rows.length > 5; text: h.puts ? "+" + (h.puts.rows.length - 5) + " more" : ""; color: h.cFaint }
        }
      }
    }

    // ---- footer
    Rectangle { width: parent.width; height: 1; color: h.cBorder }
    Item {
      width: parent.width
      height: 20
      MouseArea {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: upd.implicitWidth
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: h.openUrl(Model.SITE)
      }
      Text {
        id: upd
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "updated " + (h.lastUpdate() > 0 ? Qt.formatTime(new Date(h.lastUpdate()), "hh:mm:ss") : "—") + (h.lastRefreshFailed ? "  · retrying" : "")
        color: h.lastRefreshFailed ? h.cAmber : h.cFaint
        font.family: root.fam
        font.pixelSize: 10
      }
      Text {
        id: dash
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Open flyingtulip.com →"
        color: dashMa.containsMouse ? h.cTulip300 : h.cTulip400
        font.family: root.fam
        font.pixelSize: 11
        Behavior on color { ColorAnimation { duration: 120 } }
        MouseArea { id: dashMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: h.openUrl(Model.SITE) }
      }
    }
  }
}
