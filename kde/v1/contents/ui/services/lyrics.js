/**
    Parse the lyric file and convert it to a list of dictionaries. Each dictionary contains a timestamp and the corresponding lyric.
    The format of the lyric file is as follows:
    [00:34.33] 妳說這一句 很有夏天的感覺
    [00:41.06] 手中的鉛筆 在紙上來來回回
    [00:47.45] 我用幾行字形容妳是我的誰
    [00:54.19] 秋刀魚 的滋味 貓跟妳都想瞭解
*/
function parseLyric(lrcFile) {
    // console.log(lrcFile)
    var lrcList = lrcFile.split("\n");
    for (var i = 0; i < lrcList.length; i++) {
        var lyricPerRowWTime = lrcList[i].split("]");
        if (lyricPerRowWTime.length > 1) {
            var timestamp = parseTime(lyricPerRowWTime[0].replace("[", "").trim());
            var lyricPerRow = lyricPerRowWTime[1].trim();
            lyricsWTimes.append({time: timestamp, lyric: lyricPerRow});
        }
    }
    /** 
        Add an empty lyric at the end to avoid can't reach last correct lyric forever.
        This empty lyric like {song's length, ""}
    */
    lyricsWTimes.append({time: length, lyric: ""});
    lyricDisplayTimer.start()
}

function fetchMediaIdYPM() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", ypm_base_url + "/player");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            if (xhr.responseText) {
                var response = JSON.parse(xhr.responseText);
                if (response && response.currentTrack && response.currentTrack.name === currentMediaTitle) {
                    previousMediaTitle = currentMediaTitle;
                    previousMediaArtists = currentMediaArtists;
                    currentMediaYPMId = response.currentTrack.id;
                    fetchSyncLyricYPM();
                }
            }
        }
    };
    xhr.send();
}

// fetch the current media lyric from yesplaymusic by media id
function fetchSyncLyricYPM() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", ypm_base_url + "/api/lyric?id=" + currentMediaYPMId);
    xhr.onreadystatechange = function() {
        if (xhr.status === 200) {
            var response = JSON.parse(xhr.responseText);
            print(xhr.responseText)
            //console.log("YPM Network OK");
            if (response && response.lrc && response.lrc.lyric) {
                lyricsWTimes.clear();
                //console.log("Successfully fetched YPM lyrics");
                isYPMLyricFound = true;
                parseLyric(response.lrc.lyric);
            } else if (!response.lrc || !response.lrc.lyric) {
                //console.log("YPM lyric not found");
                lyricsWTimes.clear();
                lyricText.text = lrc_not_exists;
            }
        }
    };
    xhr.send();
}

function fetchSyncLyricLX() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", lxmusic_base_url + "/lyric");
    xhr.onreadystatechange = function() {
        if (xhr.status === 200) {
            var lrc_raw = xhr.responseText;
            if (lrc_raw) {
                lyricsWTimes.clear();
                isLXLyricFound = true;
                parseLyric(lrc_raw);
            } else if (!lrc_raw) {
                lyricsWTimes.clear();
                lyricText.text = lrc_not_exists;
            }
        }
    };
    xhr.send();
}

function fetchMediaInfoSP() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", splayer_base_url + "/api/control/song-info");
    xhr.onreadystatechange = function() {
        if (xhr.status === 200 && xhr.readyState === XMLHttpRequest.DONE) {
            var response = JSON.parse(xhr.responseText);
            if (response && response.data && !response.data.lyricLoading) {
                parseSyncLyricSP(response.data.lrcData);
            } else {
                lyricsWTimes.clear();
                lyricText.text = lrc_not_exists;
            }
        }
    };
    xhr.send();
}

function parseSyncLyricSP(lyricsOriginList) {
    var finalLyrics = new Array();
    for (var i = 0; i < lyricsOriginList.length; i++) {
        for (var j = 0; j < lyricsOriginList[i].words.length; j++) {
            var lyric = "[mm:ss]{lyric}"
            var currentTime = lyricsOriginList[i].words[j].startTime;
            var currentLyric =  lyricsOriginList[i].words[j].word;
            var currentMM = currentTime/1000/60;
            var currentSS = (currentTime/1000) % 60;
            finalLyrics.push(lyric
                .replace("mm", parseInt(currentMM))
                .replace("ss", currentSS.toFixed(3))
                .replace("{lyric}", currentLyric)
            );
        }
    }
    if (finalLyrics.length > 0) {
        lyricsWTimes.clear();
        parseLyric(finalLyrics.join("\n"));
    } else {
        lyricsWTimes.clear();
        lyricText.text = lrc_not_exists;
    }
    isSPlayerLyricFound = true;
}

