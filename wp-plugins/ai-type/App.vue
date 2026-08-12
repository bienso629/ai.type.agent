<template>
    <div class="simple-chatbot" ref="chatbotRef">
        <button id="chatbot-toggle" @click="toggleChat">
            <img loading="lazy" :src="botIcon" />
        </button>

        <div v-if="showChat" class="chatbox">
            <div v-if="!user">
                <div class="chat-status" :style="{ color: isOnline ? 'green' : 'red' }">
                    <img loading="lazy" class="logo" :src="botAvatar" />
                    <div class="label" v-html="isOnline ? t.online : t.offline"></div>
                </div>

                <p class="title">Thông tin liên hệ của bạn:</p>
                <input v-model="registrationForm.name" placeholder="Tên của bạn" />
                <input v-model="registrationForm.email" placeholder="Email" />
                <input v-model="registrationForm.phone" placeholder="Số điện thoại" @keyup.enter="registerUser" />
                <button @click="registerUser" :disabled="isRegistering">
                    {{ isRegistering ? 'Đang kết nối...' : 'Bắt đầu chat' }}
                </button>
            </div>

            <div v-else>
                <div class="chat-status" :style="{ color: isOnline ? 'green' : 'red', display: 'flex', alignItems: 'center' }">
                    <img loading="lazy" class="logo" :src="botAvatar" style="flex-shrink: 0; object-fit: cover;" />
                    <div class="hello" style="display: flex; justify-content: space-between; align-items: center; width: 100%; margin-left: 10px;">
                        <div style="display: flex; flex-direction: column; justify-content: center; gap: 0;">
                            <div class="label" style="display: flex; align-items: center; font-weight: 600; line-height: 1;"><span v-html="isOnline ? t.online : t.offline"></span> &nbsp;{{ user.name }}</div>
                            <div style="font-size: 0.75rem; color: #666; margin-top: 1px; line-height: 1.2;">Chatbot giúp bạn tra cứu và sử dụng Website</div>
                        </div>
                        <span class="btn-logout" @click="out" style="color: #ff6b6b; cursor: pointer; font-size: 0.85rem; font-weight: 600; white-space: nowrap;">Thoát</span>
                    </div>
                </div>

                <div class="messages" ref="messageContainer">
                    <div v-for="msg in messages" class="message-row">
                        <div :class="msg.sender" :key="msg.time">
                            <img loading="lazy" class="avatar" :src="msg.sender === 'user' ? userAvatar : botAvatar" />
                            <div class="text-bubble">
                                <div v-html="msg.text"></div>
                                <small style="font-size: 0.7em; color: #c6c6c6;">{{ msg.time }}</small>
                            </div>
                        </div>
                    </div> <div v-if="isTyping" class="message-row">
                        <div class="assistant">
                            <img loading="lazy" class="avatar" :src="botAvatar" />
                            <div class="text-bubble"><em>{{ t.bot_typing }}</em></div>
                        </div>
                    </div>
                </div>
                <div class="footer" style="padding-top: 20px !important;">
                    <div class="note">Lưu ý: Simple Chatbot có thể mắc lỗi. Hãy kiểm tra các thông tin quan trọng.</div>
                    <div class="chat-input">
                        <input v-model="input" @keyup.enter="sendMessage" :placeholder="t.placeholder" />
                        <button @click="sendMessage">{{ t.send }}</button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>

<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount } from 'vue'
// marked is loaded globally

const user = ref(null)
const chatbotRef = ref(null)
const showChat = ref(false)
const isTyping = ref(false)

window.clbntbToggleChat = () => {
    showChat.value = !showChat.value;
}
const isOnline = ref(true)
const isRegistering = ref(false)
const messages = ref([])
const input = ref('')
const messageContainer = ref(null)

let botIcon = ChatbotSettings.pluginUrl + 'assets/bot.png';
let botAvatar = ChatbotSettings.pluginUrl + 'assets/bot_chat.png';

if (ChatbotSettings.simple_chatbot_image != "") {
    botIcon = ChatbotSettings.simple_chatbot_image;
}

if (ChatbotSettings.simple_chatbot_logo != "") {
    botAvatar = ChatbotSettings.simple_chatbot_logo;
}

const userAvatar = computed(() => {
    return user.value && user.value.email 
        ? `https://api.dicebear.com/7.x/initials/svg?seed=${user.value.email}` 
        : 'https://api.dicebear.com/7.x/initials/svg?seed=';
})

const registrationForm = ref({ name: '', email: '', phone: '' })

const encKey = "simple_chatbot_secure";
const encodeUserData = (data) => {
    const text = encodeURIComponent(JSON.stringify(data));
    let result = '';
    for (let i = 0; i < text.length; i++) {
        result += String.fromCharCode(text.charCodeAt(i) ^ encKey.charCodeAt(i % encKey.length));
    }
    return btoa(result);
};
const decodeUserData = (encoded) => {
    try {
        const text = atob(encoded);
        let result = '';
        for (let i = 0; i < text.length; i++) {
            result += String.fromCharCode(text.charCodeAt(i) ^ encKey.charCodeAt(i % encKey.length));
        }
        return JSON.parse(decodeURIComponent(result));
    } catch(e) {
        return null;
    }
};

