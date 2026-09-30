-- FCM (Firebase Cloud Messaging) token for push notifications
ALTER TABLE devices ADD COLUMN fcm_token TEXT;
