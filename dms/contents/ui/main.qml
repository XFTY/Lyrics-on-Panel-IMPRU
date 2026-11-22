import QtQuick
import QtWebSockets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "lyricsOnPanel"

    // Icon paths
    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"

    property bool config_showAlbumCover: pluginData.showAlbumCover ?? false

    // Config from pluginData (defaults match configGeneral.qml)
    property bool config_yesPlayMusicChecked: pluginData.playerMode === "yesplaymusic"
    property bool config_lxMusicChecked: pluginData.playerMode === "lxmusic"
    property bool config_spotifyChecked: pluginData.playerMode === "spotify"

    property int config_lyricTextSize: pluginData.lyricTextSize ?? 12
    property string config_lyricTextColor: pluginData.lyricTextColor ?? "#ffffff"
    property bool config_lyricTextBold: pluginData.lyricTextBold ?? false
    property bool config_lyricTextItalic: pluginData.lyricTextItalic ?? false

    property int config_mediaControllSpacing: pluginData.mediaControllSpacing ?? 8
    property int config_mediaControllItemSize: pluginData.mediaControllItemSize ?? 12
    property bool config_showMediaControls: pluginData.showMediaControls ?? true

    property bool config_whiteMediaControlIconsChecked: pluginData.whiteMediaControlIconsChecked ?? true

    // Server config
    readonly property string serverHost: "127.0.0.1"
    readonly property int serverPort: 23560

    // State
    property string playbackStatus: "stopped"
    property string currentLyric: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentArtUrl: ""
    property string currentPlayerBusName: ""
    property var availablePlayers: []
    property string selectedPlayer: ""

    property string requestedPlayer: {
        if (selectedPlayer) {
            return selectedPlayer
        } else if (config_yesPlayMusicChecked) {
            return "org.mpris.MediaPlayer2.yesplaymusic"
        } else if (config_spotifyChecked) {
            return "org.mpris.MediaPlayer2.spotify"
        } else if (config_lxMusicChecked) {
            return "org.mpris.MediaPlayer2.lx-music-desktop"
        } else {
            return ""
        }
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

    property Component mediaControls: Component {
        Row {
            visible: root.config_showMediaControls
            spacing: root.config_mediaControllSpacing

            Image {
                source: root.backwardIcon
                sourceSize.width: root.config_mediaControllItemSize
                sourceSize.height: root.config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.sendControl("previous")
                }
            }

            Image {
                source: (root.playbackStatus === "playing") ? root.pauseIcon : root.playIcon
                sourceSize.width: root.config_mediaControllItemSize
                sourceSize.height: root.config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.sendControl("play_pause")
                }
            }

            Image {
                source: root.forwardIcon
                sourceSize.width: root.config_mediaControllItemSize
                sourceSize.height: root.config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.sendControl("next")
                }
            }

            Image {
                id: mediaPlayerIcon
                source: (root.config_showAlbumCover && root.currentArtUrl !== "") ? root.currentArtUrl : ""
                sourceSize.width: root.config_mediaControllItemSize
                sourceSize.height: root.config_mediaControllItemSize
                fillMode: Image.PreserveAspectCrop
                visible: root.config_showAlbumCover && root.currentArtUrl !== ""
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: root.config_mediaControllSpacing

            StyledText {
                text: root.currentLyric || root.lrc_not_exists
                font.pixelSize: root.config_lyricTextSize
                font.bold: root.config_lyricTextBold
                font.italic: root.config_lyricTextItalic
                color: root.config_lyricTextColor
                anchors.verticalCenter: parent.verticalCenter
              }

            Loader {
                active: root.config_showMediaControls
                visible: active
                sourceComponent: root.mediaControls
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: root.config_mediaControllSpacing
            
            StyledText {
                text: root.currentLyric || root.lrc_not_exists
                font.pixelSize: root.config_lyricTextSize - 2
                font.bold: root.config_lyricTextBold
                color: root.config_lyricTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Loader {
                active: root.config_showMediaControls
                visible: active
                sourceComponent: root.mediaControls
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Media Players"
            detailsText: "Select a player"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: playerList.contentHeight

                ListView {
                    id: playerList
                    anchors.fill: parent
                    model: root.availablePlayers
                    spacing: Theme.spacingXS

                    delegate: StyledRect {
                        width: playerList.width
                        height: 40
                        radius: Theme.cornerRadius
                        color: playerMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            StyledText {
                                text: modelData === root.currentPlayerBusName ? "\u25CF" : "\u25CB"
                                color: modelData === root.currentPlayerBusName ? Theme.primary : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: modelData.replace("org.mpris.MediaPlayer2.", "")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: playerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedPlayer = modelData
                                popoutColumn.closePopout()
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 300
    popoutHeight: Math.max(availablePlayers.length * 50 + 100, 150)

    Timer {
        id: pollTimer
        interval: 500
        running: pollSocket.status === WebSocket.Open
        repeat: true
        onTriggered: {
            sendPollRequest()
        }
    }

    // WebSocket connections
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
                currentLyric = ""
                reconnectTimer.start()
            } else if (pollSocket.status === WebSocket.Error) {
                console.log("Poll WebSocket error:", pollSocket.errorString)
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
                if (!data.success) {
                    console.log("Control command failed")
                }
            } catch (e) {
                console.log("Error parsing control response:", e)
            }
        }
    }

    function sendPollRequest() {
        if (pollSocket.status === WebSocket.Open) {
            var request = { "player": requestedPlayer || null }
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

    function handlePollResponse(data) {
        if (!data || !data.player) {
            currentLyric = ""
            currentTitle = ""
            currentArtist = ""
            currentArtUrl = ""
            playbackStatus = "stopped"
            return
        }

        playbackStatus = data.playback_status || "stopped"

        if (data.player) {
            currentPlayerBusName = data.player.bus_name || ""
        }

        if (data.track) {
            currentTitle = data.track.title || ""
            currentArtist = data.track.artist || ""
            currentArtUrl = data.track.art_url || ""
        }

        if (data.lyrics && data.lyrics.current_lyric) {
            currentLyric = data.lyrics.current_lyric
        } else {
            currentLyric = ""
        }

        if (data.available_players) {
            availablePlayers = data.available_players
        }
    }

    function sendControl(action) {
        if (controlSocket.status !== WebSocket.Open) {
            console.log("Control socket not connected")
            return
        }
        var request = {
            "action": action,
            "player": requestedPlayer || currentPlayerBusName || null
        }
        controlSocket.sendTextMessage(JSON.stringify(request))
    }
}
