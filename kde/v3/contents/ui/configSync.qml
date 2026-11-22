import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.15 as Kirigami
import QtQuick.Layouts 1.15 as QQLayouts
import "i18n.js" as I18n
import org.kde.plasma.plasmoid

Kirigami.ScrollablePage {
    id: syncPage
    signal configurationChanged

    readonly property string language: I18n.languageForIndex((typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.languageIndex !== undefined) ? Plasmoid.configuration.languageIndex : 0)

    property alias cfg_showNextLyric: showNextLyricCheckBox.checked
    property alias cfg_nextLyricOpacity: nextLyricOpacitySlider.value
    property alias cfg_transitionDurationMs: transitionDurationMsSpinBox.value
    property alias cfg_syncOffsetMs: syncOffsetMsSpinBox.value

    verticalScrollBarPolicy: QQC2.ScrollBar.AsNeeded
    horizontalScrollBarPolicy: QQC2.ScrollBar.AlwaysOff

    Kirigami.FormLayout {
        width: Math.min(parent ? parent.width : syncPage.width, 760)
        x: parent ? Math.max(0, (parent.width - width) / 2) : 0

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(syncPage.language, "下一句预览")
        }

        QQC2.CheckBox {
            id: showNextLyricCheckBox
            Kirigami.FormData.label: I18n.tr(syncPage.language, "显示下一句预览：")
            text: I18n.tr(syncPage.language, "在歌词下方显示下一句，形成双行布局")
            QQC2.ToolTip.text: I18n.tr(syncPage.language, "逐字歌词模式下同样显示下一句预览")
            checkable: true
        }

        QQLayouts.RowLayout {
            Kirigami.FormData.label: I18n.tr(syncPage.language, "下一句不透明度：")
            enabled: showNextLyricCheckBox.checked
            QQLayouts.Layout.maximumWidth: 300

            QQC2.Slider {
                id: nextLyricOpacitySlider
                from: 0.05
                to: 1.0
                stepSize: 0.05
                QQC2.ToolTip.text: I18n.tr(syncPage.language, "下一句预览的透明度")
                QQLayouts.Layout.fillWidth: true
            }
            QQC2.Label {
                text: Math.round(nextLyricOpacitySlider.value * 100) + "%"
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(syncPage.language, "动画与时间")
        }

        QQC2.SpinBox {
            id: transitionDurationMsSpinBox
            Kirigami.FormData.label: I18n.tr(syncPage.language, "过渡时长（毫秒）：")
            from: 0
            to: 1000
            stepSize: 50
            QQC2.ToolTip.text: I18n.tr(syncPage.language, "渐显渐隐和滚动歌词的切换动画时长")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(syncPage.language, "逐字歌词模式会立即切换歌词行以避免延迟；此设置主要影响渐显渐隐和滚动歌词。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(syncPage.language, "手动同步调整")
        }

        QQC2.SpinBox {
            id: syncOffsetMsSpinBox
            Kirigami.FormData.label: I18n.tr(syncPage.language, "同步偏移（毫秒）：")
            from: -5000
            to: 5000
            stepSize: 50
            editable: true
            QQC2.ToolTip.text: I18n.tr(syncPage.language, "正值延后歌词，负值提前歌词")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.Label {
            Kirigami.FormData.label: I18n.tr(syncPage.language, "偏移说明：")
            text: I18n.tr(syncPage.language, "正值（+毫秒）使歌词延后，负值（-毫秒）使歌词提前。逐字歌词的逐字高亮也会同步偏移。")
            font: Kirigami.Theme.smallFont
            opacity: 0.78
            wrapMode: Text.WordWrap
            QQLayouts.Layout.maximumWidth: 680
        }
    }
}
