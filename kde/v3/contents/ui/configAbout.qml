import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.15 as Kirigami
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQuick.Layouts 1.15 as QQLayouts
import "i18n.js" as I18n
import org.kde.plasma.plasmoid

Kirigami.ScrollablePage {
    id: aboutPage
    signal configurationChanged

    readonly property string language: I18n.languageForIndex((typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.languageIndex !== undefined) ? Plasmoid.configuration.languageIndex : 0)

    verticalScrollBarPolicy: QQC2.ScrollBar.AsNeeded
    horizontalScrollBarPolicy: QQC2.ScrollBar.AlwaysOff

    Kirigami.FormLayout {
        width: Math.min(parent ? parent.width : aboutPage.width, 760)
        x: parent ? Math.max(0, (parent.width - width) / 2) : 0

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(aboutPage.language, "关于 Lyrics-on-Panel")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(aboutPage.language, "适用于 Plasma 6 的面板歌词控件，可实时显示同步歌词，并支持逐字高亮、多播放器匹配、专辑封面与 Spotify 快速搜索。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(aboutPage.language, "主要功能")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(aboutPage.language, "• 同步歌词与下一句预览\n• 逐字歌词从左到右扫过高亮\n• 全局、浏览器与串流音频软件匹配模式\n• 暂停后保持显示，播放器关闭后隐藏\n• 多来源歌词：LRCLIB 与酷狗\n• 繁体歌词转换、专辑封面与 Spotify 搜索")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(aboutPage.language, "作者")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(aboutPage.language, "原作者：KangweiZhu（Anicaa Zhu）\nv3 分支维护：bogeta329\n共同改进：XFTY")
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(aboutPage.language, "项目信息")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(aboutPage.language, "版本：3.3.0\n许可证：GPLv3")
            wrapMode: Text.WordWrap
        }
    }
}
