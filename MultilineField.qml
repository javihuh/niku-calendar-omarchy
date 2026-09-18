import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property string label: ""
  property alias text: editor.text
  property string placeholderText: ""
  property int maximumLength: 0
  property real fieldHeight: Style.space(112)
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property bool editorActive: editor.activeFocus

  signal escapePressed()

  implicitHeight: fieldHeight + (labelText.visible ? labelText.implicitHeight + content.spacing : 0)

  Column {
    id: content
    width: parent.width
    spacing: Style.spacing.labelGap

    Text {
      id: labelText
      textFormat: Text.PlainText
      visible: root.label !== ""
      width: parent.width
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: fieldSurface
      width: parent.width
      height: root.fieldHeight
      radius: Style.cornerRadius
      clip: true

      readonly property bool hot: fieldHover.hovered
      readonly property var fieldBorder: Border.controlSpec(
        editor.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
        root.foreground,
        root.accent)

      color: Style.controlFill(editor.activeFocus, hot, root.foreground, root.accent)
      borderSpec: fieldBorder

      HoverHandler { id: fieldHover }

      Flickable {
        id: editorScroll
        anchors.fill: parent
        anchors.topMargin: fieldSurface.borderTop + Style.spacing.inputPaddingY
        anchors.rightMargin: fieldSurface.borderRight + Style.spacing.controlPaddingX
        anchors.bottomMargin: fieldSurface.borderBottom + Style.spacing.inputPaddingY
        anchors.leftMargin: fieldSurface.borderLeft + Style.spacing.controlPaddingX
        contentWidth: width
        contentHeight: Math.max(height, editor.height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        function revealCursor() {
          var top = editor.cursorRectangle.y
          var bottom = top + editor.cursorRectangle.height
          if (top < contentY)
            contentY = Math.max(0, top)
          else if (bottom > contentY + height)
            contentY = Math.min(contentHeight - height, bottom - height)
        }

        TextEdit {
          id: editor
          width: editorScroll.width
          height: Math.max(editorScroll.height, contentHeight)
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          persistentSelection: true
          activeFocusOnTab: true
          color: root.foreground
          selectionColor: Style.selectionFillFor(root.foreground, root.accent)
          selectedTextColor: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body

          onTextChanged: {
            if (root.maximumLength > 0 && text.length > root.maximumLength) {
              var position = cursorPosition
              text = text.slice(0, root.maximumLength)
              cursorPosition = Math.min(position, text.length)
            }
          }
          onCursorRectangleChanged: editorScroll.revealCursor()
          Keys.onEscapePressed: function(event) {
            root.escapePressed()
            event.accepted = true
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: editor.text.length === 0 && !editor.activeFocus
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.placeholderText
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: Qt.IBeamCursor
        onClicked: editor.forceActiveFocus()
      }
    }
  }
}
