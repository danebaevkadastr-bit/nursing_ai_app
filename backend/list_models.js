const dotenv = require('dotenv');
dotenv.config();

fetch('https://generativelanguage.googleapis.com/v1alpha/models?key=' + process.env.GEMINI_API_KEY)
  .then(r => r.json())
  .then(d => {
    if (d.models) {
      d.models.forEach(m => {
        if (m.supportedGenerationMethods && m.supportedGenerationMethods.includes('bidiGenerateContent')) {
          console.log('SUPPORTED:', m.name, m.supportedGenerationMethods);
        }
      });
      console.log('Done checking all models.');
    } else {
      console.log('Error:', d);
    }
  });
