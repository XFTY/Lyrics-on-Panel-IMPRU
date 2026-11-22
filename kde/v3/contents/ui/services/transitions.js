function maybePromoteKaraokeLine() {
    if (!config_karaokeLyrics || playbackStatus !== "playing")
        return
    if (!nextLyric || nextLineStartMs <= 0 || nextLineStartMs <= currentLineStartMs)
        return
    if (karaokeTimeMs < nextLineStartMs)
        return

    var promotedLyric = nextLyric
    currentWords = nextWords
    hasWordLyrics = nextHasWordLyrics
    currentLineStartMs = nextLineStartMs
    currentLineEndMs = nextLineEndMs
    nextLyric = afterNextLyric
    nextWords = afterNextWords
    nextHasWordLyrics = afterNextHasWordLyrics
    nextLineStartMs = afterNextLineStartMs
    nextLineEndMs = afterNextLineEndMs
    afterNextLyric = ""
    afterNextWords = []
    afterNextHasWordLyrics = false
    afterNextLineStartMs = 0
    afterNextLineEndMs = 0
    currentLyric = promotedLyric
}

function triggerTransition() {
    if (scrollingLyricsActive) {
        playScrollingLyricAnimation()
        return
    }

    if (karaokeLyricsActive) {
        fadeTransitionAnimation.stop()
        slideTransitionAnimation.stop()
        nextLyricFadeIn.stop()
        scrollingLyricAnimation.stop()
        lyricColumn.opacity = 1.0
        displayedLyric = currentLyric
        displayedNextLyric = nextLyric
        currentTranslate.y = 0
        nextTranslate.y = 0
        nextScale.xScale = 0.85
        nextScale.yScale = 0.85
        currentLyricText.opacity = 1.0
        nextLyricText.opacity = config_nextLyricOpacity
        return
    }

    if (config_transitionDurationMs <= 0) {
        displayedLyric = currentLyric
        displayedNextLyric = nextLyric
        return
    }

    var canSlide = config_showNextLyric && displayedNextLyric !== "" && currentLyric === displayedNextLyric;
    if (canSlide) {
        slideTransitionAnimation.restart()
    } else {
        fadeTransitionAnimation.restart()
    }
}

function playScrollingLyricAnimation() {
    fadeTransitionAnimation.stop()
    slideTransitionAnimation.stop()
    nextLyricFadeIn.stop()
    scrollingLyricAnimation.stop()
    lyricColumn.opacity = 1.0
    displayedLyric = currentLyric
    displayedNextLyric = nextLyric
    currentTranslate.y = 6
    currentLyricText.opacity = 0.45
    scrollingLyricAnimation.start()
}

function handleNextLyricChanged() {
    if (!fadeTransitionAnimation.running && !slideTransitionAnimation.running) {
        displayedNextLyric = nextLyric
    }
}

function handleLrcNotExistsChanged() {
    if (!currentLyric)
        triggerTransition()
}

function handleScrollingLyricsActiveChanged() {
    if (scrollingLyricsActive) {
        fadeTransitionAnimation.stop()
        slideTransitionAnimation.stop()
        nextLyricFadeIn.stop()
        scrollingLyricAnimation.stop()
        lyricColumn.opacity = 1.0
        currentTranslate.y = 0
        currentLyricText.opacity = 1.0
        if (currentLyric && displayedLyric !== currentLyric) {
            playScrollingLyricAnimation()
        }
    } else {
        fadeTransitionAnimation.stop()
        slideTransitionAnimation.stop()
        nextLyricFadeIn.stop()
        scrollingLyricAnimation.stop()
        lyricColumn.opacity = 1.0
        currentLyricText.opacity = 1.0
        currentTranslate.y = 0
        nextTranslate.y = 0
        nextScale.xScale = 0.85
        nextScale.yScale = 0.85
        nextLyricText.opacity = config_nextLyricOpacity
        displayedLyric = currentLyric
        displayedNextLyric = nextLyric
    }
}
