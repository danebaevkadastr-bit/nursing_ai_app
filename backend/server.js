const { WebSocketServer } = require('ws');
const dotenv = require('dotenv');

dotenv.config();

const port = process.env.PORT || 8080;
const wss = new WebSocketServer({ port });

const QWEN_API_KEY = process.env.QWEN_API_KEY;

const AZURE_KEY = process.env.AZURE_TTS_KEY;
const AZURE_REGION = process.env.AZURE_TTS_REGION || 'eastus';

console.log(`Backend WebSocket Server ishga tushdi (port: ${port})`);

// ─── Suhbat holatlari ────────────────────────────────────────────────────────
// not_started  → Suhbat hali boshlanmagan
// intro        → AI salomlashdi, user tayyor deyishi kutilmoqda
// main_q       → AI asosiy savol berdi
// follow_up_1  → AI birinchi qo'shimcha savol berdi
// follow_up_2  → AI ikkinchi qo'shimcha savol berdi
// grading      → AI baholadi (x/20)
// ────────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Sen hamshiralik fani bo'yicha og'zaki imtihon o'tkazayotgan mehribon va professional hamshira ustazasan.
Suhbatni O'ZBEK TILIDA olib bor.
Qoidalar:
- Javoblarni QISQA va ANIQ qil (2-4 gap)
- Mehribon va rag'batlantiruvchi bo'l
- Savol berganingda faqat BITTA savol ber
- HECH QACHON raqam yoki tartib belgisi (1., 2., 1-, 2- va hokazo) ishlatma
- HECH QACHON ro'yxat (list) shaklida yozma, faqat tabiiy gaplar shaklida yoz
- Bu audio suhbat, shuning uchun faqat og'zaki nutqqa mos iboralar ishlatilsin
- Baholashda aniq x/20 format ishlatish: masalan "15/20"`;

// ─── WAV header yaratish (Azure STT uchun) ───────────────────────────────────
function createWavBuffer(pcmBuffer) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const dataSize = pcmBuffer.length;
    const header = Buffer.alloc(44);

    header.write('RIFF', 0);
    header.writeUInt32LE(36 + dataSize, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20);                      // PCM
    header.writeUInt16LE(numChannels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(sampleRate * numChannels * bitsPerSample / 8, 28);
    header.writeUInt16LE(numChannels * bitsPerSample / 8, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write('data', 36);
    header.writeUInt32LE(dataSize, 40);

    return Buffer.concat([header, pcmBuffer]);
}

// ─── Azure STT ───────────────────────────────────────────────────────────────
async function transcribeAzure(pcmChunks) {
    try {
        const pcmBuffer = Buffer.concat(pcmChunks);
        if (pcmBuffer.length < 3200) {
            console.log('Audio juda qisqa, o\'tkazib yuborildi.');
            return null;
        }

        const wavBuffer = createWavBuffer(pcmBuffer);
        const url = `https://${AZURE_REGION}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=uz-UZ&format=simple`;

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Ocp-Apim-Subscription-Key': AZURE_KEY,
                'Content-Type': 'audio/wav; codecs=audio/pcm; samplerate=16000',
                'Accept': 'application/json'
            },
            body: wavBuffer
        });

        if (!response.ok) {
            const errText = await response.text();
            console.error(`Azure STT xato: ${response.status} - ${errText}`);
            return null;
        }

        const result = await response.json();
        console.log('Azure STT natija:', result);

        if (result.RecognitionStatus === 'Success') {
            return result.DisplayText;
        }
        return null;
    } catch (err) {
        console.error('Azure STT xatosi:', err);
        return null;
    }
}

// ─── Azure TTS ───────────────────────────────────────────────────────────────
async function sendTts(text, ws) {
    try {
        const url = `https://${AZURE_REGION}.tts.speech.microsoft.com/cognitiveservices/v1`;
        const ssml = `<speak version='1.0' xml:lang='uz-UZ'>
            <voice xml:lang='uz-UZ' xml:gender='Female' name='uz-UZ-MadinaNeural'>
                ${text}
            </voice>
        </speak>`;

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Ocp-Apim-Subscription-Key': AZURE_KEY,
                'Content-Type': 'application/ssml+xml',
                'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3'
            },
            body: ssml
        });

        if (!response.ok) {
            const err = await response.text();
            throw new Error(`Azure TTS xatosi: ${response.status} - ${err}`);
        }

        const arrayBuffer = await response.arrayBuffer();
        ws.send(Buffer.from(arrayBuffer));
    } catch (err) {
        console.error('TTS xatosi:', err);
    }
}

