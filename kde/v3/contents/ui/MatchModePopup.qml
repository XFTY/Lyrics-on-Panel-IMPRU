import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import "i18n.js" as I18n

PlasmaCore.Dialog {
    id: modePopup

    property string language: "zh_CN"
    property int currentMode: 0

    signal modeSelected(int mode)

    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.PopupMenu
    flags: Qt.WindowStaysOnTopHint
    hideOnWindowDeactivate: true

    readonly property var modeOptions: [
        { mode: 0, label: I18n.tr(modePopup.language, "全局模式") },
        { mode: 1, label: I18n.tr(modePopup.language, "浏览器模式") },
        { mode: 2, label: I18n.tr(modePopup.language, "串流音频软件匹配模式") },
        { mode: 3, label: I18n.tr(modePopup.language, "纯音乐模式") }
    ]

    mainItem: Rectangle {
        width: 230
        height: modeContent.implicitHeight + 16
        color: "#1e1e24"
        radius: 10
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        ColumnLayout {
            id: modeContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Text {
                text: I18n.tr(modePopup.language, "歌词匹配模式")
                color: "#a1a1aa"
                font.pixelSize: 11
                font.bold: true
                Layout.leftMargin: 8
                Layout.bottomMargin: 4
            }

            Repeater {
                model: modePopup.modeOptions

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 6
                    color: modePopup.currentMode === modelData.mode
                        ? Qt.rgba(0.114, 0.725, 0.329, 0.18)
                        : (optionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: modePopup.currentMode === modelData.mode ? "#1db954" : "#ffffff"
                        font.pixelSize: 12
                        font.bold: modePopup.currentMode === modelData.mode
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        color: "#1db954"
                        font.pixelSize: 12
                        font.bold: true
                        visible: modePopup.currentMode === modelData.mode
                    }

                    MouseArea {
                        id: optionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            modePopup.modeSelected(modelData.mode)
                            modePopup.visible = false
                        }
                    }
                }
            }
        }
    }
}
