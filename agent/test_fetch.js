async function run() {
    let start = Date.now();
    const res = await fetch('http://127.0.0.1:54321/api/chat', {
        method: 'POST',
        headers: {
            'Content-Type': 'multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW',
            'x-api-key': '381986yennguyeN'
        },
        body: '------WebKitFormBoundary7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name="prompt"\r\n\r\nHãy kể chuyện dài 200 chữ\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
    });
    
    console.log("Status:", res.status);
    
    const reader = res.body.getReader();
    while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        let diff = (Date.now() - start) / 1000;
        console.log(`[${diff.toFixed(2)}s] CHUNK: ${new TextDecoder().decode(value).length} bytes | ${new TextDecoder().decode(value)}`);
    }
}
run();
