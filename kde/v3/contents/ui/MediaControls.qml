import QtQuick 2.15
import QtQuick.Layouts 1.1

RowLayout {
    id: controls

    property bool whiteIcons: false
    property int controlSize: 15
    property int albumCoverSize: 18
    property string playbackStatus: "stopped"
    property bool showAlbumCover: false
    property string artUrl: ""
    property bool spotifySearchEnabled: true
    property string displayedArtUrl: artUrl

    signal previousClicked()
    signal playPauseClicked()
    signal nextClicked()
    signal albumCoverClicked(real globalX, real globalY, real width)

    readonly property string backwardIcon: whiteIcons ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    readonly property string pauseIcon: whiteIcons ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    readonly property string forwardIcon: whiteIcons ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    readonly property string playIcon: whiteIcons ? "../assets/media-play-white.svg" : "../assets/media-play.svg"

    Layout.preferredWidth: 3 * controlSize + (showAlbumCover && artUrl !== "" ? (albumCoverSize + spacing) : 0) + 2 * spacing
    Layout.preferredHeight: Math.max(controlSize, albumCoverSize)
    Layout.alignment: Qt.AlignVCenter
    Layout.rightMargin: 1
    spacing: 10

    onArtUrlChanged: {
        if (showAlbumCover && artUrl !== "" && displayedArtUrl !== "") {
            artChangeAnimation.restart()
        } else {
            displayedArtUrl = artUrl
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
                displayedArtUrl = artUrl
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

    Image {
        source: controls.backwardIcon
        sourceSize.width: controls.controlSize
        sourceSize.height: controls.controlSize

        MouseArea {
            anchors.fill: parent
            onClicked: controls.previousClicked()
        }
    }

    Image {
        source: (controls.playbackStatus === "playing") ? controls.pauseIcon : controls.playIcon
        sourceSize.width: controls.controlSize
        sourceSize.height: controls.controlSize

        MouseArea {
            anchors.fill: parent
            onClicked: controls.playPauseClicked()
        }
    }

    Image {
        source: controls.forwardIcon
        sourceSize.width: controls.controlSize
        sourceSize.height: controls.controlSize

        MouseArea {
            anchors.fill: parent
            onClicked: controls.nextClicked()
        }
    }

    Item {
        id: mediaPlayerIconContainer
        width: controls.albumCoverSize
        height: controls.albumCoverSize
        visible: controls.showAlbumCover && controls.artUrl !== ""

        Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Math.round(controls.albumCoverSize * 0.2))
            color: "transparent"
            clip: true

            Image {
                id: mediaPlayerIcon
                anchors.fill: parent
                source: (controls.showAlbumCover && controls.displayedArtUrl !== "") ? controls.displayedArtUrl : ""
                sourceSize.width: controls.albumCoverSize * 2
                sourceSize.height: controls.albumCoverSize * 2
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                asynchronous: true
                transformOrigin: Item.Center
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: controls.spotifySearchEnabled
            cursorShape: controls.spotifySearchEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (controls.spotifySearchEnabled) {
                    var pos = mediaPlayerIconContainer.mapToGlobal(0, mediaPlayerIconContainer.height)
                    controls.albumCoverClicked(pos.x, pos.y, mediaPlayerIconContainer.width)
                }
            }
        }
    }
}
