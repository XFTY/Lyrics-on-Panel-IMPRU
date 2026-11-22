import QtQuick 2.0
import org.kde.plasma.configuration 2.0
import org.kde.plasma.plasmoid
import "../ui/i18n.js" as I18n

ConfigModel {
    readonly property int uiLanguageIndex: (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.languageIndex !== undefined) ? Plasmoid.configuration.languageIndex : 0
    readonly property string uiLanguage: I18n.languageForIndex(uiLanguageIndex)

    ConfigCategory {
        name: I18n.tr(uiLanguage, "外观与布局")
        icon: "preferences-desktop-display"
        source: "configAppearance.qml"
    }

    ConfigCategory {
        name: I18n.tr(uiLanguage, "动画与同步")
        icon: "media-playback-start"
        source: "configSync.qml"
    }

    ConfigCategory {
        name: I18n.tr(uiLanguage, "Spotify")
        icon: "multimedia-audio-player"
        source: "configSpotify.qml"
    }

    ConfigCategory {
        name: I18n.tr(uiLanguage, "关于")
        icon: "help-about"
        source: "configAbout.qml"
    }
}
