package com.Aetherion.Resonate.media

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * Handles runtime audio and notification permission requests for Resonate.
 * Keeps the request-code bookkeeping and result callbacks out of MainActivity.
 */
class PermissionHelper(private val activity: Activity) {

    companion object {
        const val AUDIO_REQUEST_CODE = 6167
        const val NOTIFICATION_REQUEST_CODE = 6169
        const val VISUALIZATION_REQUEST_CODE = 6171
    }

    private var audioResult: MethodChannel.Result? = null
    private var notificationResult: MethodChannel.Result? = null
    private var visualizationResult: MethodChannel.Result? = null

    fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    fun hasAudioPermission(): Boolean =
        activity.checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        audioResult = result
        activity.requestPermissions(arrayOf(audioPermission()), AUDIO_REQUEST_CODE)
    }

    fun requestVisualizationPermission(result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        visualizationResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), VISUALIZATION_REQUEST_CODE)
    }

    fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ) {
        when (requestCode) {
            AUDIO_REQUEST_CODE -> {
                audioResult?.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED,
                )
                audioResult = null
            }
            VISUALIZATION_REQUEST_CODE -> {
                visualizationResult?.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED,
                )
                visualizationResult = null
            }
            NOTIFICATION_REQUEST_CODE -> {
                notificationResult?.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED,
                )
                notificationResult = null
            }
        }
    }
}
