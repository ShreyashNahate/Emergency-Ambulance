const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendDriverNotification = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    const requestData = snap.data();
    if (!requestData) return;

    const driverSnapshot = await admin.firestore()
      .collection("drivers")
      .where("isAvailable", "==", true)
      .get();

    const tokens = [];

    driverSnapshot.forEach(doc => {
      const data = doc.data();
      if (data.fcmToken) tokens.push(data.fcmToken);
    });

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: "🆘 New Ambulance Request",
        body: "Tap to accept a nearby emergency request",
      },
      tokens: tokens,
    };

    const response = await admin.messaging().sendMulticast(message);
    console.log(`✅ Sent to ${response.successCount} drivers.`);
  });
