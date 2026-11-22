import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import QtWebSockets

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import "i18n.js" as I18n

/**
 * Lyrics on Panel for KDE Plasma 6 - v2.0.0
 *
 * This version uses a WebSocket connection to communicate with a Python backend
 * server that handles MPRIS2 interactions and lyrics fetching.
 *
 * Backend endpoints:
 *   ws://127.0.0.1:23560/poll    - Poll for player state and lyrics
 *   ws://127.0.0.1:23560/control - Send playback control commands
 */

PlasmoidItem {
    id: root

    width: animatedWidth
    implicitWidth: animatedWidth
    implicitHeight: (lyricColumn ? lyricColumn.height : 0) + 8
    height: implicitHeight

    FontMetrics {
        id: lyricFontMetrics
        font.pixelSize: actualFontSize
        font.bold: config_lyricTextBold
        font.italic: config_lyricTextItalic
    }

    readonly property real targetWidth: {
        var iconsW = iconsContainer ? iconsContainer.Layout.preferredWidth : 120;
        var minW = iconsW + config_mediaControllSpacing + 16;
        var parsedWidth = config_preferedWidgetWidth;

        if (config_dynamicWidth) {
            var maxCap = (parsedWidth && parsedWidth > 850) ? parsedWidth : 2000;
            var currentText = displayedLyric || lrc_not_exists;
            var textW = lyricFontMetrics.advanceWidth(currentText) + 36;
            if (config_showNextLyric && displayedNextLyric) {
                var nextW = lyricFontMetrics.advanceWidth(displayedNextLyric) * 0.8 + 36;
                textW = Math.max(textW, nextW);
            }
            var needed = textW + minW;
            return Math.min(maxCap, Math.max(minW, needed));
        } else {
            var userW = (parsedWidth && parsedWidth > 0) ? parsedWidth : 850;
            return Math.max(minW, userW);
        }
    }

    property real animatedWidth: targetWidth

    readonly property real karaokeTextWidth: lyricFontMetrics.advanceWidth(displayedLyric)

    readonly property real karaokeTextStartX: {
        if (config_lyricTextAlignment === 0)
            return 0
        if (config_lyricTextAlignment === 1)
            return Math.max(0, (currentLyricText.width - karaokeTextWidth) / 2)
        return Math.max(0, currentLyricText.width - karaokeTextWidth)
    }

    readonly property var karaokeWordItems: {
        var words = currentWords
        if (!words || words.length === 0)
            return []
        var items = []
        var prefix = ""
        var startX = karaokeTextStartX
        for (var i = 0; i < words.length; i++) {
            var start = words[i].time_ms || 0
            var end
            if (i + 1 < words.length) {
                var nextStart = words[i + 1].time_ms || 0
                end = nextStart > start ? nextStart : start + 1
            } else {
                end = currentLineEndMs
                if (end <= start) {
                    var fallbackEnd = currentLineStartMs + currentLyricDurationMs
                    end = fallbackEnd > start ? fallbackEnd : start + 300
                }
            }
            items.push({
                text: words[i].text,
                x: startX + lyricFontMetrics.advanceWidth(prefix),
                width: lyricFontMetrics.advanceWidth(words[i].text),
                time_ms: start,
                end_ms: end
            })
            prefix += words[i].text
        }
        return items
    }

    readonly property real karaokeHighlightWidth: {
        if (!karaokeOverlayVisible)
            return 0
        var items = karaokeWordItems
        if (items.length === 0)
            return 0
        var timeMs = karaokeTimeMs
        var textStartX = karaokeTextStartX
        var boundary = 0
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (timeMs < item.time_ms)
                break
            var progress = 1
            if (timeMs < item.end_ms && item.end_ms > item.time_ms)
                progress = (timeMs - item.time_ms) / (item.end_ms - item.time_ms)
            var itemEndX = item.x - textStartX + item.width * progress
            if (itemEndX > boundary)
                boundary = itemEndX
            if (progress < 1)
                break
        }
        return Math.max(0, Math.min(karaokeTextWidth, boundary))
    }

    Behavior on animatedWidth {
        NumberAnimation {
            duration: (config_transitionDurationMs > 0 && config_dynamicWidth) ? Math.min(300, config_transitionDurationMs) : 200
            easing.type: Easing.InOutQuad
        }
    }

    preferredRepresentation: fullRepresentation
    Layout.preferredWidth: animatedWidth
    Layout.maximumWidth: {
        var parsedWidth = config_preferedWidgetWidth;
        if (config_dynamicWidth) {
            return (parsedWidth && parsedWidth > 850) ? parsedWidth : 2000;
        } else {
            return (parsedWidth && parsedWidth > 0) ? parsedWidth : 850;
        }
    }
    Layout.preferredHeight: height

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    Plasmoid.status: (config_playerMode !== 0 && !hasActivePlayer)
        ? PlasmaCore.Types.HiddenStatus
        : (hasActivePlayer || !config_hideItemWhenNoControlChecked
            ? PlasmaCore.Types.ActiveStatus
            : PlasmaCore.Types.HiddenStatus)

    RowLayout {
        anchors.fill: parent
        spacing: config_mediaControllSpacing

        Item {
            id: lyricTextContainer
            Layout.fillWidth: true
            Layout.preferredHeight: lyricColumn.height
            Layout.minimumHeight: lyricColumn.height
            clip: false

            onWidthChanged: {
                if (lyricBounceAnimation.running) {
                    lyricBounceAnimation.stop()
                    restartTimer.start()
                }
            }

            SequentialAnimation {
                id: lyricBounceAnimation
                running: config_enableTextScrolling && lyricColumn.width > lyricTextContainer.width && playbackStatus === "playing"
                loops: Animation.Infinite

                PauseAnimation { duration: 300 }

                PropertyAnimation {
                    target: lyricColumn
                    property: "xPosition"
                    from: 0
                    to: lyricTextContainer.width - lyricColumn.width
                    duration: animationDuration
                    easing.type: Easing.Linear
                }

                PauseAnimation { duration: 1500 }

                PropertyAnimation {
                    target: lyricColumn
                    property: "xPosition"
                    from: lyricTextContainer.width - lyricColumn.width
                    to: 0
                    duration: animationDuration
                    easing.type: Easing.Linear
                }

                PauseAnimation { duration: 500 }
            }

            Timer {
                id: restartTimer
                interval: 50
                running: false
                repeat: false
                onTriggered: {
                    if (config_enableTextScrolling && lyricColumn.width > lyricTextContainer.width && playbackStatus === "playing") {
                        lyricColumn.xPosition = 0
                        lyricBounceAnimation.start()
                    }
                }
            }

            Item {
                id: lyricColumn
                width: lyricTextContainer.width
                height: (currentLyricText ? currentLyricText.contentHeight : 0) + ((nextLyricText && nextLyricText.visible) ? (nextLyricText.contentHeight * 0.85 + 2) : 0)
                
                y: {
                    var centerY = (lyricTextContainer.height - height) / 2;
                    return Math.max(2, centerY) + config_lyricTextVerticalOffset;
                }

                Behavior on y {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }

                Text {
                    id: currentLyricText
                    text: displayedLyric || lrc_not_exists
                    color: karaokeOverlayVisible ? "#9a9a9a" : config_lyricTextColor
                    font.pixelSize: actualFontSize
                    font.bold: config_lyricTextBold
                    font.italic: config_lyricTextItalic
                    renderType: Text.NativeRendering
                    elide: config_enableTextScrolling ? Text.ElideNone : Text.ElideRight
                    width: parent.width
                    
                    anchors.top: parent.top

                    horizontalAlignment: {
                        if (config_lyricTextAlignment === 0) return Text.AlignLeft;
                        if (config_lyricTextAlignment === 1) return Text.AlignHCenter;
                        return Text.AlignRight;
                    }

                    transform: Translate {
                        id: currentTranslate
                        y: 0
                    }

                    Item {
                        id: karaokeWordsLayer
                        x: 0
                        y: 0
                        width: currentLyricText.width
                        height: currentLyricText.height
                        clip: true
                        visible: karaokeOverlayVisible

                        Item {
                            x: karaokeTextStartX
                            y: 0
                            width: karaokeHighlightWidth
                            height: parent.height
                            clip: true

                            Text {
                                x: 0
                                y: 0
                                width: karaokeTextWidth
                                height: parent.height
                                text: displayedLyric
                                color: config_lyricTextColor
                                font.pixelSize: actualFontSize
                                font.bold: config_lyricTextBold
                                font.italic: config_lyricTextItalic
                                renderType: Text.NativeRendering
                                horizontalAlignment: Text.AlignLeft
                                wrapMode: Text.NoWrap
                            }
                        }
                    }
                }

                Text {
                    id: nextLyricText
                    text: displayedNextLyric
                    color: config_lyricTextColor
                    font.pixelSize: actualFontSize
                    font.bold: config_lyricTextBold
                    font.italic: config_lyricTextItalic
                    renderType: Text.NativeRendering
                    opacity: config_nextLyricOpacity
                    visible: config_showNextLyric && !scrollingLyricsActive && displayedLyric && displayedNextLyric
                    elide: config_enableTextScrolling ? Text.ElideNone : Text.ElideRight
                    width: parent.width
                    
                    anchors.top: currentLyricText.bottom
                    anchors.topMargin: 2

                    horizontalAlignment: currentLyricText.horizontalAlignment

                    transform: [
                        Translate {
                            id: nextTranslate
                            y: 0
                        },
                        Scale {
                            id: nextScale
                            xScale: 0.85
                            yScale: 0.85
                            origin.x: {
                                if (config_lyricTextAlignment === 0) return 0;
                                if (config_lyricTextAlignment === 1) return nextLyricText.width / 2;
                                return nextLyricText.width;
                            }
                            origin.y: 0
                        }
                    ]
                }
            }
        }

        RowLayout {
            id: iconsContainer
            Layout.preferredWidth: 3 * config_mediaControllItemSize + (config_showAlbumCover && currentArtUrl !== "" ? (config_albumCoverItemSize + config_mediaControllSpacing) : 0) + 2 * config_mediaControllSpacing
            Layout.preferredHeight: Math.max(config_mediaControllItemSize, config_albumCoverItemSize)
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 1
            spacing: config_mediaControllSpacing

            Image {
                source: backwardIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("previous")
                }
            }

            Image {
                source: (playbackStatus === "playing") ? pauseIcon : playIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("play_pause")
                }
            }

            Image {
                source: forwardIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("next")
                }
            }

            Item {
                id: mediaPlayerIconContainer
                width: config_albumCoverItemSize
                height: config_albumCoverItemSize
                visible: config_showAlbumCover && currentArtUrl !== ""

                Rectangle {
                    anchors.fill: parent
                    radius: Math.max(2, Math.round(config_albumCoverItemSize * 0.2))
                    color: "transparent"
                    clip: true

                    Image {
                        id: mediaPlayerIcon
                        anchors.fill: parent
                        source: (config_showAlbumCover && displayedArtUrl !== "") ? displayedArtUrl : ""
                        sourceSize.width: config_albumCoverItemSize * 2
                        sourceSize.height: config_albumCoverItemSize * 2
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        transformOrigin: Item.Center
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: config_enableSpotifySearch
                    cursorShape: config_enableSpotifySearch ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (config_enableSpotifySearch) {
                            var pos = mediaPlayerIconContainer.mapToGlobal(0, mediaPlayerIconContainer.height)
                            spotifySearchPopup.x = pos.x - (320 - mediaPlayerIconContainer.width) / 2
                            spotifySearchPopup.y = pos.y + 6
                            spotifySearchPopup.visible = !spotifySearchPopup.visible
                        }
                    }
                }
            }
        }
    }

    PlasmaCore.Dialog {
        id: spotifySearchPopup
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
                spotifySearchResults = []
                spotifySearching = false
            }
        }

        mainItem: Rectangle {
            id: searchPopupContainer
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
                            placeholderText: I18n.tr(root.config_language, "搜索歌曲或艺术家...")
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
                                    spotifySearchResults = []
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // Type Selector Tabs (Only visible when Spotify API credentials are configured)
                RowLayout {
                    Layout.fillWidth: true
                    visible: config_spotifyClientId !== "" && config_spotifyClientSecret !== ""
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 7
                        color: selectedSearchType === "track" ? Qt.rgba(0.114, 0.725, 0.329, 0.2) : (trackTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                        border.color: selectedSearchType === "track" ? "#1db954" : Qt.rgba(1, 1, 1, 0.1)
                        border.width: selectedSearchType === "track" ? 1.5 : 1

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
                                text: I18n.tr(root.config_language, "歌曲")
                                color: selectedSearchType === "track" ? "#ffffff" : "#a1a1aa"
                                font.pixelSize: 11
                                font.bold: selectedSearchType === "track"
                            }
                        }

                        MouseArea {
                            id: trackTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (selectedSearchType !== "track") {
                                    selectedSearchType = "track"
                                    spotifySearchResults = []
                                    spotifySearching = false
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
                        color: selectedSearchType === "playlist" ? Qt.rgba(0.114, 0.725, 0.329, 0.2) : (playlistTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                        border.color: selectedSearchType === "playlist" ? "#1db954" : Qt.rgba(1, 1, 1, 0.1)
                        border.width: selectedSearchType === "playlist" ? 1.5 : 1

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
                                text: I18n.tr(root.config_language, "播放列表")
                                color: selectedSearchType === "playlist" ? "#ffffff" : "#a1a1aa"
                                font.pixelSize: 11
                                font.bold: selectedSearchType === "playlist"
                            }
                        }

                        MouseArea {
                            id: playlistTabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (selectedSearchType !== "playlist") {
                                    selectedSearchType = "playlist"
                                    spotifySearchResults = []
                                    spotifySearching = false
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
                        visible: spotifySearching
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "⚡"
                            font.pixelSize: 22
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr(root.config_language, "正在 Spotify 中搜索...")
                            color: "#1db954"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    // Empty State (No Results)
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !spotifySearching && searchInput.text.trim() !== "" && spotifySearchResults.length === 0
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "🔍"
                            font.pixelSize: 24
                            opacity: 0.6
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: selectedSearchType === "playlist" ? I18n.tr(root.config_language, "未找到播放列表") : I18n.tr(root.config_language, "未找到歌曲")
                            color: "#d4d4d8"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: selectedSearchType === "playlist" ? I18n.tr(root.config_language, "试试用其他播放列表名称搜索") : I18n.tr(root.config_language, "试试用其他歌曲名或艺术家搜索")
                            color: "#71717a"
                            font.pixelSize: 11
                        }
                    }

                    // Initial Guide State
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !spotifySearching && searchInput.text.trim() === "" && spotifySearchResults.length === 0
                        spacing: 6
                        width: parent.width - 40

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: selectedSearchType === "playlist" ? "📑" : "🎵"
                            font.pixelSize: 28
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: selectedSearchType === "playlist" ? I18n.tr(root.config_language, "搜索任意播放列表") : I18n.tr(root.config_language, "搜索任意歌曲")
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: selectedSearchType === "playlist" ? I18n.tr(root.config_language, "输入内容以查找并在 Spotify 中播放播放列表") : I18n.tr(root.config_language, "输入内容以直接在 Spotify 中播放")
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
                        visible: !spotifySearching && spotifySearchResults.length > 0
                        model: spotifySearchResults
                        spacing: 4
                        clip: true

                        header: Item {
                            width: resultsListView.width
                            height: selectedSearchType === "playlist" && searchInput.text.trim() === "" ? 24 : 0
                            visible: selectedSearchType === "playlist" && searchInput.text.trim() === ""

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr(root.config_language, "📚 你的播放列表库")
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
                                    playSpotifyTrack(modelData.uri)
                                }
                            }
                        }
                    }
                }

                // API Key setup hint
                Text {
                    visible: !config_spotifyClientId || !config_spotifyClientSecret
                    Layout.fillWidth: true
                    text: I18n.tr(root.config_language, "💡 在设置中配置 Spotify Client ID 即可一键精确播放。")
                    color: "#71717a"
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
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

    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"

    property bool config_showAlbumCover: Plasmoid.configuration.showAlbumCover
    property bool config_enableSpotifySearch: Plasmoid.configuration.enableSpotifySearch !== undefined ? Plasmoid.configuration.enableSpotifySearch : true
    property string config_spotifyClientId: Plasmoid.configuration.spotifyClientId || ""
    property string config_spotifyClientSecret: Plasmoid.configuration.spotifyClientSecret || ""
    property int config_lyricTextSize: Plasmoid.configuration.lyricTextSize
    property int baseFontSize: config_lyricTextSize
    property int actualFontSize: {
        var hSize = baseFontSize;
        if (!config_dynamicWidth && !config_enableTextScrolling && lyricTextContainer && lyricTextContainer.width > 50) {
            var currentText = displayedLyric || lrc_not_exists;
            var textW = lyricFontMetrics.advanceWidth(currentText) + 24;
            if (config_showNextLyric && displayedNextLyric) {
                var nextW = lyricFontMetrics.advanceWidth(displayedNextLyric) * 0.8 + 24;
                textW = Math.max(textW, nextW);
            }
            if (textW > lyricTextContainer.width) {
                var ratio = lyricTextContainer.width / textW;
                var fittedSize = Math.floor(hSize * ratio);
                return Math.max(8, fittedSize);
            }
        }
        return hSize;
    }
    property int config_languageIndex: Plasmoid.configuration.languageIndex !== undefined ? Plasmoid.configuration.languageIndex : 0
    property string config_language: I18n.languageForIndex(config_languageIndex)
    property string config_lyricTextColor: Plasmoid.configuration.lyricTextColor || "#ffffff"
    property bool config_lyricTextBold: Plasmoid.configuration.lyricTextBold
    property bool config_lyricTextItalic: Plasmoid.configuration.lyricTextItalic
    property int config_lyricTextVerticalOffset: Plasmoid.configuration.lyricTextVerticalOffset
    property int config_lyricTextAlignment: Plasmoid.configuration.lyricTextAlignment !== undefined ? Plasmoid.configuration.lyricTextAlignment : 2

    property int config_mediaControllSpacing: Plasmoid.configuration.mediaControllSpacing
    property int config_mediaControllItemSize: Plasmoid.configuration.mediaControllItemSize
    property int config_albumCoverItemSize: Plasmoid.configuration.albumCoverItemSize > 0 ? Plasmoid.configuration.albumCoverItemSize : 18
    property int config_mediaControllItemVerticalOffset: Plasmoid.configuration.mediaControllItemVerticalOffset

    property bool config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked
    property int config_preferedWidgetWidth: Plasmoid.configuration.preferedWidgetWidth > 0 ? Plasmoid.configuration.preferedWidgetWidth : 850
    property bool config_dynamicWidth: Plasmoid.configuration.dynamicWidth !== undefined ? Plasmoid.configuration.dynamicWidth : true
    property bool config_enableTextScrolling: Plasmoid.configuration.enableTextScrolling !== undefined ? Plasmoid.configuration.enableTextScrolling : false
    property bool config_hideItemWhenNoControlChecked: Plasmoid.configuration.hideItemWhenNoControlChecked !== undefined ? Plasmoid.configuration.hideItemWhenNoControlChecked : true
    property int config_playerMode: Plasmoid.configuration.playerMode !== undefined ? Plasmoid.configuration.playerMode : 0
    property bool config_convertToSimplified: Plasmoid.configuration.convertToSimplified !== undefined ? Plasmoid.configuration.convertToSimplified : false
    property bool config_scrollingLyrics: Plasmoid.configuration.scrollingLyrics !== undefined ? Plasmoid.configuration.scrollingLyrics : false
    property bool config_karaokeLyrics: Plasmoid.configuration.karaokeLyrics !== undefined ? Plasmoid.configuration.karaokeLyrics : true
    property int config_karaokeFrameRate: {
        var fps = Plasmoid.configuration.karaokeFrameRate
        if (!fps || fps <= 0)
            return 60
        return Math.max(10, Math.min(120, fps))
    }

    property bool config_showNextLyric: Plasmoid.configuration.showNextLyric !== undefined ? Plasmoid.configuration.showNextLyric : false
    property int config_syncOffsetMs: Plasmoid.configuration.syncOffsetMs
    property int config_transitionDurationMs: Plasmoid.configuration.transitionDurationMs
    property double config_nextLyricOpacity: Plasmoid.configuration.nextLyricOpacity

    readonly property string serverHost: "127.0.0.1"
    readonly property int serverPort: 23560

    property string playbackStatus: "stopped"
    property string currentLyric: ""
    property string nextLyric: ""
    property int currentLyricDurationMs: 0
    property int timeRemainingMs: 0
    property string displayedLyric: ""
    property string displayedNextLyric: ""
    property bool hasSyncedLyrics: false
    property bool hasWordLyrics: false
    property var currentWords: []
    property int currentLineStartMs: 0
    property int currentLineEndMs: 0
    property var nextWords: []
    property bool nextHasWordLyrics: false
    property int nextLineStartMs: 0
    property int nextLineEndMs: 0
    property string afterNextLyric: ""
    property var afterNextWords: []
    property bool afterNextHasWordLyrics: false
    property int afterNextLineStartMs: 0
    property int afterNextLineEndMs: 0
    property real karaokeBasePositionMs: 0
    property double karaokeBaseTimestamp: 0
    property real karaokePositionMs: 0
    readonly property real karaokeTimeMs: karaokePositionMs + config_syncOffsetMs
    readonly property bool karaokeLyricsActive: config_karaokeLyrics && hasWordLyrics && currentWords.length > 0 && currentLyric !== ""
    readonly property bool karaokeOverlayVisible: karaokeLyricsActive && displayedLyric === currentLyric && currentWords.length > 0
    readonly property bool karaokeTimingActive: config_karaokeLyrics && playbackStatus === "playing" && (karaokeLyricsActive || nextLineStartMs > 0)
    readonly property bool scrollingLyricsActive: config_scrollingLyrics && hasSyncedLyrics && currentLyric !== "" && !karaokeLyricsActive

    property string currentTitle: ""
    property string currentArtist: ""
    property string currentAlbum: ""
    property string currentArtUrl: ""
    property string displayedArtUrl: currentArtUrl

    onCurrentArtUrlChanged: {
        if (config_showAlbumCover && currentArtUrl !== "" && displayedArtUrl !== "") {
            artChangeAnimation.restart()
        } else {
            displayedArtUrl = currentArtUrl
        }
    }

    SequentialAnimation {
        id: artChangeAnimation
        
        ParallelAnimation {
            NumberAnimation {
                target: mediaPlayerIcon
                property: "opacity"
                to: 0.0
                duration: 160
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: mediaPlayerIcon
                property: "scale"
                to: 0.75
                duration: 160
                easing.type: Easing.InQuad
            }
        }
        
        ScriptAction {
            script: {
                displayedArtUrl = currentArtUrl
            }
        }
        
        ParallelAnimation {
            NumberAnimation {
                target: mediaPlayerIcon
                property: "opacity"
                to: 1.0
                duration: 240
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: mediaPlayerIcon
                property: "scale"
                to: 1.0
                duration: 240
                easing.type: Easing.OutBack
            }
        }
    }
    property string currentPlayerIdentity: ""
    property string currentPlayerBusName: ""
    property int positionMs: 0
    property bool hasActivePlayer: false
    property var availablePlayers: []
    property string selectedPlayer: ""
    property int animationDuration: {
        var overflow = Math.abs(lyricColumn.width - lyricTextContainer.width);
        var defaultDuration = Math.max(2000, overflow / 60 * 1000);
        if (playbackStatus !== "playing" || timeRemainingMs <= 0) {
            return defaultDuration;
        }
        var adjustedRemaining = timeRemainingMs + config_syncOffsetMs;
        if (adjustedRemaining < 3000) {
            return Math.max(1200, defaultDuration * 0.5);
        }
        var targetDuration = (adjustedRemaining - 2500) / 2;
        return Math.max(1500, Math.min(defaultDuration, targetDuration));
    }

    property string requestedPlayer: {
        return selectedPlayer ? selectedPlayer : ""
    }

    property string lrc_not_exists: {
        if (currentTitle && currentArtist) {
            return currentTitle + " - " + currentArtist
        } else if (currentTitle) {
            return currentTitle
        } else {
            return " "
        }
    }

    Timer {
        id: pollTimer
        interval: 500
        running: pollSocket.status === WebSocket.Open
        repeat: true
        onTriggered: {
            sendPollRequest()
        }
    }

    Timer {
        id: karaokeClockTimer
        interval: Math.max(1, Math.round(1000 / config_karaokeFrameRate))
        repeat: true
        running: karaokeTimingActive
        onTriggered: {
            karaokePositionMs = karaokeBasePositionMs + (Date.now() - karaokeBaseTimestamp)
            maybePromoteKaraokeLine()
        }
    }

    WebSocket {
        id: pollSocket
        url: "ws://" + serverHost + ":" + serverPort + "/poll"
        active: true

        onStatusChanged: {
            if (pollSocket.status === WebSocket.Open) {
                console.log("Poll WebSocket connected")
                sendPollRequest()
            } else if (pollSocket.status === WebSocket.Closed) {
                console.log("Poll WebSocket closed, reconnecting...")
                hasActivePlayer = false
                currentLyric = ""
                reconnectTimer.start()
            } else if (pollSocket.status === WebSocket.Error) {
                console.log("Poll WebSocket error:", pollSocket.errorString)
                hasActivePlayer = false
                reconnectTimer.start()
            }
        }

        onTextMessageReceived: function(message) {
            try {
                var data = JSON.parse(message)
                handlePollResponse(data)
            } catch (e) {
                console.log("Error parsing poll response:", e)
            }
        }
    }

    WebSocket {
        id: controlSocket
        url: "ws://" + serverHost + ":" + serverPort + "/control"
        active: true

        onStatusChanged: {
            if (controlSocket.status === WebSocket.Open) {
                console.log("Control WebSocket connected")
            } else if (controlSocket.status === WebSocket.Error) {
                console.log("Control WebSocket error:", controlSocket.errorString)
            }
        }

        onTextMessageReceived: function(message) {
            try {
                var data = JSON.parse(message)
                if (data.type === "search_results") {
                    if (!data.search_type || data.search_type === selectedSearchType) {
                        spotifySearchResults = data.results || []
                        spotifySearching = false
                    }
                } else if (data.action === "play_uri") {
                    sendPollRequest()
                } else if (!data.success) {
                    console.log("Control command failed")
                }
            } catch (e) {
                console.log("Error parsing control response:", e)
            }
        }
    }

    property var spotifySearchResults: []
    property bool spotifySearching: false
    property string selectedSearchType: "track"

    Timer {
        id: searchDebounceTimer
        interval: 350
        running: false
        repeat: false
        onTriggered: performSearch(searchInput.text)
    }

    function performSearch(query) {
        var cleanQ = query ? query.trim() : ""
        if (cleanQ === "" && selectedSearchType !== "playlist") {
            spotifySearchResults = []
            spotifySearching = false
            return
        }
        if (controlSocket.status === WebSocket.Open) {
            spotifySearching = true
            var req = {
                "action": "search_spotify",
                "query": cleanQ,
                "limit": 20,
                "client_id": config_spotifyClientId,
                "client_secret": config_spotifyClientSecret,
                "search_type": selectedSearchType
            }
            controlSocket.sendTextMessage(JSON.stringify(req))
        }
    }

    function playSpotifyTrack(uri) {
        if (controlSocket.status === WebSocket.Open) {
            var req = {
                "action": "play_uri",
                "uri": uri,
                "player": "org.mpris.MediaPlayer2.spotify"
            }
            controlSocket.sendTextMessage(JSON.stringify(req))
            sendPollRequest()
            quickPollTimer.restart()
            spotifySearchPopup.visible = false
        }
    }

    function sendPollRequest() {
        if (pollSocket.status === WebSocket.Open) {
            var modeNames = ["global", "browser", "streaming"]
            var request = {
                "player": requestedPlayer || null,
                "mode": modeNames[config_playerMode] || "global",
                "convert_to_simplified": config_convertToSimplified
            }
            pollSocket.sendTextMessage(JSON.stringify(request))
        }
    }

    Timer {
        id: reconnectTimer
        interval: 3000
        running: false
        repeat: false
        onTriggered: {
            if (pollSocket.status !== WebSocket.Open) {
                pollSocket.active = false
                pollSocket.active = true
            }
            if (controlSocket.status !== WebSocket.Open) {
                controlSocket.active = false
                controlSocket.active = true
            }
        }
    }

    onCurrentLyricChanged: {
        triggerTransition()
    }

    onNextLyricChanged: {
        if (!fadeTransitionAnimation.running && !slideTransitionAnimation.running) {
            displayedNextLyric = nextLyric
        }
    }

    onLrc_not_existsChanged: {
        if (!currentLyric) {
            triggerTransition()
        }
    }

    onScrollingLyricsActiveChanged: {
        if (scrollingLyricsActive) {
            fadeTransitionAnimation.stop()
            slideTransitionAnimation.stop()
            nextLyricFadeIn.stop()
            scrollingLyricAnimation.stop()
            lyricColumn.opacity = 1.0
            currentTranslate.y = 0
            currentLyricText.opacity = 1.0
            if (currentLyric && displayedLyric !== currentLyric) {
                playScrollingLyricAnimation()
            }
        } else {
            fadeTransitionAnimation.stop()
            slideTransitionAnimation.stop()
            nextLyricFadeIn.stop()
            scrollingLyricAnimation.stop()
            lyricColumn.opacity = 1.0
            currentLyricText.opacity = 1.0
            currentTranslate.y = 0
            nextTranslate.y = 0
            nextScale.xScale = 0.85
            nextScale.yScale = 0.85
            nextLyricText.opacity = config_nextLyricOpacity
            displayedLyric = currentLyric
            displayedNextLyric = nextLyric
        }
    }

    function maybePromoteKaraokeLine() {
        if (!config_karaokeLyrics || playbackStatus !== "playing")
            return
        if (!nextLyric || nextLineStartMs <= 0 || nextLineStartMs <= currentLineStartMs)
            return
        if (karaokeTimeMs < nextLineStartMs)
            return

        var promotedLyric = nextLyric
        currentWords = nextWords
        hasWordLyrics = nextHasWordLyrics
        currentLineStartMs = nextLineStartMs
        currentLineEndMs = nextLineEndMs
        nextLyric = afterNextLyric
        nextWords = afterNextWords
        nextHasWordLyrics = afterNextHasWordLyrics
        nextLineStartMs = afterNextLineStartMs
        nextLineEndMs = afterNextLineEndMs
        afterNextLyric = ""
        afterNextWords = []
        afterNextHasWordLyrics = false
        afterNextLineStartMs = 0
        afterNextLineEndMs = 0
        currentLyric = promotedLyric
    }

    function triggerTransition() {
        if (scrollingLyricsActive) {
            playScrollingLyricAnimation()
            return
        }

        if (karaokeLyricsActive) {
            fadeTransitionAnimation.stop()
            slideTransitionAnimation.stop()
            nextLyricFadeIn.stop()
            scrollingLyricAnimation.stop()
            lyricColumn.opacity = 1.0
            displayedLyric = currentLyric
            displayedNextLyric = nextLyric
            currentTranslate.y = 0
            nextTranslate.y = 0
            nextScale.xScale = 0.85
            nextScale.yScale = 0.85
            currentLyricText.opacity = 1.0
            nextLyricText.opacity = config_nextLyricOpacity
            return
        }

        if (config_transitionDurationMs <= 0) {
            displayedLyric = currentLyric
            displayedNextLyric = nextLyric
            return
        }

        var canSlide = config_showNextLyric && displayedNextLyric !== "" && currentLyric === displayedNextLyric;
        if (canSlide) {
            slideTransitionAnimation.restart()
        } else {
            fadeTransitionAnimation.restart()
        }
    }

    function playScrollingLyricAnimation() {
        fadeTransitionAnimation.stop()
        slideTransitionAnimation.stop()
        nextLyricFadeIn.stop()
        scrollingLyricAnimation.stop()
        lyricColumn.opacity = 1.0
        displayedLyric = currentLyric
        displayedNextLyric = nextLyric
        currentTranslate.y = 6
        currentLyricText.opacity = 0.45
        scrollingLyricAnimation.start()
    }

    ParallelAnimation {
        id: scrollingLyricAnimation

        NumberAnimation {
            target: currentTranslate
            property: "y"
            from: 6
            to: 0
            duration: Math.max(180, Math.min(500, config_transitionDurationMs))
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: currentLyricText
            property: "opacity"
            from: 0.45
            to: 1.0
            duration: Math.max(180, Math.min(500, config_transitionDurationMs))
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: fadeTransitionAnimation
        
        PropertyAnimation {
            target: lyricColumn
            property: "opacity"
            to: 0
            duration: config_transitionDurationMs / 2
            easing.type: Easing.InOutQuad
        }
        
        ScriptAction {
            script: {
                displayedLyric = currentLyric
                displayedNextLyric = nextLyric
            }
        }
        
        PropertyAnimation {
            target: lyricColumn
            property: "opacity"
            to: 1
            duration: config_transitionDurationMs / 2
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation {
        id: slideTransitionAnimation
        
        ParallelAnimation {
            NumberAnimation {
                target: currentTranslate
                property: "y"
                from: 0
                to: -8
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: currentLyricText
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: nextTranslate
                property: "y"
                from: 0
                to: -(currentLyricText.contentHeight + 2)
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: nextLyricText
                property: "opacity"
                from: config_nextLyricOpacity
                to: 1.0
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: nextScale
                property: "xScale"
                from: 0.85
                to: 1.0
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: nextScale
                property: "yScale"
                from: 0.85
                to: 1.0
                duration: config_transitionDurationMs
                easing.type: Easing.OutCubic
            }
        }
        
        ScriptAction {
            script: {
                displayedLyric = currentLyric
                displayedNextLyric = nextLyric
                currentTranslate.y = 0
                nextTranslate.y = 0
                nextScale.xScale = 0.85
                nextScale.yScale = 0.85
                currentLyricText.opacity = 1.0
                nextLyricText.opacity = 0.0
                nextLyricFadeIn.restart()
            }
        }
    }

    NumberAnimation {
        id: nextLyricFadeIn
        target: nextLyricText
        property: "opacity"
        from: 0.0
        to: config_nextLyricOpacity
        duration: 200
        easing.type: Easing.OutQuad
    }

    function handlePollResponse(data) {
        if (!data || !data.player) {
            hasActivePlayer = false
            hasSyncedLyrics = false
            hasWordLyrics = false
            currentWords = []
            currentLineStartMs = 0
            currentLineEndMs = 0
            nextWords = []
            nextHasWordLyrics = false
            nextLineStartMs = 0
            nextLineEndMs = 0
            afterNextLyric = ""
            afterNextWords = []
            afterNextHasWordLyrics = false
            afterNextLineStartMs = 0
            afterNextLineEndMs = 0
            karaokeBasePositionMs = 0
            karaokeBaseTimestamp = Date.now()
            karaokePositionMs = 0
            currentLyric = ""
            nextLyric = ""
            currentLyricDurationMs = 0
            timeRemainingMs = 0
            currentTitle = ""
            currentArtist = ""
            currentAlbum = ""
            playbackStatus = "stopped"
            return
        }

        hasActivePlayer = true
        playbackStatus = data.playback_status || "stopped"
        positionMs = data.position_ms || 0

        if (data.player) {
            currentPlayerIdentity = data.player.identity || ""
            currentPlayerBusName = data.player.bus_name || ""
        }

        var incomingTrackTitle = data.track ? (data.track.title || "") : ""
        var trackChanged = !!data.track && incomingTrackTitle !== currentTitle

        if (data.track) {
            currentTitle = data.track.title || ""
            currentArtist = data.track.artist || ""
            currentAlbum = data.track.album || ""
            currentArtUrl = data.track.art_url || ""
        }

        if (data.lyrics) {
            var incomingWords = Array.isArray(data.lyrics.current_words) ? data.lyrics.current_words : []
            var incomingNextWords = Array.isArray(data.lyrics.next_words) ? data.lyrics.next_words : []
            var incomingAfterNextWords = Array.isArray(data.lyrics.after_next_words) ? data.lyrics.after_next_words : []
            var incomingPos = (data.lyrics.position_ms !== undefined)
                ? data.lyrics.position_ms
                : Math.floor((data.position_ms || 0) / 1000)
            var incomingPlaying = (data.playback_status || "stopped") === "playing"
            var canSmoothClock = incomingPlaying && karaokeBaseTimestamp > 0
            var clockResynced = !canSmoothClock
            if (canSmoothClock) {
                var localNow = karaokeBasePositionMs + (Date.now() - karaokeBaseTimestamp)
                var drift = incomingPos - localNow
                if (Math.abs(drift) > 1500) {
                    karaokeBasePositionMs = incomingPos
                    clockResynced = true
                } else {
                    karaokeBasePositionMs = localNow
                }
            } else {
                karaokeBasePositionMs = incomingPos
            }
            karaokeBaseTimestamp = Date.now()
            karaokePositionMs = karaokeBasePositionMs

            var incomingLyric = data.lyrics.current_lyric || ""
            var incomingStart = data.lyrics.current_line_start_ms || 0
            var localLineAhead = !trackChanged && !clockResynced && incomingPlaying && config_karaokeLyrics
                && incomingStart < currentLineStartMs

            hasSyncedLyrics = data.lyrics.has_synced_lyrics === true
            if (!localLineAhead) {
                if (currentLyric !== incomingLyric
                        || currentLineStartMs !== incomingStart
                        || currentWords.length !== incomingWords.length)
                    currentWords = incomingWords
                hasWordLyrics = data.lyrics.has_word_lyrics === true
                currentLineStartMs = incomingStart
                currentLineEndMs = data.lyrics.current_line_end_ms || 0
                currentLyric = incomingLyric
                nextLyric = data.lyrics.next_lyric || ""
                nextWords = incomingNextWords
                nextHasWordLyrics = data.lyrics.next_has_word_lyrics === true
                nextLineStartMs = data.lyrics.next_line_start_ms || 0
                nextLineEndMs = data.lyrics.next_line_end_ms || 0
                afterNextLyric = data.lyrics.after_next_lyric || ""
                afterNextWords = incomingAfterNextWords
                afterNextHasWordLyrics = data.lyrics.after_next_has_word_lyrics === true
                afterNextLineStartMs = data.lyrics.after_next_line_start_ms || 0
                afterNextLineEndMs = data.lyrics.after_next_line_end_ms || 0
                currentLyricDurationMs = data.lyrics.current_lyric_duration_ms || 0
                timeRemainingMs = data.lyrics.time_remaining_ms || 0
            }
        } else {
            hasSyncedLyrics = false
            hasWordLyrics = false
            currentWords = []
            currentLineStartMs = 0
            currentLineEndMs = 0
            nextLyric = ""
            nextWords = []
            nextHasWordLyrics = false
            nextLineStartMs = 0
            nextLineEndMs = 0
            afterNextLyric = ""
            afterNextWords = []
            afterNextHasWordLyrics = false
            afterNextLineStartMs = 0
            afterNextLineEndMs = 0
            karaokeBasePositionMs = Math.floor((data.position_ms || 0) / 1000)
            karaokeBaseTimestamp = Date.now()
            karaokePositionMs = karaokeBasePositionMs
            currentLyric = ""
            currentLyricDurationMs = 0
            timeRemainingMs = 0
        }

        if (data.available_players) {
            availablePlayers = data.available_players
        }
    }

    Timer {
        id: quickPollTimer
        interval: 100
        running: false
        repeat: false
        onTriggered: sendPollRequest()
    }

    function sendControl(action) {
        if (controlSocket.status !== WebSocket.Open) {
            console.log("Control socket not connected")
            return
        }
        if (action === "play_pause") {
            playbackStatus = (playbackStatus === "playing") ? "paused" : "playing"
        }
        var request = {
            "action": action,
            "player": requestedPlayer || currentPlayerBusName || null
        }
        controlSocket.sendTextMessage(JSON.stringify(request))
        sendPollRequest()
        quickPollTimer.restart()
    }
}
