let host = null;

chrome.runtime.onMessage.addListener((payload, sender) => {
  if (!sender.tab || !sender.url?.startsWith("https://music.youtube.com/")) return;
  if (!host) {
    host = chrome.runtime.connectNative("com.openbox_island.ytm_bridge");
    host.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      host = null;
    });
  }
  host.postMessage(payload);
});
