import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.15 as Kirigami
import org.kde.kquickcontrols 2.0 as KQControls
import QtQuick.Layouts 1.15 as QQLayouts
import "i18n.js" as I18n

Kirigami.ScrollablePage {
    id: appearancePage
    signal configurationChanged

    property alias cfg_languageIndex: languageComboBox.currentIndex
    readonly property string language: I18n.languageForIndex(cfg_languageIndex)

    property alias cfg_showAlbumCover: showAlbumCoverCheckBox.checked
    property alias cfg_enableSpotifySearch: enableSpotifySearchCheckBox.checked
    property alias cfg_lyricTextSize: lyricTextSizeSpinBox.value 
    property alias cfg_lyricTextColor: lyricTextColorButton.color
    property alias cfg_lyricTextBold: boldButton.checked   
    property alias cfg_lyricTextItalic: italicButton.checked 
    property alias cfg_lyricTextVerticalOffset: lyricTextVerticalOffsetSpinBox.value
    property alias cfg_lyricTextAlignment: lyricTextAlignmentComboBox.currentIndex
    property alias cfg_convertToSimplified: convertToSimplifiedCheckBox.checked
    property bool cfg_scrollingLyrics: false
    property bool cfg_karaokeLyrics: true
    property alias cfg_karaokeFrameRate: karaokeFrameRateSpinBox.value

    property alias cfg_mediaControllSpacing: mediaControllSpacingSpinBox.value
    property alias cfg_mediaControllItemSize: mediaControllItemSizeSpinBox.value
    property alias cfg_albumCoverItemSize: albumCoverItemSizeSpinBox.value
    property alias cfg_whiteMediaControlIconsChecked: whiteMediaControlIconsChecked.checked

    property alias cfg_dynamicWidth: dynamicWidthCheckBox.checked
    property alias cfg_enableTextScrolling: enableTextScrollingCheckBox.checked
    property alias cfg_preferedWidgetWidth: preferedWidgetWidthSpinBox.value
    property alias cfg_hideItemWhenNoControlChecked: hideItemWhenNoControlChecked.checked

    property int cfg_playerMode: 0

    verticalScrollBarPolicy: QQC2.ScrollBar.AsNeeded
    horizontalScrollBarPolicy: QQC2.ScrollBar.AlwaysOff

    Kirigami.FormLayout {
        width: Math.min(parent ? parent.width : appearancePage.width, 760)
        x: parent ? Math.max(0, (parent.width - width) / 2) : 0

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "语言")
        }

        QQC2.ComboBox {
            id: languageComboBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "界面语言：")
            model: ["简体中文", "繁體中文", "English", "Español / 西班牙语", "Русский / 俄语", "Deutsch / 德语"]
            QQLayouts.Layout.maximumWidth: 300
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(appearancePage.language, "切换语言后点击“应用”生效。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "歌词匹配模式")
        }

        QQLayouts.ColumnLayout {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                QQLayouts.Layout.fillWidth: true
                text: I18n.tr(appearancePage.language, "全局模式优先跟随正在播放的应用；没有应用正在播放时，保持当前应用，暂停状态也可显示。")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.78
            }

            QQC2.Label {
                QQLayouts.Layout.fillWidth: true
                text: I18n.tr(appearancePage.language, "浏览器模式匹配浏览器（包括 Plasma 浏览器集成）；多个浏览器同时播放时，按 Edge → Firefox → Chrome → Chromium → Brave → Opera → Vivaldi 的优先级选择。")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.78
            }

            QQC2.Label {
                QQLayouts.Layout.fillWidth: true
                text: I18n.tr(appearancePage.language, "串流音频软件匹配模式仅匹配 Sidra、Cider、YesPlayMusic、Spotube、Tizonia、QQ 音乐、Spotify、YouTube Music Desktop、Tidal、Qobuz；多个串流应用同时播放时，最先开始播放的应用优先显示。")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.78
            }

            QQC2.Label {
                QQLayouts.Layout.fillWidth: true
                text: I18n.tr(appearancePage.language, "浏览器/串流模式只显示对应类型的目标应用。若有其他类型应用正在播放，或没有可用的目标应用，组件会暂时隐藏。目标应用暂停后，只要没有其他类型应用在播放，组件仍保持显示。")
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.78
            }
        }

        QQLayouts.ColumnLayout {
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "匹配模式：")
            spacing: Kirigami.Units.smallSpacing

            QQC2.ButtonGroup {
                id: playerModeGroup
            }

            QQC2.RadioButton {
                id: globalModeRadio
                text: I18n.tr(appearancePage.language, "全局模式")
                QQC2.ButtonGroup.group: playerModeGroup
                checked: appearancePage.cfg_playerMode === 0
                onToggled: if (checked) appearancePage.cfg_playerMode = 0
            }

            QQC2.RadioButton {
                id: browserModeRadio
                text: I18n.tr(appearancePage.language, "浏览器模式")
                QQC2.ButtonGroup.group: playerModeGroup
                checked: appearancePage.cfg_playerMode === 1
                onToggled: if (checked) appearancePage.cfg_playerMode = 1
            }

            QQC2.RadioButton {
                id: streamingModeRadio
                text: I18n.tr(appearancePage.language, "串流音频软件匹配模式")
                QQC2.ButtonGroup.group: playerModeGroup
                checked: appearancePage.cfg_playerMode === 2
                onToggled: if (checked) appearancePage.cfg_playerMode = 2
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "文本与排版")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(appearancePage.language, "歌词显示模式三选一：逐字歌词在逐字数据可用时从左到右扫过高亮，没有逐字数据时回退为普通歌词；滚动歌词逐行显示；渐显渐隐歌词使用淡入淡出切换。歌词转换仅影响中文文本。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        QQC2.SpinBox {
            id: lyricTextSizeSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "歌词字体大小：")
            from: 8
            to: 36
            stepSize: 1
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.ComboBox {
            id: lyricTextAlignmentComboBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "文本对齐：")
            model: [I18n.tr(appearancePage.language, "左对齐"), I18n.tr(appearancePage.language, "居中"), I18n.tr(appearancePage.language, "右对齐")]
            currentIndex: 2
            QQLayouts.Layout.maximumWidth: 160
        }

        QQC2.CheckBox {
            id: convertToSimplifiedCheckBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "歌词转换：")
            text: I18n.tr(appearancePage.language, "繁体中文转换为简体中文")
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "只转换歌词文本，不改变歌曲信息")
            checkable: true
        }

        QQLayouts.ColumnLayout {
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "歌词显示：")
            spacing: Kirigami.Units.smallSpacing

            QQC2.ButtonGroup {
                id: lyricsModeGroup
            }

            QQC2.RadioButton {
                id: scrollingLyricsRadio
                text: I18n.tr(appearancePage.language, "滚动歌词")
                QQC2.ButtonGroup.group: lyricsModeGroup
                checked: !appearancePage.cfg_karaokeLyrics && appearancePage.cfg_scrollingLyrics
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_karaokeLyrics = false
                        appearancePage.cfg_scrollingLyrics = true
                    }
                }
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "逐行显示，切换时轻微上移并淡入；需要普通同步歌词")
            }

            QQC2.RadioButton {
                id: karaokeLyricsRadio
                text: I18n.tr(appearancePage.language, "逐字歌词")
                QQC2.ButtonGroup.group: lyricsModeGroup
                checked: appearancePage.cfg_karaokeLyrics
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_karaokeLyrics = true
                        appearancePage.cfg_scrollingLyrics = false
                    }
                }
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "逐字从左到右扫过高亮；需要逐字歌词数据，没有时自动回退为普通歌词")
            }

            QQC2.RadioButton {
                id: fadeLyricsRadio
                text: I18n.tr(appearancePage.language, "渐显渐隐歌词")
                QQC2.ButtonGroup.group: lyricsModeGroup
                checked: !appearancePage.cfg_karaokeLyrics && !appearancePage.cfg_scrollingLyrics
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_karaokeLyrics = false
                        appearancePage.cfg_scrollingLyrics = false
                    }
                }
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "歌词切换使用原有的渐显渐隐动画；需要普通同步歌词")
            }
        }

        QQC2.SpinBox {
            id: karaokeFrameRateSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "逐字高亮刷新率（FPS）：")
            from: 10
            to: 120
            stepSize: 5
            editable: true
            enabled: karaokeLyricsRadio.checked
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "数值越低越省 CPU；建议 30–60，过低会不够顺滑")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(appearancePage.language, "降低刷新率可减少 CPU 占用；30–60 FPS 通常足够。低于 30 FPS 时，逐字高亮的移动可能不够顺滑。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        QQLayouts.RowLayout {
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "颜色与字形：")
            spacing: Kirigami.Units.smallSpacing

            KQControls.ColorButton {
                id: lyricTextColorButton
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "歌词文字颜色")
            }

            QQC2.Button {
                id: boldButton
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "粗体")
                icon.name: "format-text-bold"
                checkable: true
            }

            QQC2.Button {
                id: italicButton
                QQC2.ToolTip.text: I18n.tr(appearancePage.language, "斜体")
                icon.name: "format-text-italic"
                checkable: true
            }
        }

        QQC2.SpinBox {
            id: lyricTextVerticalOffsetSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "文本垂直偏移：")
            from: -20
            to: 20
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "负值上移，正值下移")
            QQLayouts.Layout.maximumWidth: 130
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "媒体控制与专辑封面")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(appearancePage.language, "调整播放控制图标、专辑封面与间距。关闭专辑封面后，Spotify 快速搜索也不可用。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        QQC2.CheckBox {
            id: showAlbumCoverCheckBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "显示专辑封面：")
            text: I18n.tr(appearancePage.language, "显示当前曲目的专辑封面")
            checkable: true
        }

        QQC2.CheckBox {
            id: enableSpotifySearchCheckBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "Spotify 搜索：")
            text: I18n.tr(appearancePage.language, "点击专辑封面时打开 Spotify 快速搜索")
            checkable: true
            enabled: showAlbumCoverCheckBox.checked
        }

        QQC2.CheckBox {
            id: whiteMediaControlIconsChecked
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "白色控制图标：")
            text: I18n.tr(appearancePage.language, "适合深色面板")
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "将播放控制图标切换为白色")
            checkable: true
        }

        QQC2.SpinBox {
            id: mediaControllItemSizeSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "控制图标大小：")
            from: 10
            to: 32
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "播放控制图标的大小")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.SpinBox {
            id: albumCoverItemSizeSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "专辑封面大小：")
            from: 10
            to: 48
            enabled: showAlbumCoverCheckBox.checked
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "专辑封面的显示大小")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.SpinBox {
            id: mediaControllSpacingSpinBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "图标间距：")
            from: 2
            to: 30
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "图标之间的水平间距")
            QQLayouts.Layout.maximumWidth: 130
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "尺寸与行为")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            QQLayouts.Layout.fillWidth: true
            QQLayouts.Layout.maximumWidth: 680
            text: I18n.tr(appearancePage.language, "动态宽度会随歌词长度调整；关闭后使用固定宽度。暂停不会隐藏组件，只有播放器关闭或停止提供媒体会话后才会隐藏。")
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.78
        }

        QQC2.CheckBox {
            id: dynamicWidthCheckBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "动态控件宽度：")
            text: I18n.tr(appearancePage.language, "根据歌词长度自动调整控件宽度")
            checkable: true
        }

        QQC2.SpinBox {
            id: preferedWidgetWidthSpinBox
            Kirigami.FormData.label: dynamicWidthCheckBox.checked ? I18n.tr(appearancePage.language, "最大控件宽度（像素）：") : I18n.tr(appearancePage.language, "固定控件宽度（像素）：")
            from: 100
            to: 2000
            stepSize: 50
            value: 850
            QQC2.ToolTip.text: dynamicWidthCheckBox.checked ? I18n.tr(appearancePage.language, "动态模式下的最大宽度") : I18n.tr(appearancePage.language, "固定模式下的控件宽度")
            QQLayouts.Layout.maximumWidth: 130
        }

        QQC2.CheckBox {
            id: enableTextScrollingCheckBox
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "文本滚动：")
            text: I18n.tr(appearancePage.language, "歌词超出控件宽度时水平滚动")
            checkable: true
        }

        QQC2.CheckBox {
            id: hideItemWhenNoControlChecked
            Kirigami.FormData.label: I18n.tr(appearancePage.language, "无播放器时隐藏：")
            text: I18n.tr(appearancePage.language, "没有检测到播放器时隐藏")
            QQC2.ToolTip.text: I18n.tr(appearancePage.language, "暂停时保持显示，播放器关闭后才隐藏")
            checkable: true
        }
    }
}