const lang = navigator.language.startsWith("vi") ? "vi" : "en"
const i18n = {
    en: {
        send: "Send",
        placeholder: "Type a message...",
        bot_typing: "Typing...",
        error: "An error occurred.",
        online: "<div class='flicker' style='background-color: #28a745 !important; box-shadow: 0 0 8px #28a745 !important; opacity: 1 !important; visibility: visible !important; display: block !important;'></div> Hi, ",
        offline: "<div class='flicker' style='background-color: #dc3545 !important; box-shadow: 0 0 8px #dc3545 !important; opacity: 1 !important; visibility: visible !important; display: block !important;'></div> Bot Offline"
    },
    vi: {
        send: "Gửi",
        placeholder: "Nhập tin nhắn...",
        bot_typing: "Đang trả lời...",
        error: "Đã xảy ra lỗi.",
        online: "<div class='flicker' style='background-color: #28a745 !important; box-shadow: 0 0 8px #28a745 !important; opacity: 1 !important; visibility: visible !important; display: block !important;'></div> Xin chào, ",
        offline: "<div class='flicker' style='background-color: #dc3545 !important; box-shadow: 0 0 8px #dc3545 !important; opacity: 1 !important; visibility: visible !important; display: block !important;'></div> Bot không phản hồi"
    }
}
const t = i18n[lang]

const toggleChat = () => (showChat.value = !showChat.value)

const scrollToBottom = () => {
    nextTick(() => {
        if (messageContainer.value) {
            messageContainer.value.scrollTop = messageContainer.value.scrollHeight
        }
    })
}

const registerUser = async () => {
    let { name, email, phone } = registrationForm.value;
    
    name = name?.trim();
    email = email?.trim();
    phone = phone?.trim();

    if (!name || !email || !phone) return alert("Vui lòng điền đầy đủ thông tin");

    isRegistering.value = true;
    try {
        const res = await fetch(ChatbotSettings.ajax_url + "?action=register_user", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ name, email, phone })
        });

        if (!res.ok) throw new Error("Registration failed");
        const data = await res.json();
        
        if (data && data['error']) {
            alert("Lỗi khi đăng ký người dùng");
        } else {
            user.value = data.user;
            localStorage.setItem('chatbot_user', encodeUserData(data.user));
        }
    } catch (e) {
        alert("Lỗi khi đăng ký người dùng");
    } finally {
        isRegistering.value = false;
    }
}

const out = async () => {
    localStorage.removeItem('chatbot_user');
    user.value = null;
    messages.value = [];
}

const loadChatHistory = async () => {
    if (!ChatbotSettings.is_configured) return;
    if (!user.value || !user.value.thread_id) return;

    try {
        const res = await fetch(`${ChatbotSettings.ajax_url}?action=get_chat_history&thread_id=${user.value.thread_id}`);
        const result = await res.json();

        if (!result.success) throw new Error("Failed to get chat");

        if (result.data.length === 0) {
            console.log("Không có lịch sử chat");
        } else {
            messages.value = result.data.map(msg => ({
                sender: msg[2],
                text: marked.parse(msg[3]),
                time: msg[6] || new Date().toLocaleTimeString()
            }));

            // Đợi Vue render xong rồi scroll
            await nextTick();
            scrollToBottom();
        }
    } catch (err) {
        console.log("Lỗi khi tải lịch sử chat:", err);
    }
};

const sendMessage = async () => {
    const msg = input.value.trim();
    if (!msg) return;

    messages.value.push({
        sender: "user",
        text: msg,
        time: new Date().toLocaleTimeString()
    });

    input.value = "";
    isTyping.value = true;
    scrollToBottom();

    try {
        const res = await fetch(ChatbotSettings.ajax_url + "?action=handle_chat", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message: msg, thread_id: user.value.thread_id })
        });

        if (!res.ok) throw new Error("Bad response");

        const data = await res.json();
        messages.value.push({
            sender: "assistant",
            text: marked.parse(data['reply']['content']),
            time: new Date().toLocaleTimeString()
        });
        isOnline.value = true;
    } catch (e) {
        messages.value.push({
            sender: "assistant",
            text: t.error,
            time: new Date().toLocaleTimeString()
        });
        isOnline.value = false;
    } finally {
        isTyping.value = false;
        scrollToBottom();
    }
}

const handleClickOutside = (event) => {
    const ntbox = document.getElementById('chatbot-ui-ntbox');
    if (showChat.value && chatbotRef.value && !chatbotRef.value.contains(event.target)) {
        if (ntbox && ntbox.contains(event.target)) return;
        showChat.value = false
    }
}

onMounted(() => {
    document.addEventListener('click', handleClickOutside)

    const saved = localStorage.getItem('chatbot_user')
    if (saved) {
        const parsedUser = decodeUserData(saved);
        if (parsedUser) {
            user.value = parsedUser;
            loadChatHistory();
        } else {
            // Old unencrypted data or corrupted data
            localStorage.removeItem('chatbot_user');
        }
    }
    
    // Tự động mở khi load từ fake button
    if (window.chatbotAutoOpen) {
        showChat.value = true;
        window.chatbotAutoOpen = false;
    }
})

onBeforeUnmount(() => {
    document.removeEventListener('click', handleClickOutside)
})
</script>

