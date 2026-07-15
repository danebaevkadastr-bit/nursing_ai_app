const WebSocket = require('ws');
const dotenv = require('dotenv');
dotenv.config();

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const url = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=${GEMINI_API_KEY}`;

const ws = new WebSocket(url);

ws.on('open', () => {
    console.log('Connected. Sending setup...');
    ws.send(JSON.stringify({
        setup: {
            model: 'models/gemini-2.5-flash-native-audio-latest',
            generationConfig: {
                responseModalities: ['AUDIO'],
                thinkingConfig: { thinkingLevel: 'minimal' },
                speechConfig: {
                    languageCode: 'de-DE',
                    voiceConfig: {
                        prebuiltVoiceConfig: { voiceName: 'Puck' }
                    }
                }
            },
            systemInstruction: {
                parts: [{ text: "Hello" }]
            }
        }
    }));
});

ws.on('message', (data) => {
    console.log('Received:', data.toString());
});

ws.on('close', (code, reason) => {
    console.log(`Closed: ${code} - ${reason}`);
});

ws.on('error', (err) => {
    console.error('Error:', err);
});
