import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import org.kde.plasma.core 2.0 as PlasmaCore
import "i18n.js" as I18n

PlasmaCore.Dialog {
    id: searchPopup

    property string language: "zh_CN"
    property string clientId: ""
    property string clientSecret: ""
    property var results: []
    property bool searching: false
    property string searchType: "track"

    signal searchRequested(string query, string type)
    signal playRequested(string uri)

    location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.PopupMenu
        flags: Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: true

        onVisibleChanged: {
            if (visible) {
                searchInput.forceActiveFocus()
                if (searchInput.text.trim() !== "") {
                    performSearch(searchInput.text)
                }
            } else {
                searchInput.text = ""
                results = []
                searching = false
            }
        }

        mainItem: Rectangle {
            id: searchPopupContainer

            Timer {
                id: searchDebounceTimer
                interval: 350
                running: false
                repeat: false
                onTriggered: searchPopup.performSearch(searchInput.text)
            }

            width: 350
            height: 420
            color: "#121215"
            radius: 14
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Top Header Badge
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#1db954"
                    }

                    Text {
                        text: "Spotify 快速搜索"
                        color: "#d4d4d8"
                        font.pixelSize: 11
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 34
                        height: 18
                        radius: 4
                        color: "#27272a"

                        Text {
                            anchors.centerIn: parent
                            text: "ESC"
                            color: "#71717a"
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }

                // Search Bar Input
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: "#1e1e24"
                    radius: 10
                    border.color: searchInput.activeFocus ? "#1db954" : Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "🔍"
                            font.pixelSize: 12
                            color: searchInput.activeFocus ? "#1db954" : "#71717a"
                        }

                        TextField {
                            id: searchInput
                            Layout.fillWidth: true
                            placeholderText: I18n.tr(searchPopup.language, "搜索歌曲或艺术家...")
                            placeholderTextColor: "#71717a"
                            color: "#ffffff"
                            font.pixelSize: 13
                            background: null
                            selectByMouse: true

                            onTextChanged: {
                                searchDebounceTimer.restart()
                            }

                            onAccepted: {
                                performSearch(text)
                            }
                        }

                        Rectangle {
                            visible: searchInput.text.length > 0
                            width: 20
                            height: 20
                            radius: 10
                            color: clearMouseArea.containsMouse ? "#3f3f46" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#a1a1aa"
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: clearMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = ""
                                    results = []
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // Type Selector Tabs (Only visible when Spotify API credentials are configured)
                RowLayout {
                    Layout.fillWidth: true
                    visible: clientId !== "" && clientSecret !== ""
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 7
                        color: searchType === "track" ? Qt.rgba(0.114, 0.725, 0.329, 0.2) : (trackTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                        border.color: searchType === "track" ? "#1db954" : Qt.rgba(1, 1, 1, 0.1)
                        border.width: searchType === "track" ? 1.5 : 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "🎵"
                                font.pixelSize: 11
                            }
                            Text {
                                text: I18n.tr(searchPopup.language, "歌曲")
                                color: searchType === "track" ? "#ffffff" : "#a1a1aa"
                                font.pixelSize: 11
                                font.bold: searchType === "track"
                            }
                        }

                        MouseArea {
                            id: trackTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (searchType !== "track") {
                                    searchType = "track"
                                    results = []
                                    searching = false
                                    if (searchInput.text.trim() !== "") {
                                        performSearch(searchInput.text)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 7
                        color: searchType === "playlist" ? Qt.rgba(0.114, 0.725, 0.329, 0.2) : (playlistTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                        border.color: searchType === "playlist" ? "#1db954" : Qt.rgba(1, 1, 1, 0.1)
                        border.width: searchType === "playlist" ? 1.5 : 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "📑"
                                font.pixelSize: 11
                            }
                            Text {
                                text: I18n.tr(searchPopup.language, "播放列表")
                                color: searchType === "playlist" ? "#ffffff" : "#a1a1aa"
                                font.pixelSize: 11
                                font.bold: searchType === "playlist"
                            }
                        }

                        MouseArea {
                            id: playlistTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (searchType !== "playlist") {
                                    searchType = "playlist"
                                    results = []
                                    searching = false
                                    performSearch(searchInput.text)
                                }
                            }
                        }
                    }
                }

                // Results Container
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Loading State
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: searching
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "⚡"
                            font.pixelSize: 22
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr(searchPopup.language, "正在 Spotify 中搜索...")
                            color: "#1db954"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    // Empty State (No Results)
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !searching && searchInput.text.trim() !== "" && results.length === 0
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "🔍"
                            font.pixelSize: 24
                            opacity: 0.6
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchType === "playlist" ? I18n.tr(searchPopup.language, "未找到播放列表") : I18n.tr(searchPopup.language, "未找到歌曲")
                            color: "#d4d4d8"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchType === "playlist" ? I18n.tr(searchPopup.language, "试试用其他播放列表名称搜索") : I18n.tr(searchPopup.language, "试试用其他歌曲名或艺术家搜索")
                            color: "#71717a"
                            font.pixelSize: 11
                        }
                    }

                    // Initial Guide State
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !searching && searchInput.text.trim() === "" && results.length === 0
                        spacing: 6
                        width: parent.width - 40

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchType === "playlist" ? "📑" : "🎵"
                            font.pixelSize: 28
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchType === "playlist" ? I18n.tr(searchPopup.language, "搜索任意播放列表") : I18n.tr(searchPopup.language, "搜索任意歌曲")
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchType === "playlist" ? I18n.tr(searchPopup.language, "输入内容以查找并在 Spotify 中播放播放列表") : I18n.tr(searchPopup.language, "输入内容以直接在 Spotify 中播放")
                            color: "#71717a"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // Results List
                    ListView {
                        id: resultsListView
                        anchors.fill: parent
                        visible: !searching && results.length > 0
                        model: results
                        spacing: 4
                        clip: true

                        header: Item {
                            width: resultsListView.width
                            height: searchType === "playlist" && searchInput.text.trim() === "" ? 24 : 0
                            visible: searchType === "playlist" && searchInput.text.trim() === ""

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr(searchPopup.language, "📚 你的播放列表库")
                                color: "#1db954"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        delegate: Rectangle {
                            width: resultsListView.width
                            height: 50
                            color: itemMouseArea.containsMouse ? "#22222a" : "transparent"
                            radius: 8

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 10
                                spacing: 10

                                // Album Art Thumbnail
                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 6
                                    color: "#1e1e24"
                                    clip: true
                                    border.color: Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.art_url || ""
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        mipmap: true
                                        asynchronous: true
                                    }
                                }

                                // Track Information
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.title || ""
                                        color: itemMouseArea.containsMouse ? "#1db954" : "#ffffff"
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true

                                        Behavior on color {
                                            ColorAnimation { duration: 100 }
                                        }
                                    }

                                    Text {
                                        text: modelData.artist || ""
                                        color: "#a1a1aa"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Right side: Duration / Playlist Badge or Play Indicator
                                Item {
                                    Layout.preferredWidth: modelData.item_type === "playlist" ? 64 : 36
                                    Layout.preferredHeight: 24

                                    // Duration (for tracks)
                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !itemMouseArea.containsMouse && modelData.item_type !== "playlist"
                                        text: formatTrackDuration(modelData.duration_ms)
                                        color: "#71717a"
                                        font.pixelSize: 11
                                    }

                                    // Playlist tag (for playlists)
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !itemMouseArea.containsMouse && modelData.item_type === "playlist"
                                        width: 58
                                        height: 18
                                        radius: 4
                                        color: Qt.rgba(0.114, 0.725, 0.329, 0.15)
                                        border.color: Qt.rgba(0.114, 0.725, 0.329, 0.3)
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "播放列表"
                                            color: "#1db954"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    // Hover Play Button
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: itemMouseArea.containsMouse
                                        width: 26
                                        height: 26
                                        radius: 13
                                        color: "#1db954"

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.horizontalCenterOffset: 1
                                            text: "▶"
                                            color: "#000000"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: itemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchPopup.playTrack(modelData.uri)
                                }
                            }
                        }
                    }
                }

                // API Key setup hint
                Text {
                    visible: !clientId || !clientSecret
                    Layout.fillWidth: true
                    text: I18n.tr(searchPopup.language, "💡 在设置中配置 Spotify Client ID 即可一键精确播放。")
                    color: "#71717a"
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }

    function formatTrackDuration(ms) {
        if (!ms || ms <= 0) return ""
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        return min + ":" + (sec < 10 ? "0" : "") + sec
    }

    function performSearch(query) {
        var cleanQ = query ? query.trim() : ""
        if (cleanQ === "" && searchType !== "playlist") {
            results = []
            searching = false
            return
        }
        searching = true
        searchPopup.searchRequested(cleanQ, searchType)
    }

    function playTrack(uri) {
        searchPopup.visible = false
        searchPopup.playRequested(uri)
    }

    function setResults(type, items) {
        if (!type || type === searchType) {
            results = items || []
            searching = false
        }
    }
}
