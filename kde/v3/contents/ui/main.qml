import QtQuick 2.15
import QtQuick.Layouts 1.1
import QtWebSockets

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import "i18n.js" as I18n
import "services/network.js" as Network
import "services/poll.js" as Poll
import "services/transitions.js" as Transitions

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

    Plasmoid.status: config_alwaysVisible
        ? PlasmaCore.Types.ActiveStatus
        : ((config_playerMode !== 0 && !hasActivePlayer)
            ? PlasmaCore.Types.HiddenStatus
            : (hasActivePlayer || !config_hideItemWhenNoControlChecked
                ? PlasmaCore.Types.ActiveStatus
                : PlasmaCore.Types.HiddenStatus))

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

            MouseArea {
                id: lyricModeMouseArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                onClicked: {
                    var globalPos = lyricModeMouseArea.mapToGlobal(mouse.x, mouse.y)
                    matchModePopup.x = globalPos.x
                    matchModePopup.y = globalPos.y
                    matchModePopup.visible = true
                }
            }
        }

        MediaControls {
            id: iconsContainer
            whiteIcons: config_whiteMediaControlIconsChecked
            controlSize: config_mediaControllItemSize
            albumCoverSize: config_albumCoverItemSize
            spacing: config_mediaControllSpacing
            playbackStatus: root.playbackStatus
            showAlbumCover: config_showAlbumCover
            artUrl: root.currentArtUrl
            spotifySearchEnabled: config_enableSpotifySearch
            onPreviousClicked: Network.sendControl("previous")
            onPlayPauseClicked: Network.sendControl("play_pause")
            onNextClicked: Network.sendControl("next")
            onAlbumCoverClicked: function(gx, gy, w) {
                spotifySearchPopup.x = gx - (320 - w) / 2
                spotifySearchPopup.y = gy + 6
                spotifySearchPopup.visible = !spotifySearchPopup.visible
            }
        }
    }

    SpotifySearchPopup {
        id: spotifySearchPopup
        language: root.config_language
        clientId: root.config_spotifyClientId
        clientSecret: root.config_spotifyClientSecret
        onSearchRequested: function(query, type) {
            Network.searchSpotify(query, type)
        }
        onPlayRequested: function(uri) {
            Network.playSpotifyTrack(uri)
        }
    }

    MatchModePopup {
        id: matchModePopup
        language: root.config_language
        currentMode: root.config_playerMode
        onModeSelected: function(mode) {
            root.setPlayerMode(mode)
        }
    }

    function setPlayerMode(mode) {
        if (Plasmoid.configuration.playerMode === mode)
            return
        Plasmoid.configuration.playerMode = mode
        Plasmoid.configuration.writeConfig()
        Network.sendPollRequest()
    }

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

    property bool config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked
    property int config_preferedWidgetWidth: Plasmoid.configuration.preferedWidgetWidth > 0 ? Plasmoid.configuration.preferedWidgetWidth : 850
    property bool config_dynamicWidth: Plasmoid.configuration.dynamicWidth !== undefined ? Plasmoid.configuration.dynamicWidth : true
    property bool config_enableTextScrolling: Plasmoid.configuration.enableTextScrolling !== undefined ? Plasmoid.configuration.enableTextScrolling : false
    property bool config_hideItemWhenNoControlChecked: Plasmoid.configuration.hideItemWhenNoControlChecked !== undefined ? Plasmoid.configuration.hideItemWhenNoControlChecked : true
    property bool config_alwaysVisible: Plasmoid.configuration.alwaysVisible !== undefined ? Plasmoid.configuration.alwaysVisible : false
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
    property string currentArtUrl: ""
    property string currentPlayerBusName: ""
    property bool hasActivePlayer: false
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
            Network.sendPollRequest()
        }
    }

    Timer {
        id: karaokeClockTimer
        interval: Math.max(1, Math.round(1000 / config_karaokeFrameRate))
        repeat: true
        running: karaokeTimingActive
        onTriggered: {
            karaokePositionMs = karaokeBasePositionMs + (Date.now() - karaokeBaseTimestamp)
            Transitions.maybePromoteKaraokeLine()
        }
    }

    WebSocket {
        id: pollSocket
        url: "ws://" + serverHost + ":" + serverPort + "/poll"
        active: true

        onStatusChanged: {
            if (pollSocket.status === WebSocket.Open) {
                console.log("Poll WebSocket connected")
                Network.sendPollRequest()
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
                Poll.handlePollResponse(data)
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
                    spotifySearchPopup.setResults(data.search_type, data.results)
                } else if (data.action === "play_uri") {
                    Network.sendPollRequest()
                } else if (!data.success) {
                    console.log("Control command failed")
                }
            } catch (e) {
                console.log("Error parsing control response:", e)
            }
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
        Transitions.triggerTransition()
    }

    onNextLyricChanged: {
        Transitions.handleNextLyricChanged()
    }

    onLrc_not_existsChanged: {
        Transitions.handleLrcNotExistsChanged()
    }

    onScrollingLyricsActiveChanged: {
        Transitions.handleScrollingLyricsActiveChanged()
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

    Timer {
        id: quickPollTimer
        interval: 100
        running: false
        repeat: false
        onTriggered: Network.sendPollRequest()
    }


}
