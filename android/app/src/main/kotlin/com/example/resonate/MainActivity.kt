package com.example.resonate

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.resonate/media_store"
    private val permissionRequestCode = 6167
    private val folderRequestCode = 6168
    private var permissionResult: MethodChannel.Result? = null
    private var folderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAudioPermission" -> requestAudioPermission(result)
                    "pickFolder" -> pickFolder(result)
                    "scanAudio" -> {
                        val folders = (call.argument<List<String>>("folders") ?: emptyList())
                        result.success(scanAudio(folders))
                    }
                    "getAudioSize" -> {
                        val folders = (call.argument<List<String>>("folders") ?: emptyList())
                        result.success(getAudioSize(folders))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun audioPermission(): String = if (Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_AUDIO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasAudioPermission(): Boolean =
        checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(arrayOf(audioPermission()), permissionRequestCode)
    }

    private fun pickFolder(result: MethodChannel.Result) {
        folderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, folderRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequestCode) return
        val result = folderResult ?: return
        folderResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) { }

        val documentId = DocumentsContract.getTreeDocumentId(uri)
        val name = documentId.substringAfter(':').trim('/').substringAfterLast('/').ifBlank { "Device storage" }
        result.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }

    private fun selectedPrefixes(folders: List<String>): Set<String> {
        return folders.mapNotNull { value ->
            try {
                val id = DocumentsContract.getTreeDocumentId(Uri.parse(value))
                val path = id.substringAfter(':', "").trim('/')
                if (path.isEmpty()) "" else "$path/"
            } catch (_: Exception) {
                null
            }
        }.toSet()
    }

    private fun isInSelectedFolder(relativePath: String?, dataPath: String?, prefixes: Set<String>): Boolean {
        if (prefixes.isEmpty()) return false
        if (prefixes.contains("")) return true
        val relative = (relativePath ?: "").trim('/') + "/"
        if (prefixes.any { relative == it || relative.startsWith(it) }) return true
        val absolute = dataPath ?: return false
        return prefixes.any { prefix -> absolute.contains("/$prefix") || absolute.contains(prefix) }
    }

    private fun scanAudio(folders: List<String>): List<Map<String, Any?>> {
        if (!hasAudioPermission() || folders.isEmpty()) return emptyList()
        val prefixes = selectedPrefixes(folders)
        if (prefixes.isEmpty()) return emptyList()
        val songs = mutableListOf<Map<String, Any?>>()
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE,
        )
        if (Build.VERSION.SDK_INT >= 29) projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        if (Build.VERSION.SDK_INT <= 28) projection.add(MediaStore.Audio.Media.DATA)

        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        contentResolver.query(
            collection,
            projection.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dateAdded = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val mime = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val relative = if (Build.VERSION.SDK_INT >= 29) cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH) else -1
            val data = if (Build.VERSION.SDK_INT <= 28) cursor.getColumnIndex(MediaStore.Audio.Media.DATA) else -1

            while (cursor.moveToNext()) {
                val type = cursor.getString(mime) ?: ""
                if (!type.startsWith("audio/")) continue
                val relativePath = if (relative >= 0) cursor.getString(relative) else null
                val dataPath = if (data >= 0) cursor.getString(data) else null
                if (!isInSelectedFolder(relativePath, dataPath, prefixes)) continue

                val mediaId = cursor.getLong(id)
                val uri = ContentUris.withAppendedId(collection, mediaId).toString()
                songs.add(mapOf(
                    "filePath" to uri,
                    "title" to cursor.getString(title),
                    "artist" to cursor.getString(artist),
                    "album" to cursor.getString(album),
                    "duration" to cursor.getLong(duration),
                    "dateAdded" to cursor.getLong(dateAdded),
                ))
            }
        }
        return songs
    }

    private fun getAudioSize(folders: List<String>): Long {
        return scanAudio(folders).sumOf { 0L }
    }
}
