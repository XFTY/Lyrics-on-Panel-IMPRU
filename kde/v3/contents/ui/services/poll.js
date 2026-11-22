function handlePollResponse(data) {
    if (!data || !data.player) {
        hasActivePlayer = false
        hasSyncedLyrics = false
        hasWordLyrics = false
        currentWords = []
        currentLineStartMs = 0
        currentLineEndMs = 0
        nextWords = []
        nextHasWordLyrics = false
        nextLineStartMs = 0
        nextLineEndMs = 0
        afterNextLyric = ""
        afterNextWords = []
        afterNextHasWordLyrics = false
        afterNextLineStartMs = 0
        afterNextLineEndMs = 0
        karaokeBasePositionMs = 0
        karaokeBaseTimestamp = Date.now()
        karaokePositionMs = 0
        currentLyric = ""
        nextLyric = ""
        currentLyricDurationMs = 0
        timeRemainingMs = 0
        currentTitle = ""
        currentArtist = ""
        playbackStatus = "stopped"
        return
    }

    hasActivePlayer = true
    playbackStatus = data.playback_status || "stopped"

    if (data.player) {
        currentPlayerBusName = data.player.bus_name || ""
    }

    var incomingTrackTitle = data.track ? (data.track.title || "") : ""
    var trackChanged = !!data.track && incomingTrackTitle !== currentTitle

    if (data.track) {
        currentTitle = data.track.title || ""
        currentArtist = data.track.artist || ""
        currentArtUrl = data.track.art_url || ""
    }

    if (data.lyrics) {
        var incomingWords = Array.isArray(data.lyrics.current_words) ? data.lyrics.current_words : []
        var incomingNextWords = Array.isArray(data.lyrics.next_words) ? data.lyrics.next_words : []
        var incomingAfterNextWords = Array.isArray(data.lyrics.after_next_words) ? data.lyrics.after_next_words : []
        var incomingPos = (data.lyrics.position_ms !== undefined)
            ? data.lyrics.position_ms
            : Math.floor((data.position_ms || 0) / 1000)
        var incomingPlaying = (data.playback_status || "stopped") === "playing"
        var canSmoothClock = incomingPlaying && karaokeBaseTimestamp > 0
        var clockResynced = !canSmoothClock
        if (canSmoothClock) {
            var localNow = karaokeBasePositionMs + (Date.now() - karaokeBaseTimestamp)
            var drift = incomingPos - localNow
            if (Math.abs(drift) > 1500) {
                karaokeBasePositionMs = incomingPos
                clockResynced = true
            } else {
                karaokeBasePositionMs = localNow
            }
        } else {
            karaokeBasePositionMs = incomingPos
        }
        karaokeBaseTimestamp = Date.now()
        karaokePositionMs = karaokeBasePositionMs

        var incomingLyric = data.lyrics.current_lyric || ""
        var incomingStart = data.lyrics.current_line_start_ms || 0
        var localLineAhead = !trackChanged && !clockResynced && incomingPlaying && config_karaokeLyrics
            && incomingStart < currentLineStartMs

        hasSyncedLyrics = data.lyrics.has_synced_lyrics === true
        if (!localLineAhead) {
            if (currentLyric !== incomingLyric
                    || currentLineStartMs !== incomingStart
                    || currentWords.length !== incomingWords.length)
                currentWords = incomingWords
            hasWordLyrics = data.lyrics.has_word_lyrics === true
            currentLineStartMs = incomingStart
            currentLineEndMs = data.lyrics.current_line_end_ms || 0
            currentLyric = incomingLyric
            nextLyric = data.lyrics.next_lyric || ""
            nextWords = incomingNextWords
            nextHasWordLyrics = data.lyrics.next_has_word_lyrics === true
            nextLineStartMs = data.lyrics.next_line_start_ms || 0
            nextLineEndMs = data.lyrics.next_line_end_ms || 0
            afterNextLyric = data.lyrics.after_next_lyric || ""
            afterNextWords = incomingAfterNextWords
            afterNextHasWordLyrics = data.lyrics.after_next_has_word_lyrics === true
            afterNextLineStartMs = data.lyrics.after_next_line_start_ms || 0
            afterNextLineEndMs = data.lyrics.after_next_line_end_ms || 0
            currentLyricDurationMs = data.lyrics.current_lyric_duration_ms || 0
            timeRemainingMs = data.lyrics.time_remaining_ms || 0
        }
    } else {
        hasSyncedLyrics = false
        hasWordLyrics = false
        currentWords = []
        currentLineStartMs = 0
        currentLineEndMs = 0
        nextLyric = ""
        nextWords = []
        nextHasWordLyrics = false
        nextLineStartMs = 0
        nextLineEndMs = 0
        afterNextLyric = ""
        afterNextWords = []
        afterNextHasWordLyrics = false
        afterNextLineStartMs = 0
        afterNextLineEndMs = 0
        karaokeBasePositionMs = Math.floor((data.position_ms || 0) / 1000)
        karaokeBaseTimestamp = Date.now()
        karaokePositionMs = karaokeBasePositionMs
        currentLyric = ""
        currentLyricDurationMs = 0
        timeRemainingMs = 0
    }
}
