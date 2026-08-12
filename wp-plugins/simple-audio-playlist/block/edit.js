(function (wp) {
    const { registerBlockType } = wp.blocks;
    const { TextControl } = wp.components;
    const { useBlockProps } = wp.blockEditor;
    const { createElement } = wp.element;

    registerBlockType("simple-audio-playlist/block", {
        title: "Simple Audio Playlist",
        icon: "format-audio",
        category: "media",
        attributes: {
            ids: {
                type: "string",
                default: ""
            }
        },
        edit: ({ attributes, setAttributes }) => {
            const blockProps = useBlockProps();

            return createElement("div", blockProps, [
                createElement(TextControl, {
                    key: "input",
                    label: "Nhập danh sách audio (mỗi item: URL|Tiêu đề, cách nhau bằng dấu phẩy)",
                    value: attributes.ids,
                    onChange: (value) => setAttributes({ ids: value })
                }),
                createElement("p", { style: { fontSize: "13px", color: "#666" } }, "Ví dụ: https://example.com/audio1.mp3|Bài 1, https://example.com/audio2.mp3|Bài 2")
            ]);
        },
        save: () => {
            return null; // Render bằng PHP
        }
    });
})(window.wp);
