function createBridgeAuthority() {
  const tabs = new Map();
  let sequence = 0;

  function current(now) {
    let selected = null;
    for (const [id, tab] of tabs) {
      if (now - tab.seen > 10000) {
        tabs.delete(id);
        continue;
      }
      if (!selected || (tab.payload.playing && !selected.payload.playing) ||
          (tab.payload.playing === selected.payload.playing && tab.order > selected.order)) {
        selected = tab;
      }
    }
    return selected?.payload;
  }

  return {
    update(id, payload, now = Date.now()) {
      const previous = tabs.get(id);
      const order = payload.playing || previous?.payload.playing
        ? ++sequence : (previous?.order ?? 0);
      tabs.set(id, { payload, order, seen: now });
      return current(now);
    },
    remove(id, now = Date.now()) {
      const previous = current(now);
      tabs.delete(id);
      const selected = current(now);
      return selected !== previous ? selected : undefined;
    },
  };
}

if (typeof module !== 'undefined') module.exports = { createBridgeAuthority };
