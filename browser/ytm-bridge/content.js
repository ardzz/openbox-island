(() => {
  let previous = "";
  let lastSent = 0;

  function poll() {
    const session = navigator.mediaSession;
    const metadata = session?.metadata;
    if (!metadata) return;

    const media = document.querySelector("video, audio");
    const state = session.playbackState;
    const payload = {
      title: metadata.title || "",
      artist: metadata.artist || "",
      album: metadata.album || "",
      video_id: new URL(location.href).searchParams.get("v") || "",
      playing: state === "playing" || (state === "none" && !!media && !media.paused),
    };
    const serialized = JSON.stringify(payload);
    const now = Date.now();
    if (serialized === previous && now - lastSent < 5000) return;

    previous = serialized;
    lastSent = now;
    chrome.runtime.sendMessage({ ...payload, ts: now }).catch(() => {});
  }

  poll();
  setInterval(poll, 1000);
})();
