(() => {
  let previous = "";
  let lastSent = 0;
  let timer = 0;

  // After the extension reloads, this orphaned script's chrome.runtime calls
  // throw "Extension context invalidated" synchronously (not a rejected
  // promise), so stop quietly instead of throwing every second.
  function send(payload) {
    try {
      const sent = chrome.runtime.sendMessage(payload);
      if (sent && sent.catch) sent.catch(() => stop());
    } catch {
      stop();
    }
  }

  function stop() {
    clearInterval(timer);
    removeEventListener("pagehide", gone);
    removeEventListener("beforeunload", gone);
  }

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
    send({ ...payload, ts: now });
  }

  const gone = () => send({ gone: true });
  addEventListener("pagehide", gone);
  addEventListener("beforeunload", gone);

  poll();
  timer = setInterval(poll, 1000);
})();
