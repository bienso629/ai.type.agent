document.addEventListener('DOMContentLoaded', () => {
    const fileUpload = document.getElementById('file-upload');
    const fileInfo = document.getElementById('file-info');
    const emptyState = document.getElementById('empty-state');
    const emptyPdf = document.getElementById('empty-pdf');
    const documentContainer = document.getElementById('document-container');
    const loadDefaultBtn = document.getElementById('load-default-btn');
    const outlineList = document.getElementById('outline-list');
    const pdfIframe = document.getElementById('pdf-iframe');
    
    // Zoom handling for JSON pane
    let currentZoom = 0.6; // Started a bit smaller to fit split screen better
    const zoomInBtn = document.getElementById('zoom-in');
    const zoomOutBtn = document.getElementById('zoom-out');
    const zoomLevelTxt = document.getElementById('zoom-level');

    zoomInBtn.addEventListener('click', () => setZoom(currentZoom + 0.1));
    zoomOutBtn.addEventListener('click', () => setZoom(currentZoom - 0.1));

    function setZoom(level) {
        if (level < 0.2) level = 0.2;
        if (level > 2.0) level = 2.0;
        currentZoom = level;
        zoomLevelTxt.innerText = `${Math.round(currentZoom * 100)}%`;
        
        document.querySelectorAll('.pdf-page-wrapper').forEach(wrapper => {
            wrapper.style.transform = `scale(${currentZoom})`;
            const scaledHeight = 1131 * currentZoom;
            wrapper.style.marginBottom = `${(scaledHeight - 1131)}px`;
        });
    }

    fileUpload.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onload = (event) => {
                try {
                    const data = JSON.parse(event.target.result);
                    fileInfo.innerHTML = `<p class="success"><i class="fa-solid fa-check"></i> Loaded JSON: ${file.name}</p>`;
                    renderDocument(data);
                } catch (err) {
                    fileInfo.innerHTML = `<p class="error"><i class="fa-solid fa-triangle-exclamation"></i> Invalid JSON file</p>`;
                }
            };
            reader.readAsText(file);
        }
    });

    loadDefaultBtn.addEventListener('click', async () => {
        try {
            // Load JSON
            const response = await fetch('Thong tu 152 ve HO KINH DOANH.mineru.json');
            if (!response.ok) throw new Error('Network response was not ok');
            const data = await response.json();
            fileInfo.innerHTML = `<p class="success"><i class="fa-solid fa-check"></i> Loaded: Thong tu 152...</p>`;
            
            // Render JSON
            renderDocument(data);
            
            // Load PDF into iframe
            emptyPdf.style.display = 'none';
            pdfIframe.style.display = 'block';
            pdfIframe.src = encodeURI('Thong tu 152 ve HO KINH DOANH.pdf') + '#toolbar=0&navpanes=0&scrollbar=0';

        } catch (err) {
            alert('Failed to load local file. If you opened index.html directly, CORS might block this. Use a local server (e.g. python -m http.server).');
        }
    });

    function renderDocument(data) {
        emptyState.style.display = 'none';
        documentContainer.style.display = 'flex';
        documentContainer.innerHTML = '';
        outlineList.innerHTML = '';

        let pages = [];

        data.forEach(item => {
            if (!item.bbox) return;
            const pIdx = item.page_idx || 0;
            if (!pages[pIdx]) {
                pages[pIdx] = [];
            }
            pages[pIdx].push(item);
        });

        // Remove empty pages if any
        pages = pages.filter(p => p && p.length > 0);

        let titleCount = 0;

        pages.forEach((pageData, index) => {
            const pageNum = index + 1;
            
            const wrapper = document.createElement('div');
            wrapper.className = 'pdf-page-wrapper';
            wrapper.id = `page-container-${pageNum}`;
            
            const indicator = document.createElement('div');
            indicator.className = 'page-indicator';
            indicator.innerText = `${pageNum}`;
            wrapper.appendChild(indicator);

            const pageDiv = document.createElement('div');
            pageDiv.className = 'pdf-page';
            
            // Check for page_background item
            const bgItem = pageData.find(item => item.type === 'page_background');
            if (bgItem) {
                const ratio = bgItem.width / bgItem.height;
                pageDiv.style.aspectRatio = `${ratio}`;
                pageDiv.style.backgroundImage = `url('${bgItem.image_url}')`;
            } else {
                pageDiv.style.aspectRatio = `1 / 1.414`; // Fallback to A4
            }
            
            pageData.forEach(item => {
                if (item.type === 'page_background') return; // Skip background metadata
                
                const el = document.createElement('div');
                el.className = `pdf-element ${item.type}`;
                
                const [x0, y0, x1, y1] = item.bbox;
                el.style.left = `${x0 * 100}%`;
                el.style.top = `${y0 * 100}%`;
                el.style.width = `${(x1 - x0) * 100}%`;
                el.style.height = `${(y1 - y0) * 100}%`;
                let estimatedFontSize = 14; // Default fallback
                
                if (item.fitz_font_size) {
                    // fitz_page_width is usually around 595 for A4. We map it to our 800px coordinate system.
                    const fitz_width = item.fitz_page_width || 595;
                    const scale_factor = 800 / fitz_width;
                    estimatedFontSize = item.fitz_font_size * scale_factor;
                    
                    if (item.is_bold) {
                        el.style.fontWeight = 'bold';
                    }
                    if (item.is_italic) {
                        el.style.fontStyle = 'italic';
                    }
                    if (item.fitz_text_indent) {
                        el.style.textIndent = `${item.fitz_text_indent * scale_factor}px`;
                    }
                }
                
                if (item.type === 'title') {
                    el.style.fontWeight = 'bold'; // Fallback for titles
                    el.style.textAlign = 'center';
                } else if (item.type === 'header' || item.type === 'page_number') {
                    el.style.color = '#666';
                }
                
                // Set the font size
                el.style.fontSize = `${estimatedFontSize}px`;
                
                if (item.type === 'title') {
                    if (titleCount < 30) {
                        const li = document.createElement('li');
                        li.innerText = item.content.substring(0, 35) + (item.content.length > 35 ? '...' : '');
                        li.title = item.content;
                        li.onclick = () => {
                            wrapper.scrollIntoView({ behavior: 'smooth' });
                        };
                        outlineList.appendChild(li);
                        titleCount++;
                    }
                } else if (item.type === 'header' || item.type === 'page_number') {
                    estimatedFontSize = 12;
                    el.style.whiteSpace = 'nowrap';
                } else if (item.type === 'text') {
                    estimatedFontSize = Math.max(12, Math.min(estimatedFontSize, 16));
                }

                if (item.type !== 'table') {
                    el.style.fontSize = `${estimatedFontSize}px`;
                }

                if (item.type === 'table') {
                    el.innerHTML = item.content;
                } else if (item.type === 'image' || item.type === 'figure') {
                    if (item.image_url) {
                        el.style.backgroundImage = `url("${encodeURI(item.image_url)}")`;
                        el.style.backgroundSize = 'contain';
                        el.style.backgroundRepeat = 'no-repeat';
                        el.style.backgroundPosition = 'center';
                        // Ẩn text đi vì đã có hình ảnh
                        el.innerHTML = '';
                    } else if (item.content) {
                        el.innerHTML = item.content.replace(/\n/g, '<br>');
                    }
                } else if (item.content) {
                    el.innerHTML = item.content.replace(/\n/g, '<br>');
                }

                pageDiv.appendChild(el);
            });

            wrapper.appendChild(pageDiv);
            documentContainer.appendChild(wrapper);
        });
        
        if (titleCount === 0) {
            outlineList.innerHTML = '<li class="empty-outline">No titles found</li>';
        }

        setZoom(currentZoom);
    }

    const regenerateBtn = document.getElementById('regenerate-btn');
    if (regenerateBtn) {
        regenerateBtn.addEventListener('click', async () => {
            const icon = regenerateBtn.querySelector('i');
            const originalText = regenerateBtn.innerHTML;
            
            icon.classList.add('spin');
            regenerateBtn.disabled = true;
            regenerateBtn.innerHTML = '<i class="fa-solid fa-spinner spin"></i> Processing...';
            
            try {
                const res = await fetch('/regenerate', { method: 'POST' });
                const result = await res.json();
                
                if (res.ok && result.status === 'success') {
                    // Reload default file
                    loadDefaultBtn.click();
                } else {
                    alert('Error regenerating JSON: ' + (result.message || 'Unknown error'));
                }
            } catch (err) {
                alert('Failed to connect to the server. Make sure you are running the custom Python server (python server.py).');
            } finally {
                regenerateBtn.disabled = false;
                regenerateBtn.innerHTML = originalText;
            }
        });
    }

    // OVERLAY TOGGLE
    const overlayToggleBtn = document.getElementById('overlay-toggle-btn');
    if (overlayToggleBtn) {
        overlayToggleBtn.addEventListener('click', () => {
            const wrappers = document.querySelectorAll('.pdf-page-wrapper');
            let isOverlay = false;
            wrappers.forEach(w => {
                w.classList.toggle('overlay-mode');
                if (w.classList.contains('overlay-mode')) isOverlay = true;
            });
            
            if (isOverlay) {
                overlayToggleBtn.style.backgroundColor = 'var(--accent-gradient)';
                overlayToggleBtn.style.color = 'white';
            } else {
                overlayToggleBtn.style.backgroundColor = 'var(--card-bg)';
                overlayToggleBtn.style.color = 'var(--text-primary)';
            }
        });
    }
});
