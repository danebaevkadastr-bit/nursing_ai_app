// ─── Gemini Live API Backend ──────────────────────────────────────────────────
// Bu server Flutter klientlarga WebSocket xizmat ko'rsatadi va
// Gemini Live API ga ulanib, STT + LLM + TTS ni yagona kanalda hal qiladi.
// ─────────────────────────────────────────────────────────────────────────────

const { WebSocketServer } = require('ws');
const WebSocket = require('ws');
const dotenv = require('dotenv');
dotenv.config();

const port = process.env.PORT || 8080;
const wss = new WebSocketServer({ port });
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

const GEMINI_WS_URL = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=${GEMINI_API_KEY}`;

// ─── System Prompt ────────────────────────────────────────────────────────────
const SYSTEM_PROMPT = `Sen hamshiralik fani bo'yicha og'zaki imtihon o'tkazayotgan mehribon va professional hamshira ustazasan.
MUHIM: Faqat va faqat O'ZBEK TILIDA gapir. Hech qachon boshqa tilda gapirim.
Qoidalar:
- Javoblarni QISQA va ANIQ qil (2-4 gap)
- Mehribon va rag'batlantiruvchi bo'l
- HECH QACHON raqam yoki ro'yxat shaklida yozma (1., 2. kabi)
- Bu real-time ovozli suhbat, faqat tabiiy gaplar ishlatilsin
- Baholashda "X/20" formatidan foydalan

Imtihon tartibi (SHU TARTIBDA AMALGA OSHIR):
Bosqich 1 (SALOMLASHISH): O'zingni tanishtir va talabani xush kelibsiz de, tayyormisiz deb so'ra.
Bosqich 2 (ASOSIY SAVOL): Talaba tayyor bo'lgandan so'ng, BITTA asosiy hamshiralik klinik savolini ber. Masalan: "Gipoglikemiyada hemshira qanday harakat qiladi?", "Bosim yarasi profilaktikasi qanday amalga oshiriladi?" kabi amaliy savol.
Bosqich 3 (BIRINCHI KUZATISH): Javobni tinglab, chuqurlashtiruvchi bitta savol ber.
Bosqich 4 (IKKINCHI KUZATISH): Yana bitta oxirgi kuzatish savolini ber.
Bosqich 5 (BAHOLASH): Barcha javoblarni tahlil qilib X/20 ball ber. "Yangi savolga o'tamizmi?" deb so'ra.`;

