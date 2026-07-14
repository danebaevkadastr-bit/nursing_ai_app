const { WebSocketServer } = require('ws');
const { createClient } = require('@deepgram/sdk');
const Groq = require('groq-sdk');
const dotenv = require('dotenv');

dotenv.config();

const port = process.env.PORT || 8080;
const wss = new WebSocketServer({ port });
const deepgram = createClient(process.env.DEEPGRAM_API_KEY);
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

console.log(`Backend WebSocket Server ishga tushdi (port: ${port})`);

// ─── Suhbat holatlari ────────────────────────────────────────────────────────
// intro        → AI salomlashadi, user tayyor deydi
// main_q       → AI asosiy savol berdi, user javob kutilmoqda
// follow_up_1  → AI birinchi qo'shimcha savol berdi
// follow_up_2  → AI ikkinchi qo'shimcha savol berdi
// grading      → AI baholaydi (x/20), keyin yangi savolga o'tadi
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Sen hamshiralik fani bo'yicha og'zaki imtihon o'tkazayotgan mehribon va professional hamshira ustazasan. 
Suhbatni O'ZBEK TILIDA olib bor. 
Qoidalar:
- Javoblarni QISQA va ANIQ qil (2-4 gap)
- Mehribon va rag'batlantiruvchi bo'l
- Savol berganingda faqat BITTA savol ber
- Baholashda aniq x/20 format ishlatish: masalan "15/20"`;

wss.on('connection', (ws) => {
    console.log("Yangi mijoz ulandi!");

    // ─── Holat o'zgaruvchilari ───────────────────────────────────────────────
    let sessionState = 'not_started'; // not_started | intro | main_q | follow_up_1 | follow_up_2 | grading
    let conversationHistory = [];
    let isListening = false;
    let sttConnection = null;
    let audioBuffer = [];

    // ─── STT yaratish funksiyasi ─────────────────────────────────────────────
    function createSttConnection() {
        if (sttConnection) {
            try { sttConnection.finish(); } catch(e) {}
            sttConnection = null;
        }

        const stt = deepgram.listen.live({
            model: 'nova-2',
            language: 'ru', // O'zbek yo'q, rus eng yaqin
            smart_format: true,
            endpointing: 500,
            interim_results: false,
            utterance_end_ms: 1000,
        });

        stt.on('open', () => {
            console.log('Deepgram STT ulandi.');
            // Buferdagi audio ma'lumotlarni yuborish
            if (audioBuffer.length > 0) {
                for (const chunk of audioBuffer) {
                    if (stt.getReadyState() === 1) stt.send(chunk);
                }
                audioBuffer = [];
            }
        });

        stt.on('Results', async (data) => {
            const transcript = data.channel?.alternatives[0]?.transcript;
            if (transcript && transcript.trim() && data.is_final) {
                console.log(`[USER]: ${transcript}`);
                ws.send(JSON.stringify({ type: 'transcript', content: transcript }));
                await processUserInput(transcript);
            }
        });

        stt.on('UtteranceEnd', async (data) => {
            // Utterance tugadi - bu signal bilan ham ishlov berish mumkin
        });

        stt.on('error', (err) => {
            console.error("Deepgram STT xatosi:", err);
            ws.send(JSON.stringify({ type: 'status', content: 'stt_error' }));
        });

        stt.on('close', () => {
            console.log('Deepgram STT yopildi.');
        });

        return stt;
    }

    // ─── AI javob generatsiyasi ──────────────────────────────────────────────
    async function generateAiResponse(messages) {
        try {
            const stream = await groq.chat.completions.create({
                messages: [
                    { role: 'system', content: SYSTEM_PROMPT },
                    ...messages
                ],
                model: 'llama3-8b-8192',
                stream: true,
                max_tokens: 300,
            });

            let fullResponse = "";
            let sentenceBuffer = "";

            for await (const chunk of stream) {
                const content = chunk.choices[0]?.delta?.content || "";
                fullResponse += content;
                sentenceBuffer += content;

                ws.send(JSON.stringify({ type: 'llm_chunk', content: content }));

                // Gapni TTS ga berish (punkt belgisida)
                const shouldFlush = /[.?!]\s/.test(sentenceBuffer) ||
                    /[.?!]$/.test(sentenceBuffer) ||
                    sentenceBuffer.length > 80;

                if (shouldFlush) {
                    const textToSpeak = sentenceBuffer.trim();
                    sentenceBuffer = "";
                    if (textToSpeak.length > 3) {
                        await sendTts(textToSpeak, ws);
                    }
                }
            }

            // Qolgan matnni TTS ga berish
            if (sentenceBuffer.trim().length > 3) {
                await sendTts(sentenceBuffer.trim(), ws);
            }

            return fullResponse.trim();
        } catch (err) {
            console.error("Groq xatosi:", err);
            return null;
        }
    }

    // ─── TTS yuborish ────────────────────────────────────────────────────────
    async function sendTts(text, ws) {
        try {
            const ttsResponse = await deepgram.speak.request(
                { text },
                { model: 'aura-asteria-en' }
            );
            const audioStream = await ttsResponse.getStream();
            if (audioStream) {
                const reader = audioStream.getReader();
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    ws.send(value);
                }
            }
        } catch (err) {
            console.error("TTS xatosi:", err);
        }
    }

    // ─── Foydalanuvchi kiritishini qayta ishlash ─────────────────────────────
    async function processUserInput(userText) {
        conversationHistory.push({ role: 'user', content: userText });

        let aiPromptMessages = [...conversationHistory];
        let nextState = sessionState;

        if (sessionState === 'intro') {
            // User salomlashdi → AI asosiy savolni beradi
            aiPromptMessages.push({
                role: 'user',
                content: '[ICHKI KO\'RSATMA: Foydalanuvchi tayyor. Endi bitta asosiy hamshiralik savolini ber. Savol raqamini aytma.]'
            });
            nextState = 'main_q';
        } else if (sessionState === 'main_q') {
            // User asosiy savolga javob berdi → Birinchi qo'shimcha savol
            aiPromptMessages.push({
                role: 'user',
                content: '[ICHKI KO\'RSATMA: Foydalanuvchi asosiy savolga javob berdi. Birinchi qo\'shimcha (follow-up) savol ber. Agar javob to\'g\'ri bo\'lsa, chuqurlashtir; xato bo\'lsa, muloyimlik bilan yo\'nalt.]'
            });
            nextState = 'follow_up_1';
        } else if (sessionState === 'follow_up_1') {
            // User birinchi follow-up ga javob berdi → Ikkinchi qo'shimcha savol
            aiPromptMessages.push({
                role: 'user',
                content: '[ICHKI KO\'RSATMA: Foydalanuvchi javob berdi. Ikkinchi va oxirgi qo\'shimcha (follow-up) savolni ber.]'
            });
            nextState = 'follow_up_2';
        } else if (sessionState === 'follow_up_2') {
            // User ikkinchi follow-up ga javob berdi → Baholash
            aiPromptMessages.push({
                role: 'user',
                content: '[ICHKI KO\'RSATMA: Barcha javoblarni tahlil qilib, talabaga 1-20 shkalada ball ber. Format: "Bahoingiz: X/20". Qisqacha nima to\'g\'ri/noto\'g\'ri ekanini ayt. Oxirida "Yangi savolga o\'tamizmi?" deb so\'ra.]'
            });
            nextState = 'grading';
        } else if (sessionState === 'grading') {
            // User yangi savolga rozi → Yangi mavzu boshlash
            aiPromptMessages = [
                {
                    role: 'user',
                    content: '[ICHKI KO\'RSATMA: Foydalanuvchi yangi savolga tayyor. Yangi, boshqa hamshiralik savolini ber.]'
                }
            ];
            conversationHistory = [{ role: 'user', content: userText }];
            nextState = 'main_q';
        }

        ws.send(JSON.stringify({ type: 'status', content: 'thinking' }));

        const aiResponse = await generateAiResponse(aiPromptMessages);

        if (aiResponse) {
            conversationHistory.push({ role: 'assistant', content: aiResponse });
            sessionState = nextState;
            console.log(`[BOT - ${sessionState}]: ${aiResponse.substring(0, 100)}...`);
        }

        ws.send(JSON.stringify({ type: 'llm_end', state: sessionState }));
    }

    // ─── WebSocket xabarlari ─────────────────────────────────────────────────
    ws.on('message', async (message) => {
        if (Buffer.isBuffer(message)) {
            // Audio ma'lumotlar
            if (isListening && sttConnection) {
                if (sttConnection.getReadyState() === 1) {
                    sttConnection.send(message);
                } else {
                    audioBuffer.push(message);
                }
            }
        } else {
            // Matnli buyruqlar
            try {
                const data = JSON.parse(message.toString());
                console.log("Buyruq:", data.type);

                if (data.type === 'start_session') {
                    // Birinchi marta suhbat boshlanishi
                    sessionState = 'intro';
                    conversationHistory = [];

                    ws.send(JSON.stringify({ type: 'status', content: 'thinking' }));

                    // AI salomlashadi
                    const greeting = "Assalomu alaykum! Men AI hamshirasiman. Bugungi imtihonga xush kelibsiz! Tayyormisiz?";
                    conversationHistory.push({ role: 'assistant', content: greeting });

                    ws.send(JSON.stringify({ type: 'llm_chunk', content: greeting }));
                    await sendTts(greeting, ws);
                    ws.send(JSON.stringify({ type: 'llm_end', state: sessionState }));

                } else if (data.type === 'start_listening') {
                    // Push-to-talk: user mikrofon tugmasini bosdi
                    isListening = true;
                    audioBuffer = [];
                    sttConnection = createSttConnection();
                    ws.send(JSON.stringify({ type: 'status', content: 'listening' }));

                } else if (data.type === 'stop_listening') {
                    // Push-to-talk: user tugmani qo'yib yubordi
                    isListening = false;
                    if (sttConnection) {
                        try {
                            sttConnection.finish();
                        } catch(e) {}
                        sttConnection = null;
                    }
                    ws.send(JSON.stringify({ type: 'status', content: 'processing' }));
                }
            } catch (e) {
                console.error("Xabar parse xatosi:", e);
            }
        }
    });

    ws.on('close', () => {
        console.log("Mijoz uzildi.");
        if (sttConnection) {
            try { sttConnection.finish(); } catch(e) {}
        }
    });
});
