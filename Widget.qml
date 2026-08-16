import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.douglas.omarchy-kefctl"
  property string icon: "󰓄"
  property string statusClass: "off"
  property string tooltip: "KEF · Offline"
  property bool popupOpen: false
  property string selectedIp: ""
  property var panel: ({ "connected": false, "speakers": [] })
  property string kefctlError: ""
  property int pendingVolume: 0
  readonly property string kefctlCommand: "/usr/bin/kefctl"
  readonly property bool connected: statusClass.indexOf("on") !== -1
  readonly property var sources: [
    { "id": "wifi", "label": "Wi-Fi" },
    { "id": "bluetooth", "label": "Bluetooth" },
    { "id": "tv", "label": "TV" },
    { "id": "optical", "label": "Optical" },
    { "id": "coaxial", "label": "Coaxial" },
    { "id": "analog", "label": "Analog" },
    { "id": "usb", "label": "USB" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    statusProcess.running = false
    statusProcess.running = true
  }

  function iconFor(status) {
    return String(status).indexOf("on") !== -1 ? "󰦢" : "󰓄"
  }

  function refreshPanel() {
    kefctlError = ""
    versionProcess.running = false
    versionProcess.running = true
  }

  function versionFromOutput(output) {
    var match = /(?:^|\s)(\d+)\.(\d+)\.(\d+)(?:\s|$)/.exec(output)
    return match ? match[1] + "." + match[2] + "." + match[3] : ""
  }

  function supportsPanel(version) {
    var parts = version.split(".")
    return Number(parts[0]) > 0
      || (Number(parts[0]) === 0 && Number(parts[1]) >= 7)
  }

  function loadPanel() {
    panelProcess.command = selectedIp === ""
      ? [kefctlCommand, "panel"]
      : [kefctlCommand, "--speaker", selectedIp, "panel"]
    panelProcess.running = true
  }

  function runAction(command, refreshAfter) {
    actionProcess.command = command
    actionProcess.refreshAfter = refreshAfter
    actionProcess.running = true
  }

  function setVolume(value) {
    if (!selectedIp)
      return
    pendingVolume = Math.max(0, Math.min(Math.round(value), panel.maxVolume || 100))
    panel.volume = pendingVolume
    volumeTimer.restart()
  }

  function close() {
    popupOpen = false
  }

  Process {
    id: statusProcess
    command: ["bash", "-c", root.kefctlCommand + " waybar 2>/dev/null || printf '%s\\n' '{\"alt\":\"off\",\"class\":\"off\",\"text\":\"󰓄\",\"tooltip\":\"KEF · Offline\"}'"]
    running: true
    stdout: SplitParser {
      property string buffer: ""
      onRead: function(data) { buffer += data }
    }
    onExited: {
      var raw = stdout.buffer.trim()
      stdout.buffer = ""
      try {
        var parsed = JSON.parse(raw)
        root.statusClass = parsed.class || parsed.alt || "off"
        root.icon = root.iconFor(root.statusClass)
        root.tooltip = parsed.tooltip || "KEF"
      } catch (e) {
        root.icon = "󰓄"
        root.statusClass = "off"
        root.tooltip = "KEF · Offline"
      }
    }
  }

  Process {
    id: versionProcess
    command: ["bash", "-c", "test -x " + root.kefctlCommand + " && " + root.kefctlCommand + " --version"]
    stdout: SplitParser {
      property string buffer: ""
      onRead: function(data) { buffer += data }
    }
    onExited: function(exitCode) {
      var raw = stdout.buffer.trim()
      stdout.buffer = ""
      var version = root.versionFromOutput(raw)
      if (exitCode !== 0 || version === "") {
        root.kefctlError = "The Kefctl AUR package is not installed. Install it with: yay -S kefctl"
        root.panel = { "connected": false, "speakers": [] }
      } else if (!root.supportsPanel(version)) {
        root.kefctlError = "kefctl " + version + " is installed. Update to 0.7.0 or newer."
        root.panel = { "connected": false, "speakers": [] }
      } else {
        root.loadPanel()
      }
    }
  }

  Process {
    id: panelProcess
    command: [root.kefctlCommand, "panel"]
    stdout: SplitParser {
      property string buffer: ""
      onRead: function(data) { buffer += data }
    }
    onExited: {
      var raw = stdout.buffer.trim()
      stdout.buffer = ""
      try {
        var parsed = JSON.parse(raw)
        root.panel = parsed
        if (parsed.ip)
          root.selectedIp = parsed.ip
      } catch (e) {
        root.panel = { "connected": false, "error": "Unable to read KEF status", "speakers": [] }
      }
    }
  }

  Process {
    id: actionProcess
    property bool refreshAfter: false
    command: ["bash", "-c", ""]
    onExited: {
      if (refreshAfter) {
        root.refresh()
        if (root.popupOpen)
          root.refreshPanel()
      }
    }
  }

  Timer {
    id: volumeTimer
    interval: 150
    repeat: false
    onTriggered: root.runAction([root.kefctlCommand, "--speaker", root.selectedIp, "volume", String(root.pendingVolume)], true)
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.tooltip
    foreground: Color.foreground
    dimmed: !root.connected
    useActiveColor: false
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton)
        root.runAction(["bash", "-c", "setsid uwsm-app -- ghostty --class=org.omarchy.Kefctl --title=kefctl -e " + root.kefctlCommand], false)
      else {
        root.popupOpen = !root.popupOpen
        if (root.popupOpen)
          root.refreshPanel()
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight)

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(8)

        BorderSurface {
          id: speakerIcon
          width: Style.space(40)
          height: Style.space(40)
          radius: Style.spacing.labelGap
          color: root.panel.standby
            ? "transparent"
            : Style.selectedFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: root.panel.standby ? "󰓄" : "󰓃"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.iconLarge
          }
        }

        Column {
          width: parent.width - speakerIcon.width - refreshButton.implicitWidth - closeButton.implicitWidth - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.kefctlError !== ""
              ? "Kefctl setup required"
              : (root.panel.connected ? (root.panel.name || "KEF") : "KEF Offline")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: root.panel.connected
              ? ((root.panel.model || "KEF") + " · " + (root.panel.ip || ""))
              : (root.kefctlError !== ""
                ? "Install or update the AUR package"
                : (root.panel.error || "Select a configured speaker"))
            color: Qt.darker(root.bar.foreground, 1.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Button {
          id: refreshButton
          iconText: "󰑐"
          tooltipText: "Refresh KEF status"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingY
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.refreshPanel()
        }
        Button {
          id: closeButton
          iconText: "󰅖"
          tooltipText: "Close KEF controls"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingY
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.close()
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      BorderSurface {
        visible: root.kefctlError !== ""
        width: parent.width
        implicitHeight: dependencyMessage.implicitHeight + Style.space(20)
        radius: Style.spacing.labelGap
        color: Style.selectedFillFor(root.bar.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

        Row {
          id: dependencyMessage
          anchors.centerIn: parent
          width: parent.width - Style.space(20)
          spacing: Style.space(8)

          Text {
            text: "󰀦"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.icon
          }

          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(2)

            Text {
              text: "Kefctl 0.7.0 required"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.kefctlError
              color: Qt.darker(root.bar.foreground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              width: parent.width
            }
          }
        }
      }

      Button {
        visible: root.kefctlError === ""
        width: parent.width
        iconText: root.panel.standby ? "󰐥" : "󰐤"
        text: root.panel.standby ? "Turn on speaker" : "Put speaker in standby"
        foreground: root.bar.foreground
        selected: !root.panel.standby
        bordered: true
        enabled: root.panel.connected && root.selectedIp !== ""
        onClicked: root.runAction([root.kefctlCommand, "--speaker", root.selectedIp, "toggle"], true)
      }

      Text {
        visible: root.kefctlError === ""
        text: "Speakers"
        color: Qt.darker(root.bar.foreground, 1.45)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
      Flow {
        visible: root.kefctlError === ""
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: root.panel.speakers || []
          delegate: Button {
            required property var modelData
            text: modelData.name
            foreground: root.bar.foreground
            selected: root.selectedIp === modelData.ip
            bordered: true
            onClicked: {
              root.selectedIp = modelData.ip
              root.refreshPanel()
            }
          }
        }
      }

      Text {
        visible: root.kefctlError === ""
        text: "Volume · " + String(root.panel.volume || 0) + "%"
        color: Qt.darker(root.bar.foreground, 1.45)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
      Row {
        visible: root.kefctlError === ""
        width: parent.width
        spacing: Style.space(6)

        PanelSlider {
          id: volumeSlider
          width: parent.width - muteButton.implicitWidth - Style.space(6)
          height: Math.max(implicitHeight, muteButton.implicitHeight)
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, Number(root.panel.maxVolume || 100))
          step: 1
          integer: true
          value: Number(root.panel.volume || 0)
          enabled: root.panel.connected && root.selectedIp !== ""
          opacity: root.panel.muted ? 0.5 : 1.0
          onMoved: value => root.setVolume(value)
          onReleased: value => root.setVolume(value)
          onRightClicked: root.runAction([root.kefctlCommand, "--speaker", root.selectedIp, "mute", root.panel.muted ? "off" : "on"], true)
        }

        Button {
          id: muteButton
          height: volumeSlider.height
          iconText: root.panel.muted ? "󰖁" : "󰕾"
          tooltipText: root.panel.muted ? "Unmute speaker" : "Mute speaker"
          foreground: root.bar.foreground
          selected: root.panel.muted
          bordered: true
          enabled: root.panel.connected && root.selectedIp !== ""
          onClicked: root.runAction([root.kefctlCommand, "--speaker", root.selectedIp, "mute", root.panel.muted ? "off" : "on"], true)
        }
      }

      Text {
        visible: root.kefctlError === ""
        text: "Source"
        color: Qt.darker(root.bar.foreground, 1.45)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
      Flow {
        visible: root.kefctlError === ""
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: root.sources
          delegate: Button {
            required property var modelData
            text: modelData.label
            foreground: root.bar.foreground
            selected: root.panel.source === modelData.id
            bordered: true
            enabled: root.panel.connected && root.selectedIp !== ""
            onClicked: root.runAction([root.kefctlCommand, "--speaker", root.selectedIp, "source", modelData.id], true)
          }
        }
      }
    }
  }
}
