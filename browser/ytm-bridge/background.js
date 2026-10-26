importScripts("authority.js");
const authority = createBridgeAuthority();

let host = null;

function forward(payload) {
  if (!payload) return;
  if (!host) {
    host = chrome.runtime.connectNative("com.openbox_island.ytm_bridge");
    host.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      host = null;
    });
  }
  host.postMessage(payload);
}

chrome.runtime.onMessage.addListener((payload, sender) => {
  if (!sender.tab || !sender.url?.startsWith("https://music.youtube.com/")) return;
  const selected = authority.update(sender.tab.id, payload);
  if (selected === payload) forward(selected);
});

chrome.tabs.onRemoved.addListener(id => {
  forward(authority.remove(id));
});
