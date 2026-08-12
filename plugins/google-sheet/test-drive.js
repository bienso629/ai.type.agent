const path = require('path');
const { google } = require('googleapis');

async function test() {
  try {
    const auth = new google.auth.GoogleAuth({
      keyFile: path.join(__dirname, 'credentials.json'),
      scopes: ['https://www.googleapis.com/auth/spreadsheets', 'https://www.googleapis.com/auth/drive'],
    });
    const authClient = await auth.getClient();
    const sheets = google.sheets({ version: 'v4', auth: authClient });
    const drive = google.drive({ version: 'v3', auth: authClient });

    console.log("Listing files to free up space...");
    let files = [];
    let pageToken = null;
    do {
      const res = await drive.files.list({
        pageSize: 100,
        fields: 'nextPageToken, files(id, name, trashed)',
        q: 'trashed=true or trashed=false',
        pageToken: pageToken
      });
      files = files.concat(res.data.files);
      pageToken = res.data.nextPageToken;
    } while (pageToken);

    console.log(`Found ${files.length} files. Deleting...`);
    for (let file of files) {
      try {
        await drive.files.delete({ fileId: file.id });
        console.log(`Deleted: ${file.name}`);
      } catch (e) {
        console.log(`Failed to delete ${file.name}: ${e.message}`);
      }
    }
    console.log("Cleanup complete!");
  } catch (error) {
    console.error("Outer Error:", error.message);
  }
}

test();