/**
    ================================================================================================================================================================================
    If the current media title is advertisement, then we will not query the API. This happens in apps like Spotify and the user is not a premium user.
    Also, if we've already found the lyric, then we will not spam querying the API.
    ================================================================================================================================================================================
    Elsewise, Start querying the lrclib API for the current media title and artists. If the response is empty, then we will go to the fall back mode. 
    Specifically speaking, check the details in lrcQueryUrl variable.
    ================================================================================================================================================================================
    If the response is not empty and the current playing music is different from the previous plyaing music, then we will reset the timer, parse the lyric and display it on the screen. 

*/
function fetchLyricsCompatibleMode() {
    if (currentMediaTitle === "Advertisement" || isCompatibleLRCFound) {
        return;
    }

    var xhr = new XMLHttpRequest();
    xhr.open("GET", lrcQueryUrl);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
            if (!xhr.responseText || xhr.responseText === "[]") {
                needFallback = true;
                previousLrcId = Number.MIN_VALUE;
                lyricsWTimes.clear();
                lyricText.text = lrc_not_exists;
            } else {
                var response = JSON.parse(xhr.responseText);

                /**
                    Fix: LrcLib might return multiple result for the same [track_name, artist_name, album_name], some of the result doesn't contain the syncedLyrics field.

                    An example could be as listed below
                    [
                        {"id":13957,"name":"Jar Of Love","trackName":"Jar Of Love","artistName":"Wanting","albumName":"Everything In The World", xxx},
                        {"id":18131162,"name":"Jar Of Love","trackName":"Jar Of Love","artistName":"Wanting 曲婉婷","albumName":"Everything In The World","duration":229.026667, xxxx}
                    ]
                */
                for (var i = 0; i < response.length; i++) {
                    var responseItem = response[i]
                    if (previousLrcId !== responseItem.id.toString()) {
                        if (responseItem.syncedLyrics) {
                            reset()
                            previousLrcId = responseItem.id.toString();
                            isCompatibleLRCFound = true;
                            parseLyric(responseItem.syncedLyrics);
                            break;
                        } 
                    }
                }

                // If reached here, it means the lrc file is just broken or doesn't follow the standard format. No need to fallback again since actually we can retrieve it. 
                isCompatibleLRCFound = true;
                lyricText.text = lrc_not_exists;
            }
        }
    };
    xhr.send();
}

function parseTime(timeString) {
    var parts = timeString.split(":");
    var minutes = parseInt(parts[0], 10);
    var seconds = parseFloat(parts[1]);
    var parsedMicrosecond = (minutes * 60 + seconds) * 1000000
    return parsedMicrosecond;
}

function ypmHandler() {
    if (currentMediaArtists === "" && currentMediaTitle === "") {
            lyricText.text = " ";
            lyricsWTimes.clear();
    } else {
        if (!isYPMLyricFound) {
            reset();
            fetchMediaIdYPM();  
        }
    }
}

function lxHandler() {
    if (currentMediaArtists === "" && currentMediaTitle === "") {
        lyricText.text = " ";
        lyricsWTimes.clear();
    } else {
        if (!isLXLyricFound) {
            fetchSyncLyricLX();
        }
    }
}

function splayerHandler() {
    if (currentMediaArtists === "" && currentMediaTitle === "") {
        lyricText.text = " ";
        lyricsWTimes.clear();
    } else {
        if (!isSPlayerLyricFound) {
            fetchMediaInfoSP();
        }
    }
}

/**
    1. Stop the compatible mode timer and yesplaymusic timer.
    2. Set the previous media title and artists to the current media title and artists.
    3. Set the previous player name to the current player name.
    4. Set the previous expected player Identity to the current expected player Identity
    5. Clear the lyricsWTimes list.
    6. Clear the previous non empty lyric.
    7. Clear the previous lrc id.
    8. Set the fallback mode to false, meaning that first query the lrclibAPI with precise matching, if failed, then go to the fallback mode.
    9. Set compatibleLRCFound to false, meaning that we haven't found the lyric yet(From LrcLib for compatible(global)/spotify mode).
    10. Set isYPMLyricFound to false, meaning that we haven't found the lyric yet(From YPM, YPM mode only).
*/
function reset() {
    compatibleModeTimer.stop();
    yesPlayMusicTimer.stop();
    lxMusicTimer.stop();
    splayerTimer.stop();
    previousMediaTitle = currentMediaTitle;
    previousMediaArtists = currentMediaArtists;
    mpris2PreviousPlayerIdentity = mpris2CurrentPlayerIdentity;
    prevExpectedPlayerIdentity = currExpectedPlayerIdentity;
    lyricsWTimes.clear();
    prevNonEmptyLyric = "";
    previousLrcId = "";
    needFallback = false;
    lyricText.text = " ";
    isCompatibleLRCFound = false;
    isYPMLyricFound = false;
    isLXLyricFound = false;
    isSPlayerLyricFound = false;
}