// ─── WAV yaratish (Gemini 24kHz PCM uchun) ───────────────────────────────────
function createWavBuffer(pcmBuffer, sampleRate = 24000) {
    const numChannels = 1;
    const bitsPerSample = 16;
    const dataSize = pcmBuffer.length;
    const header = Buffer.alloc(44);
    header.write('RIFF', 0);
    header.writeUInt32LE(36 + dataSize, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20);              // PCM
    header.writeUInt16LE(numChannels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(sampleRate * numChannels * bitsPerSample / 8, 28);
    header.writeUInt16LE(numChannels * bitsPerSample / 8, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write('data', 36);
    header.writeUInt32LE(dataSize, 40);
    return Buffer.concat([header, pcmBuffer]);
}

// ─── Suhbat holatlari ─────────────────────────────────────────────────────────
const STATE_MAP = {
    'not_started': 'intro',
    'intro': 'main_q',
    'main_q': 'follow_up_1',
    'follow_up_1': 'follow_up_2',
    'follow_up_2': 'grading',
    'grading': 'main_q'
};

// ─── WebSocket Server ─────────────────────────────────────────────────────────
wss.on('connection', (clientWs) => {
    console.log('[Live] Flutter klient ulandi');

    let geminiWs = null;
    let isListening = false;
    let sessionState = 'not_started';
    let geminiAudioChunks = [];
    let geminiTextBuffer = '';
    let setupComplete = false;
    let keepAliveInterval = null;

    // ─── Gemini Live ga ulanish ───────────────────────────────────────────────
    function connectToGemini(onReadyCallback) {
        if (!GEMINI_API_KEY) {
            clientWs.send(JSON.stringify({ type: 'llm_chunk', content: '[XATO]: GEMINI_API_KEY topilmadi!' }));
            return;
        }

        geminiWs = new WebSocket(GEMINI_WS_URL);

        geminiWs.on('open', () => {
            console.log('[Live] Gemini ga ulandi, setup yuborilmoqda...');

            const setupMsg = {
                setup: {
                    model: 'models/gemini-2.5-flash-native-audio-latest',
                    generationConfig: {
                        responseModalities: ['AUDIO'],
                        speechConfig: {
                            voiceConfig: {
                                prebuiltVoiceConfig: { voiceName: 'Puck' }
                            }
                        }
                    },
                    realtimeInputConfig: {
                        automaticActivityDetection: {}
                    },
                    systemInstruction: {
                        parts: [{ text: SYSTEM_PROMPT }]
                    },
                    outputAudioTranscription: {}  // AI gapini matn sifatida ham ber
                }
            };
            geminiWs.send(JSON.stringify(setupMsg));

            // Keep-alive: har 4 daqiqada bo'sh xabar
            keepAliveInterval = setInterval(() => {
                if (geminiWs?.readyState === WebSocket.OPEN) {
                    geminiWs.send(JSON.stringify({
                        clientContent: { turns: [], turnComplete: false }
                    }));
                }
            }, 4 * 60 * 1000);
        });

        geminiWs.on('message', (rawData) => {
            try {
                const msg = JSON.parse(rawData.toString());

                // ─── Setup muvaffaqiyatli ─────────────────────────────────────
                if (msg.setupComplete !== undefined) {
                    console.log('[Live] Gemini setup tayyor ✓');
                    setupComplete = true;
                    if (onReadyCallback) onReadyCallback();
                    return;
                }

                const sc = msg.serverContent;
                if (!sc) return;

                // ─── Audio va matn qismlari ───────────────────────────────────
                if (sc.modelTurn?.parts) {
                    for (const part of sc.modelTurn.parts) {
                        // Audio chunk (PCM 24kHz, base64)
                        if (part.inlineData?.mimeType === 'audio/pcm;rate=24000') {
                            const pcmBuf = Buffer.from(part.inlineData.data, 'base64');
                            geminiAudioChunks.push(pcmBuf);
                        }
                    }
                }

                // ─── AI matn transkripsiyasi ──────────────────────────────────
                if (sc.outputTranscription?.text) {
                    const text = sc.outputTranscription.text;
                    geminiTextBuffer += text;
                    clientWs.send(JSON.stringify({ type: 'llm_chunk', content: text }));
                }

                // ─── Gemini turn tugadi ───────────────────────────────────────
                if (sc.turnComplete === true) {
                    console.log(`[Live] Gemini turn tugadi. Audio chunks: ${geminiAudioChunks.length}, matn uzunligi: ${geminiTextBuffer.length}`);

                    // To'liq audio ni WAV ga o'rab Flutter ga yuboramiz
                    if (geminiAudioChunks.length > 0) {
                        const fullPcm = Buffer.concat(geminiAudioChunks);
                        const wavBuffer = createWavBuffer(fullPcm, 24000);
                        console.log(`[Live] WAV yuborilmoqda: ${wavBuffer.length} bayt`);
                        clientWs.send(wavBuffer);
                        geminiAudioChunks = [];
                    }

                    // State o'tish
                    sessionState = STATE_MAP[sessionState] || sessionState;
                    geminiTextBuffer = '';

                    clientWs.send(JSON.stringify({ type: 'llm_end', state: sessionState }));
                }

                // ─── Foydalanuvchi nutqi transkripsiyasi ─────────────────────
                if (sc.inputTranscription?.text) {
                    clientWs.send(JSON.stringify({
                        type: 'transcript',
                        content: sc.inputTranscription.text
                    }));
                }

            } catch (e) {
                // JSON bo'lmagan binary xabarlar (odatda bo'lmaydi)
            }
        });

        geminiWs.on('close', (code) => {
            console.log(`[Live] Gemini ulanishi yopildi (kod: ${code})`);
            setupComplete = false;
            clearInterval(keepAliveInterval);

            // 1006/1008/1011 → qayta ulanish
            if (code === 1006 || code === 1008 || code === 1011) {
                console.log('[Live] Qayta ulanish 2 soniyadan keyin...');
                setTimeout(() => {
                    if (clientWs.readyState === WebSocket.OPEN) {
                        connectToGemini(null);
                    }
                }, 2000);
            }
        });

        geminiWs.on('error', (err) => {
            console.error('[Live] Gemini xatosi:', err.message);
            clientWs.send(JSON.stringify({ type: 'llm_chunk', content: `[XATO]: ${err.message}` }));
        });
    }

    // ─── Flutter dan kelgan xabarlar ─────────────────────────────────────────
    clientWs.on('message', (message, isBinary) => {
        // Binary = audio chunk (PCM 16kHz)
        if (isBinary) {
            if (isListening && geminiWs?.readyState === WebSocket.OPEN) {
                const base64Audio = message.toString('base64');
                geminiWs.send(JSON.stringify({
                    realtimeInput: {
                        mediaChunks: [{
                            mimeType: 'audio/pcm;rate=16000',
                            data: base64Audio
                        }]
                    }
                }));
            }
            return;
        }

        // Matnli buyruqlar
        try {
            const data = JSON.parse(message.toString());
            console.log('[Live] Buyruq:', data.type);

            // ─── Suhbatni boshlash ────────────────────────────────────────────
            if (data.type === 'start_session') {
                sessionState = 'not_started';
                geminiAudioChunks = [];
                geminiTextBuffer = '';

                clientWs.send(JSON.stringify({ type: 'status', content: 'thinking' }));

                // Gemini ga ulan va tayyor bo'lgach salomlashishni ishga tushir
                connectToGemini(() => {
                    setTimeout(() => {
                        if (geminiWs?.readyState === WebSocket.OPEN) {
                            geminiWs.send(JSON.stringify({
                                clientContent: {
                                    turns: [{
                                        role: 'user',
                                        parts: [{ text: 'Salom, men imtihonga keldim.' }]
                                    }],
                                    turnComplete: true
                                }
                            }));
                        }
                    }, 300); // Setup to'liq qayta ishlangach
                });
            }

            // ─── Tinglashni boshlash ──────────────────────────────────────────
            else if (data.type === 'start_listening') {
                isListening = true;
                geminiAudioChunks = [];
                // VAD avtomatik aniqlaydi — activityStart shart emas
                clientWs.send(JSON.stringify({ type: 'status', content: 'listening' }));
            }

            // ─── Tinglashni to'xtatish ────────────────────────────────────────
            else if (data.type === 'stop_listening') {
                isListening = false;
                // VAD o'zi turn_complete ni boshqaradi
                clientWs.send(JSON.stringify({ type: 'status', content: 'idle' }));
            }

        } catch (e) {
            console.error('[Live] Xabar parse xatosi:', e.message);
        }
    });

    clientWs.on('close', () => {
        console.log('[Live] Flutter klient uzildi');
        clearInterval(keepAliveInterval);
        geminiWs?.close();
    });

    clientWs.on('error', (err) => {
        console.error('[Live] Klient xatosi:', err.message);
    });
});

console.log(`[Live] Gemini Live Backend tayyor (port: ${port})`);
