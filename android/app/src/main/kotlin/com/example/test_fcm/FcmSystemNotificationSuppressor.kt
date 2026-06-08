package com.example.test_fcm

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/// Cancels the auto-displayed FCM `notification` tray entry after the Dart
/// background handler shows the richer local notification built from `data`.
///
/// Android always displays the `notification` block when the app is
/// backgrounded/killed. There is no Dart API to prevent that, so we remove the
/// system entry shortly after our data-driven notification is posted.
class FcmSystemNotificationSuppressor : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (!isDualPayload(extras)) return

        val appContext = context.applicationContext
        Handler(Looper.getMainLooper()).postDelayed({
            cancelFcmFallbackNotifications(appContext)
        }, 3500L)
    }

    private fun isDualPayload(extras: android.os.Bundle): Boolean {
        val dataTitle = extras.getString("title")
        val dataBody = extras.getString("body")
        if (dataTitle.isNullOrEmpty() || dataBody.isNullOrEmpty()) return false

        return extras.keySet().any { key -> key.startsWith("gcm.notification.") }
    }

    private fun cancelFcmFallbackNotifications(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            for (statusBarNotification in nm.activeNotifications) {
                val channelId = statusBarNotification.notification.channelId
                if (channelId != null &&
                    channelId.contains("fcm", ignoreCase = true) &&
                    channelId != "my_channel_id_labib"
                ) {
                    nm.cancel(statusBarNotification.tag, statusBarNotification.id)
                    Log.d(TAG, "cancelled FCM tray notification on channel $channelId")
                }
            }
        }

        nm.cancel("FCM_NOTIFICATION", 0)
        nm.cancel(null, 0)
    }

    companion object {
        private const val TAG = "FcmSuppressor"
    }
}
