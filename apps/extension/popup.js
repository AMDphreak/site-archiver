document.getElementById('archiveBtn').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  chrome.runtime.sendMessage({ action: "archive", url: tab.url });
  document.getElementById('status').innerText = "Request sent to Native Host...";
});
