document.addEventListener("DOMContentLoaded", function () {
    const playlist = document.querySelector("[data-playlist]");
    if (!playlist) return;

    const player = playlist.querySelector("audio");
    const tracks = playlist.querySelectorAll(".sap-track");
    if (!player || tracks.length === 0) return;

    let current = 0;

    function playTrack(index, restoreTime = false) {
        const track = tracks[index];
        if (!track) return;
        const src = track.getAttribute("data-src");
        if (!src) return;

        player.src = src;
        player.load();

        tracks.forEach(t => t.classList.remove("active"));
        track.classList.add("active");
        current = index;

        // Lưu lại trạng thái
        localStorage.setItem("sap-last-index", index);
        localStorage.setItem("sap-last-src", src);

        // Nếu có thời gian lưu trước đó thì khôi phục
        if (restoreTime) {
            const savedTime = parseFloat(localStorage.getItem("sap-last-time") || "0");
            if (!isNaN(savedTime)) {
                player.currentTime = savedTime;
            }
        }

        player.play();
    }

    // Khi user click
    tracks.forEach((track, i) => {
        track.addEventListener("click", () => {
            playTrack(i, false);
        });
    });

    // Khi phát xong thì tự qua bài sau
    player.addEventListener("ended", () => {
        if (current + 1 < tracks.length) {
            playTrack(current + 1, false);
        }
    });

    // Lưu thời gian phát định kỳ
    player.addEventListener("timeupdate", () => {
        localStorage.setItem("sap-last-time", player.currentTime);
    });

    // Lấy lại trạng thái trước đó
    const lastIndex = parseInt(localStorage.getItem("sap-last-index"));
    const lastSrc = localStorage.getItem("sap-last-src");
    if (!isNaN(lastIndex) && lastSrc && tracks[lastIndex]) {
        const track = tracks[lastIndex];
        const trackSrc = track.getAttribute("data-src");
        if (trackSrc === lastSrc) {
            playTrack(lastIndex, true);
        } else {
            playTrack(0, false);
        }
    } else {
        playTrack(0, false);
    }
});
