import QtQuick 2.15
import QtQuick.Layouts 1.1

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.private.mpris as Mpris
import "services/lyrics.js" as Lyrics
import "services/player.js" as Player


/**
Below are some documents that I found useful when writing this widget.

https://specifications.freedesktop.org/mpris-spec/latest/Player_Interface.html

https://app.readthedocs.org/projects/mpris2/downloads/pdf/latest/
*/

PlasmoidItem {
    id: root

    Mpris.Mpris2Model {
        id: mpris2Model
    }

    width: 0;
    height: lyricText.contentHeight;

    // Need to set it full representation. Otherwise it will only display the applet icon declared in the metadata.json file on the panel.
    preferredRepresentation: fullRepresentation 
    Layout.preferredWidth: config_preferedWidgetWidth;
    Layout.preferredHeight: lyricText.contentHeight;
    
    /**
        Set the background of this widget to be 'configurable' transparent or non transparent.
        https://develop.kde.org/docs/plasma/widget/properties/#x-plasma-api-x-plasma-mainscript
    */    
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    // Should ask uiYzzi if problem occurs.
    Plasmoid.status: mpris2Model.currentPlayer?.canControl || !config_hideItemWhenNoControlChecked ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus;

    Text {
        id: lyricText
        text: ""
        color: config_lyricTextColor
        font.pixelSize: config_lyricTextSize
        font.bold: config_lyricTextBold
        font.italic: config_lyricTextItalic
        anchors.right: parent.right
        anchors.rightMargin: 6 * (config_mediaControllItemSize + config_mediaControllSpacing)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: config_lyricTextVerticalOffset
    }

    Item {
        id: iconsContainer
        anchors.right: parent.right
        anchors.rightMargin: 1 
        anchors.verticalCenter: parent.verticalCenter
        width: 3 * config_mediaControllItemSize + 2 * config_mediaControllSpacing
        height: config_mediaControllItemSize
        anchors.verticalCenterOffset: config_mediaControllItemVerticalOffset

        Image {
            source: backwardIcon
            sourceSize.width: config_mediaControllItemSize 
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Player.previous();
                }
            }
        }

        Image {
            source: (playbackStatus == 2 && !Player.isWrongPlayer()) ? pauseIcon : playIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: config_mediaControllItemSize + config_mediaControllSpacing
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (playbackStatus == 2) {
                        Player.pause();
                    } else {
                        Player.play();
                    }
                }
            }
        }

        Image {
            source: forwardIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: 2 * (config_mediaControllItemSize + config_mediaControllSpacing)
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Player.next();
                }
            }
        }

    }

    // UI-Resources related configurations
    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"

    // Applet UI behavior configuration
    property bool config_yesPlayMusicChecked: Plasmoid.configuration.yesPlayMusicChecked;
    property bool config_lxMusicChecked: Plasmoid.configuration.lxMusicChecked;
    property bool config_splayerChecked: Plasmoid.configuration.splayerChecked;
    property bool config_spotifyChecked: Plasmoid.configuration.spotifyChecked;

    property int config_lyricTextSize: Plasmoid.configuration.lyricTextSize;
    property string config_lyricTextColor: Plasmoid.configuration.lyricTextColor;
    property bool config_lyricTextBold: Plasmoid.configuration.lyricTextBold;
    property bool config_lyricTextItalic: Plasmoid.configuration.lyricTextItalic;
    property int config_lyricTextVerticalOffset: Plasmoid.configuration.lyricTextVerticalOffset

    property int config_mediaControllSpacing: Plasmoid.configuration.mediaControllSpacing
    property int config_mediaControllItemSize: Plasmoid.configuration.mediaControllItemSize
    property int config_mediaControllItemVerticalOffset: Plasmoid.configuration.mediaControllItemVerticalOffset;

    property int config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked;
    property int config_preferedWidgetWidth: Plasmoid.configuration.preferedWidgetWidth;
    property bool config_hideItemWhenNoControlChecked: Plasmoid.configuration.hideItemWhenNoControlChecked;

    property int config_lxMusicPort: Plasmoid.configuration.lxMusicPort;

    /**
    ===============================================================================================================================================================================
    Above are the UI related code. 

    I am planning to disassemble them. 

    Below are backend logic related code.
    ===============================================================================================================================================================================
    */

    /**
        Some music player doesn't actively pushing the position to mpris2 datasource. 
        So have to send mpris2 datasource a signal to let'em pull the current position of the song from the player.
    */
    Timer {
        id: positionTimer
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            mpris2Model.currentPlayer.updatePosition();
        }
    }

    Timer {
        id: schedulerTimer
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            //Player.log();
            /**
                Use translator if you don't understand the comment... Too lazy to rewrite it in English.

                如果 
                    1. mpris 里面，当前播放音乐的title和artists都为空, 则尝试重置。
                    2. mpris 里面，当前播放器和之前的播放器不一样，就重置。
                    3. 设置 里面， 当前播放器和之前设置的播放器不一样(即更新了当前追踪的播放器),就重置。
                    4. 前后歌名，前后歌手不一样，重置。
                
                重置后，重新判断当前预期的播放器是哪个。并且开启对应的timer（线程）
            */ 
            if (
                !currentMediaTitle && !currentMediaArtists ||
                mpris2PreviousPlayerIdentity != mpris2CurrentPlayerIdentity ||
                prevExpectedPlayerIdentity != currExpectedPlayerIdentity ||
                currentMediaTitle != previousMediaTitle || 
                currentMediaArtists != previousMediaArtists
            ){
                Lyrics.reset();
                if (currExpectedPlayerIdentity === "compatible" || currExpectedPlayerIdentity === "Spotify") {
                    compatibleModeTimer.start()
                } else if (currExpectedPlayerIdentity === "YesPlayMusic") {
                    if (mpris2CurrentPlayerIdentity === "YesPlayMusic") {
                        yesPlayMusicTimer.start();
                    }
                } else if (currExpectedPlayerIdentity === "lx-music-desktop") {
                    if (mpris2CurrentPlayerIdentity === "lx-music-desktop") {
                        lxMusicTimer.start();
                    }
                } else if (currExpectedPlayerIdentity === "SPlayer") {
                    if (mpris2CurrentPlayerIdentity === "SPlayer") {
                        splayerTimer.start();
                    }
                }
            }
        }
    }

    Timer {
        id: yesPlayMusicTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            Lyrics.ypmHandler();
        }
    }

    /**
        must set this one to repeat.
        这玩意的API有问题。加载速度太随机了，完全依赖音源。并且有时候开始放歌了，结果lyric API还没有响应出来。
    */
    Timer {
        id: lxMusicTimer
        interval: 200
        running: false
        repeat: true 
        onTriggered: {
            Lyrics.lxHandler();
        }
    }

    Timer {
        id: splayerTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            Lyrics.splayerHandler();
        }
    }
    
    /**
        Same as above, only one Lyric Fetching Timer will be running.
        If the:
            current media artists does not match the previous media artists
            current media title does not match the previous media title
            current media title and artists are empty
        Then we will stop the timer and start a new one.

        Otherwise, we will keep the timer running and fetch the lyric from the lrclib API.
        
    */
    Timer {
        id: compatibleModeTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            // console.log("reached here")
            if ((currentMediaArtists === "" && currentMediaTitle === "") || (currentMediaTitle != previousMediaTitle) || currentMediaArtists != previousMediaArtists) {
                Lyrics.reset();
                // console.log("keeping Lyrics.reset()")
            } else {
                if (mpris2CurrentPlayerIdentity === "YesPlayMusic") {
                    // console.log("YPM Timer Triggered");
                    Lyrics.ypmHandler();
                } else if (mpris2CurrentPlayerIdentity === "lx-music-desktop") {
                    // console.log("lx music triggered")
                    Lyrics.lxHandler();
                } else if (mpris2CurrentPlayerIdentity === "SPlayer") {
                    // console.log("splayer triggered")
                    Lyrics.splayerHandler();
                } else {
                    if (!isCompatibleLRCFound || needFallback) {
                        //console.log("spotify compatible mode triggered")
                        Lyrics.fetchLyricsCompatibleMode();
                    }
                }
            }
        }
    }

    Timer {
        id: lyricDisplayTimer
        interval: 1
        running: false
        repeat: true
        onTriggered: { 
            // If the current playing media source in mpris2 datasource doesn't match the expected media source, then no lyric will be displayed
            if ((currExpectedPlayerIdentity !== 'compatible') && (mpris2CurrentPlayerIdentity !== currExpectedPlayerIdentity)) {
                lyricText.text = " ";
            } else {
                if (currentMediaTitle === "Advertisement") {
                    lyricText.text = currentMediaTitle;
                } else {
                    for (let i = 0; i < lyricsWTimes.count; i++) {
                        if (lyricsWTimes.get(i).time >= mprisCurrentPlayingSongTimeMS) {
                            currentLyricIndex = i > 0 ? i - 1 : 0;
                            var currentLWT = lyricsWTimes.get(currentLyricIndex);
                            var currentLyric = currentLWT.lyric;
                            if (!currentLWT || !currentLyric || currentLyric === "" && prevNonEmptyLyric != "") {
                                lyricText.text = prevNonEmptyLyric;
                            } else {
                                lyricText.text = currentLyric;
                                prevNonEmptyLyric = currentLyric;
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    // Global constant
    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lxmusic_base_url: {
        return "http://localhost:" + config_lxMusicPort;
    }

    readonly property string splayer_base_url: "http://localhost:25884"

    readonly property string lrclib_base_url: "https://lrclib.net"

    // Successfully fetched the lyrics from the yesplaymusic API?
    property bool isYPMLyricFound: false;

    property bool isLXLyricFound: false;

    property bool isSPlayerLyricFound: false;

    // Current Media Title (Song's name), default is empty string
    property string currentMediaTitle: mpris2Model.currentPlayer?.track ?? ""

    // Current Media Artists (Song's artist), default is empty string
    property string currentMediaArtists: mpris2Model.currentPlayer?.artist ?? ""

    // Current Media Album (Song's album), default is empty string
    property string currentMediaAlbum: mpris2Model.currentPlayer?.album ?? ""

    // Current Media Playback Status (Song's playback status), default is 0
    property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? -1

    // Retrieve the identity of current music/media player
    // YesPlayMusic Spotify lx-music-desktop xxx
    property string mpris2CurrentPlayerIdentity: mpris2Model.currentPlayer?.identity ?? ""
        
    // Retrieve the current media position (in microseconds)
    property int position: mpris2Model.currentPlayer?.position ?? 0


    // Retrieve the current media length (in microseconds)
    property double length: mpris2Model.currentPlayer?.length ?? 0

    /**
        A list of dictionaries. Each dictionary contains a timestamp and the corresponding lyric. Below is an example

        [
            {timestamp: 1, lyric: "Hello"}, 
            {timestamp: 2, lyric: "World"}, 
            {timestamp: 3, lyric: "!"}
        ]
    */
    ListModel {
        id: lyricsWTimes
    }

    // Other Media Player's mpris2 data
    property int mprisCurrentPlayingSongTimeMS: {
        if (position == 0) {
            return -1;
        } else {
            return position;
        }
    }

    // YesPlayMusic only, don't get misleaded. We can use http://localhost:27232/api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
    property string currentMediaYPMId: ""

    // Just the index of the LyricWTimes lists. Retrieve the element from the list using the index. The retrieved element contains a timestamp and the corresponding lyric.
    property int currentLyricIndex: 0

    property string previousMediaTitle: ""

    property string previousMediaArtists: ""

    property string prevNonEmptyLyric: ""

    // The id of the lyric that has been fetched from the lrclib API. Only used in compatible mode when querying the lrclib API.
    property string previousLrcId: ""

    // Indicating whether we need to use the needFallback fetching strategy
    property bool needFallback: false;

    property bool isCompatibleLRCFound: false;

    property string mpris2PreviousPlayerIdentity: ""

    property string prevExpectedPlayerIdentity: "";

    property string currExpectedPlayerIdentity: {
        if (config_yesPlayMusicChecked) {
            return "YesPlayMusic";
        } else if (config_spotifyChecked) {
            return "Spotify";
        } else if (config_lxMusicChecked) {
            return "lx-music-desktop";
        } else if (config_splayerChecked) {
            return "SPlayer";
        } else {
            return "compatible";
        }
    }

    // Construct the lrclib's request url
    property string lrcQueryUrl: {
        if (needFallback) { // 如果失败了就用歌名做一次模糊查询。lrclib只支持模糊查询一个field.所以只能专辑|歌手名|歌名选一个， 很明显歌名的结果最准确。
            return lrclib_base_url + "/api/search" + "?track_name=" + encodeURIComponent(currentMediaTitle) + 
                  "&artist_name=" + encodeURIComponent(currentMediaArtists) + "&album_name=" + encodeURIComponent(currentMediaAlbum) + "&q=" 
                  + encodeURIComponent(currentMediaTitle);
        } else { // accruate matching
            return lrclib_base_url + "/api/search" + "?track_name=" + encodeURIComponent(currentMediaTitle) + 
                  "&artist_name=" + encodeURIComponent(currentMediaArtists) + "&album_name=" + encodeURIComponent(currentMediaAlbum);
        }
    }
    
    // exception handling: no lyric => only display title - artists
    property string lrc_not_exists: {
        if (currentMediaTitle && currentMediaArtists) {
            return currentMediaTitle + " - " + currentMediaArtists;
        } else if (currentMediaTitle && !currentMediaArtists) {
            return currentMediaTitle;
        } else {
            return "This song doesn't contain any lyric/title/artist.";
        }
    }

}
