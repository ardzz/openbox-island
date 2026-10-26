function createBridgeAuthority() {
  const tabs = new Map();
  let sequence = 0;

  function current() {
    let selected = null;
    for (const tab of tabs.values()) {
      if (!selected || (tab.payload.playing && !selected.payload.playing) ||
          (tab.payload.playing === selected.payload.playing && tab.order > selected.order)) {
        selected = tab;
      }
    }
    return selected?.payload;
  }

  return {
    update(id, payload) {
      const previous = tabs.get(id);
      const order = payload.playing || previous?.payload.playing
        ? ++sequence : (previous?.order ?? 0);
      tabs.set(id, { payload, order });
      return current();
    },
    remove(id) {
      const previous = current();
      tabs.delete(id);
      const selected = current();
      return selected !== previous ? selected : undefined;
    },
  };
}

if (typeof module !== 'undefined') module.exports = { createBridgeAuthority };
