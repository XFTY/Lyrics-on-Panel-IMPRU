function log() {
    console.log("currentMediaArtists: ", currentMediaArtists);
    console.log("previousMediaArtists: ", previousMediaArtists);
    console.log("currentMediaTitle: ", currentMediaTitle);
    console.log("previousMediaTitle: ", previousMediaTitle);
    console.log("Mpris2 Model: ", JSON.stringify(mpris2Model))
    console.log("Current Player Identity: ", mpris2CurrentPlayerIdentity);
    console.log(mpris2Model);
    console.log(mpris2Model.toString());
    console.log("Is wrong player: ", isWrongPlayer());
}

function previous() {
    if (!isWrongPlayer()) {
       mpris2Model.currentPlayer.Previous(); 
    }
}

function play() {
    if (!isWrongPlayer()) {
       mpris2Model.currentPlayer.Play(); 
    }
}

function pause() {
    if (!isWrongPlayer()) {
        mpris2Model.currentPlayer.Pause();
    }
}

function next() {
    if (!isWrongPlayer()) {
        mpris2Model.currentPlayer.Next();
    }
}

// Fix the problem of current playing media doesn't match the selected mode.
function isWrongPlayer() {
    if (mpris2CurrentPlayerIdentity != currExpectedPlayerIdentity) {
        if (currExpectedPlayerIdentity == "compatible") {
            return false;
        } else {
            return true;
        }
    } 
    return false;
}