// ─── AI javob generatsiyasi (Alibaba Cloud Qwen) ─────────────────────────────
async function generateAiResponse(messages, ws) {
    try {
        if (!QWEN_API_KEY) {
            throw new Error("QWEN_API_KEY Railway variables'da topilmadi!");
        }

        const requestBody = JSON.stringify({
            model: 'qwen-max',
            messages: [
                { role: 'system', content: SYSTEM_PROMPT },
                { role: 'user', content: 'Salom!' },
                ...messages
            ],
            stream: true
        });

        let response = await fetch('https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${QWEN_API_KEY}`,
                'Content-Type': 'application/json'
            },
            body: requestBody
        });

        // Agar 401 (Incorrect API Key) qaytsa, xalqaro endpointni sinab ko'ramiz
        if (response.status === 401) {
            console.log("Xitoy serveridan 401 qaytdi. Xalqaro (International) serverni sinab ko'ramiz...");
            response = await fetch('https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${QWEN_API_KEY}`,
                    'Content-Type': 'application/json'
                },
                body: requestBody
            });
        }

        if (!response.ok) {
            const errText = await response.text();
            throw new Error(`Qwen API xatosi: ${response.status} - ${errText}`);
        }

        let fullResponse = "";
        const reader = response.body;
        let buffer = "";
        const decoder = new TextDecoder();

        for await (const chunk of reader) {
            buffer += decoder.decode(chunk);
            const lines = buffer.split("\n");
            buffer = lines.pop(); // Oxirgi chala qatorni saqlab turamiz

            for (const line of lines) {
                const cleaned = line.trim();
                if (!cleaned || cleaned === "data: [DONE]") continue;
                if (cleaned.startsWith("data: ")) {
                    try {
                        const parsed = JSON.parse(cleaned.slice(6));
                        const text = parsed.choices[0]?.delta?.content || "";
                        if (text) {
                            fullResponse += text;
                            ws.send(JSON.stringify({ type: 'llm_chunk', content: text }));
                        }
                    } catch (e) {
                        // JSON parsing xatolarini tashlab o'tamiz
                    }
                }
            }
        }

        // Generate TTS for the AI response
        if (fullResponse) {
            const escapedText = fullResponse
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&apos;');
            await sendTts(escapedText, ws);
        }

        return fullResponse.trim();
    } catch (err) {
        console.error('Qwen API xatosi:', err.message || err);
        ws.send(JSON.stringify({ type: 'llm_chunk', content: `[XATO]: ${err.message || 'Qwen API ulanish xatosi'}` }));
        return null;
    }
}

