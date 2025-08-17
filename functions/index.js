const functions = require("firebase-functions");
const nodemailer = require("nodemailer");
const cors = require("cors")({ origin: true });

// Konfiguracja maila — zmień na swoje dane!
const mailTransport = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "paulina.jarmuzek.fachowiec@gmail.com",        // <-- Uzupełnij swoim adresem!
    pass: "upvmohztwbdnflhp",     // <-- Hasło aplikacji Google lub Twoje SMTP!
  },
});

exports.sendOrderEmail = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== "POST") {
      res.status(405).send("Only POST allowed");
      return;
    }

    const { recipientEmail, subject, csvData, fileName } = req.body;
    if (!recipientEmail || !subject || !csvData || !fileName) {
      res.status(400).json({ error: "Brak wymaganych danych" });
      return;
    }

    const mailOptions = {
      from: "Aplikacja Zamówień <paulina.jarmuzek.fachowiec@gmail.com>",
      to: recipientEmail,
      subject,
      text: "W załączniku zamówienie z aplikacji Flutter.",
      attachments: [
        {
          filename: fileName,
          content: Buffer.from(csvData, "utf-8"),
          contentType: "text/csv",
        },
      ],
    };

    try {
      await mailTransport.sendMail(mailOptions);
      res.status(200).send("OK");
    } catch (error) {
      console.error("Mail error:", error);
      res.status(500).json({ error: error.toString() });
    }
  });
});
