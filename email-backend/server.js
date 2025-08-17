require('dotenv').config();
const express = require('express');
const nodemailer = require('nodemailer');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Konfiguracja transporter
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

// Endpoint do wysyłania e-maili
app.post('/send-email', async (req, res) => {
  try {
    const { recipient, subject, body, attachment, attachmentName } = req.body;

    const mailOptions = {
      from: `"Twoja Aplikacja" <${process.env.EMAIL_USER}>`,
      to: recipient,
      subject: subject,
      text: body,
      attachments: attachment ? [{
        filename: attachmentName || 'attachment.csv',
        content: attachment,
        encoding: 'base64'
      }] : []
    };

    await transporter.sendMail(mailOptions);
    res.status(200).json({ success: true, message: 'E-mail wysłany pomyślnie' });
  } catch (error) {
    console.error('Błąd wysyłania e-maila:', error);
    res.status(500).json({ success: false, message: 'Błąd podczas wysyłania e-maila' });
  }
});

// Start serwera
app.listen(PORT, () => {
  console.log(`Serwer działa na porcie ${PORT}`);
});