// ─── Foydalanuvchi kiritishini qayta ishlash ──────────────────────────────────
async function processUserInput(userText, conversationHistory, sessionState, ws) {
    conversationHistory.push({ role: 'user', content: userText });

    let aiPromptMessages = [...conversationHistory];
    let nextState = sessionState;

    if (sessionState === 'intro') {
        aiPromptMessages[aiPromptMessages.length - 1] = {
            role: 'user',
            content: userText + "\n\n[ICHKI KO'RSATMA: Foydalanuvchi tayyor. Bitta asosiy hamshiralik savolini ber. Savol raqamini aytma.]"
        };
        nextState = 'main_q';
    } else if (sessionState === 'main_q') {
        aiPromptMessages[aiPromptMessages.length - 1] = {
            role: 'user',
            content: userText + "\n\n[ICHKI KO'RSATMA: Birinchi follow-up savol ber. To'g'ri bo'lsa chuqurlashtir, xato bo'lsa muloyimlik bilan yo'nalt.]"
        };
        nextState = 'follow_up_1';
    } else if (sessionState === 'follow_up_1') {
        aiPromptMessages[aiPromptMessages.length - 1] = {
            role: 'user',
            content: userText + "\n\n[ICHKI KO'RSATMA: Ikkinchi va oxirgi follow-up savolni ber.]"
        };
        nextState = 'follow_up_2';
    } else if (sessionState === 'follow_up_2') {
        aiPromptMessages[aiPromptMessages.length - 1] = {
            role: 'user',
            content: userText + "\n\n[ICHKI KO'RSATMA: Barcha javoblarni tahlil qilib 1-20 ball ber. Format: \"Bahoingiz: X/20\". Qisqacha nima to'g'ri/noto'g'ri ekanini ayt. Oxirida \"Yangi savolga o'tamizmi?\" deb so'ra.]"
        };
        nextState = 'grading';
    } else if (sessionState === 'grading') {
        aiPromptMessages = [{
            role: 'user',
            content: userText + "\n\n[ICHKI KO'RSATMA: Foydalanuvchi yangi savolga tayyor. Yangi hamshiralik savolini ber.]"
        }];
        conversationHistory.length = 0;
        conversationHistory.push({ role: 'user', content: userText });
        nextState = 'main_q';
    }

    ws.send(JSON.stringify({ type: 'status', content: 'thinking' }));

    const aiResponse = await generateAiResponse(aiPromptMessages, ws);

    if (aiResponse) {
        conversationHistory.push({ role: 'assistant', content: aiResponse });
        console.log(`[BOT - ${nextState}]: ${aiResponse.substring(0, 100)}...`);
    }

    ws.send(JSON.stringify({ type: 'llm_end', state: nextState }));
    return nextState;
}

// ─── WebSocket server ─────────────────────────────────────────────────────────
wss.on('connection', (ws) => {
    console.log('Yangi mijoz ulandi!');

    let sessionState = 'not_started';
    let conversationHistory = [];
    let isListening = false;
    let audioChunks = [];

    ws.on('message', async (message, isBinary) => {
        if (isBinary) {
            // Audio baytlar keldi (Push-to-Talk paytida)
            if (isListening) {
                audioChunks.push(message);
            }
        } else {
            try {
                const data = JSON.parse(message.toString());
                console.log('Buyruq:', data.type);

                if (data.type === 'start_session') {
                    sessionState = 'intro';
                    conversationHistory = [];

                    ws.send(JSON.stringify({ type: 'status', content: 'thinking' }));

                    const greeting = "Assalomu alaykum! Men AI hamshirasiman. Bugungi imtihonga xush kelibsiz! Tayyormisiz?";
                    // Gemini tarix user dan boshlanishi kerak, shuning uchun juft qo'shamiz
                    conversationHistory.push({ role: 'user', content: 'Assalomu alaykum!' });
                    conversationHistory.push({ role: 'assistant', content: greeting });

                    ws.send(JSON.stringify({ type: 'llm_chunk', content: greeting }));
                    await sendTts(greeting, ws);
                    ws.send(JSON.stringify({ type: 'llm_end', state: sessionState }));

                } else if (data.type === 'start_listening') {
                    isListening = true;
                    audioChunks = [];
                    ws.send(JSON.stringify({ type: 'status', content: 'listening' }));

                } else if (data.type === 'stop_listening') {
                    isListening = false;
                    ws.send(JSON.stringify({ type: 'status', content: 'processing' }));

                    // Azure STT orqali ovozni matnga o'girish
                    const transcript = await transcribeAzure(audioChunks);
                    audioChunks = [];

                    if (transcript) {
                        console.log(`[USER]: ${transcript}`);
                        ws.send(JSON.stringify({ type: 'transcript', content: transcript }));
                        sessionState = await processUserInput(transcript, conversationHistory, sessionState, ws);
                    } else {
                        console.log('STT transcript null qaytardi');
                        ws.send(JSON.stringify({ type: 'status', content: 'idle' }));
                        ws.send(JSON.stringify({ type: 'llm_chunk', content: "Kechirasiz, ovozingizni tushunolmadim. Yana bir bor urinib ko'ring." }));
                        ws.send(JSON.stringify({ type: 'llm_end', state: sessionState }));
                    }
                }
            } catch (e) {
                console.error('Xabar parse xatosi:', e);
            }
        }
    });

    ws.on('close', () => {
        console.log('Mijoz uzildi.');
    });
});
