const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  readSheet: (spreadsheetId, range) => ipcRenderer.invoke('read-sheet', { spreadsheetId, range }),
  writeSheet: (spreadsheetId, range, values) => ipcRenderer.invoke('write-sheet', { spreadsheetId, range, values }),
  getSheetsList: (spreadsheetId) => ipcRenderer.invoke('get-sheets-list', spreadsheetId),
  createSheet: (title) => ipcRenderer.invoke('create-sheet', title)
});