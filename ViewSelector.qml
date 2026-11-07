import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Rectangle {
  id: root
  property var options: []
  property string value: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  signal chosen(string value)
  implicitHeight: segments.implicitHeight + Style.space(6)
  radius: Style.cornerRadius
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)

  Row {
    id: segments
    x: Style.space(3)
    y: Style.space(3)
    width: parent.width - Style.space(6)
    spacing: Style.space(4)
    Repeater {
      model: root.options
      Button {
        required property var modelData
        width: (segments.width - segments.spacing * (root.options.length - 1)) / root.options.length
        text: modelData.label
        iconText: modelData.icon || ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        active: root.value === modelData.value
        focusable: true
        onClicked: root.chosen(modelData.value)
      }
    }
  }
}
