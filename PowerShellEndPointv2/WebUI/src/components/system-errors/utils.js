export const formatTime = (ts) => {
    try { return new Date(ts).toLocaleString(); } catch { return ts || '—'; }
};
