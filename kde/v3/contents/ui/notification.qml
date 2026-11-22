import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage

    Text {
        id: notificationText
        text: "此控件仅适用于 Plasma 6，不支持 Plasma 5。如果你使用的是 Plasma 5，请搜索 lyric-on-panel-plasma5。\n\n由于 Plasma API 发生变化，我重构了大部分代码，仅保留了核心的歌词查询逻辑。因此，两个版本控件的质量可能会有所差异。\n\n我目前正忙于寻找实习，所以暂时目标只是让这个控件可用。很抱歉我没有太多时间探索新的 Plasma API。\n如果时间允许，我会尝试让多个逻辑的实现更加优雅，并通过将 C++ 集成到此控件中来增加更多功能。"
        color: "red"
    }

    Text {
        id: latestVersionUpdate
        text: "\n[v1.1.3] 2024/05/29 - 重大错误修复，提升准确性。\n\n    1. 移除了配置页面中的开发者说明部分，并新增了更新日志与教程部分。\n\n    2. 现在，如果你从 YesPlayMusic 模式切换到 Spotify 模式，我们会先暂停 YesPlayMusic 中正在播放的音乐。然后你需要手动打开 Spotify 并点击播放（继续）按钮。反之亦然。\n\n    3. 修复了切换到 YesPlayMusic 模式后仍会显示 Spotify 歌词的问题。\n\n    4. 现在你可以在配置页面中控制此控件的宽度。\n\n\n"
    }

    Text {
        id: notificationText2
        text: "【仅致 YesPlayMusic 用户】：请关闭全局网络代理，改用规则代理。YPM 在处理代理方面存在已知缺陷，很可能导致此控件无法从 YPM 本地 API 获取歌词。"
        color: "red"
    }

    Text {
        id: notificationH2
        text: "如果你遇到任何错误，欢迎告诉我。有两种方法可以重置此控件：\n"
    }

    Text {
        id: notificationText3
        text: "         1. 在终端中输入：plasmashell --replace"
    }

    Text {
        id: notificationText4
        text: "         2. 从面板中移除此控件，然后重新添加。"
    }

    Text {
        id: notificationText5
        text: "\n\n\n如果你觉得这个控件有用，请给它点赞并为我的 GitHub 仓库加星！如需报告错误或提出功能建议，请在 KDE 商店留言或在 GitHub 提交 issue。"
    }
}
