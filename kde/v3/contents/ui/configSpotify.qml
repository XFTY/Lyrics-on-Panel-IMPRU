import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15 as QQLayouts
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kquickcontrols 2.0 as KQC
import QtWebSockets 1.1
import "i18n.js" as I18n
import org.kde.plasma.plasmoid

Kirigami.FormLayout {
    id: spotifyConfigPage

    readonly property string language: I18n.languageForIndex((typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.languageIndex !== undefined) ? Plasmoid.configuration.languageIndex : 0)

    property alias cfg_enableSpotifySearch: enableSpotifySearchCheckBox.checked
    property alias cfg_spotifyClientId: spotifyClientIdTextField.text
    property alias cfg_spotifyClientSecret: spotifyClientSecretTextField.text

    property bool isAccountConnected: false
    property string connectedUserName: ""

    function checkAuthStatus() {
        if (cfgSocket.status === WebSocket.Open) {
            var cid = spotifyClientIdTextField.text ? spotifyClientIdTextField.text.trim() : ""
            if (cid === "") {
                isAccountConnected = false
                connectedUserName = ""
                return
            }
            cfgSocket.sendTextMessage(JSON.stringify({
                "action": "get_spotify_auth_status",
                "client_id": cid
            }))
        }
    }

    WebSocket {
        id: cfgSocket
        url: "ws://127.0.0.1:23560/control"
        active: true
        onStatusChanged: {
            if (cfgSocket.status === WebSocket.Open) {
                checkAuthStatus()
            }
        }
        onTextMessageReceived: function(message) {
            try {
                var data = JSON.parse(message)
                if (data.type === "spotify_auth_status") {
                    var cid = spotifyClientIdTextField.text ? spotifyClientIdTextField.text.trim() : ""
                    var csec = spotifyClientSecretTextField.text ? spotifyClientSecretTextField.text.trim() : ""
                    if (cid !== "" && csec !== "" && data.status && data.status.connected === true) {
                        isAccountConnected = true
                        connectedUserName = data.status.user_name || ""
                    } else {
                        isAccountConnected = false
                        connectedUserName = ""
                    }
                } else if (data.type === "spotify_login_response") {
                    pollTimer.restart()
                }
            } catch (e) {
                console.log("Error parsing cfgSocket msg:", e)
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 1500
        repeat: true
        running: false
        onTriggered: {
            checkAuthStatus()
            if (isAccountConnected) {
                pollTimer.stop()
            }
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "Spotify 集成")
    }

    QQC2.CheckBox {
        id: enableSpotifySearchCheckBox
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "快速搜索：")
        text: I18n.tr(spotifyConfigPage.language, "点击专辑封面时启用歌曲搜索")
        checkable: true
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "开发者密钥（Spotify API）")
    }

    Kirigami.InlineMessage {
        id: infoBanner
        QQLayouts.Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: true
        text: I18n.tr(spotifyConfigPage.language, "<b>Spotify 密钥（可选）：</b>可一键精确播放歌曲和播放列表。<br>" +
                   "📖 请在 <b>GitHub README</b> 中查看分步配置说明。")
    }

    QQC2.TextField {
        id: spotifyClientIdTextField
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "Spotify Client ID：")
        placeholderText: I18n.tr(spotifyConfigPage.language, "例如：4c082842f450437ca5e463a5efb867c2")
        enabled: enableSpotifySearchCheckBox.checked
        QQLayouts.Layout.fillWidth: true
        onTextChanged: checkAuthStatus()
    }

    QQC2.TextField {
        id: spotifyClientSecretTextField
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "Spotify Client Secret：")
        placeholderText: I18n.tr(spotifyConfigPage.language, "例如：034e34c9f1874b7db8a9e04860b0e513")
        echoMode: TextInput.Password
        enabled: enableSpotifySearchCheckBox.checked
        QQLayouts.Layout.fillWidth: true
        onTextChanged: checkAuthStatus()
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "我的 Spotify 账户（私有播放列表与音乐库）")
    }

    Kirigami.InlineMessage {
        QQLayouts.Layout.fillWidth: true
        type: Kirigami.MessageType.Positive
        visible: isAccountConnected
        text: I18n.tr(spotifyConfigPage.language, "<b>✅ Spotify 账户已连接：</b>") + connectedUserName + "<br>" +
              I18n.tr(spotifyConfigPage.language, "你的私有、收藏和协作播放列表已与面板同步。")
    }

    Kirigami.InlineMessage {
        QQLayouts.Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: !isAccountConnected
        text: I18n.tr(spotifyConfigPage.language, "<b>想在面板中直接查看所有私有播放列表吗？</b><br>" +
                   "点击下方按钮登录一次，私有播放列表将自动显示在<i>播放列表</i>标签页中，无需搜索。")
    }

    QQLayouts.RowLayout {
        Kirigami.FormData.label: I18n.tr(spotifyConfigPage.language, "账户状态：")
        spacing: 10

        QQC2.Button {
            text: isAccountConnected ? I18n.tr(spotifyConfigPage.language, "断开账户") : I18n.tr(spotifyConfigPage.language, "🔗 连接我的 Spotify 账户")
            enabled: enableSpotifySearchCheckBox.checked && spotifyClientIdTextField.text.trim() !== "" && spotifyClientSecretTextField.text.trim() !== ""
            onClicked: {
                if (isAccountConnected) {
                    cfgSocket.sendTextMessage(JSON.stringify({"action": "spotify_logout"}))
                } else {
                    pollTimer.start()
                    cfgSocket.sendTextMessage(JSON.stringify({
                        "action": "spotify_login",
                        "client_id": spotifyClientIdTextField.text.trim(),
                        "client_secret": spotifyClientSecretTextField.text.trim()
                    }))
                }
            }
        }

        QQC2.Label {
            text: isAccountConnected ? I18n.tr(spotifyConfigPage.language, "🟢 已连接（%1）", connectedUserName) : I18n.tr(spotifyConfigPage.language, "⚪ 未连接")
            font.bold: true
            color: isAccountConnected ? "#1db954" : Kirigami.Theme.disabledTextColor
        }
    }

    QQC2.Label {
        text: I18n.tr(spotifyConfigPage.language, "🔒 你的密钥和令牌会安全地保存在本机 KDE 配置中。")
        font.pixelSize: 11
        color: Kirigami.Theme.disabledTextColor
        QQLayouts.Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
