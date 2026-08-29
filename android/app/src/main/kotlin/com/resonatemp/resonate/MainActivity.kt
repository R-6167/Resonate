package com.resonatemp.resonate

import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "resonate/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scan") {
                val list = scanAudioFiles()
                result.success(list)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun scanAudioFiles(): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()

        val uri: Uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DATE_ADDED
        )

        val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

        val cursor: Cursor? = contentResolver.query(uri, projection, null, null, sortOrder)
        cursor?.use {
            val idIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val dateAddedIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)

            while (it.moveToNext()) {
                val id = it.getLong(idIndex)
                val title = it.getString(titleIndex) ?: ""
                val artist = it.getString(artistIndex) ?: ""
                val album = it.getString(albumIndex) ?: ""
                val duration = it.getLong(durationIndex)
                val path = it.getString(dataIndex) ?: ""
                val dateAdded = it.getLong(dateAddedIndex) * 1000 // convert to ms

                val map = mapOf(
                    "id" to id.toString(),
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                    "duration" to duration.toInt(),
                    "path" to path,
                    "date_added" to dateAdded
                )
                results.add(map)
            }
        }

        return results
    }
}
