package com.mcbane23.guitarlearn

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Lets the user choose a whole folder of song files (channel `guitar_learn/files`).
 *
 * `pickFolder` opens the system folder chooser and lists the song files in the
 * folder and its subfolders, without reading them. `readFile` then reads one
 * file at a time, so a big folder never has to fit in memory at once.
 * Uses the Storage Access Framework, so no storage permission is needed.
 */
class SongFolders(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val REQUEST_CODE = 4711
        private const val MAX_FILES = 500
        private const val MAX_DEPTH = 6
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var extensions: Set<String> = emptySet()

    init {
        MethodChannel(messenger, "guitar_learn/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> {
                    if (pending != null) {
                        result.error("busy", "The folder chooser is already open", null)
                        return@setMethodCallHandler
                    }
                    extensions = (call.argument<List<String>>("extensions") ?: emptyList()).map { it.lowercase() }.toSet()
                    try {
                        pending = result
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_CODE)
                    } catch (e: ActivityNotFoundException) {
                        // Many Android TVs have no folder chooser.
                        pending = null
                        result.error("unavailable", e.message, null)
                    }
                }
                "readFile" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    io.execute {
                        try {
                            val bytes = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                                ?: throw IllegalStateException("No data")
                            main.post { result.success(bytes) }
                        } catch (e: Throwable) {
                            main.post { result.error("read", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Called from the activity; true when this was the folder chooser's answer. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        io.execute {
            try {
                val listing = list(tree)
                main.post { result.success(listing) }
            } catch (e: Throwable) {
                main.post { result.error("list", e.message, null) }
            }
        }
        return true
    }

    fun shutdown() {
        io.shutdown()
    }

    private fun list(tree: Uri): Map<String, Any> {
        val resolver = activity.contentResolver
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        var folderName = ""
        resolver.query(
            DocumentsContract.buildDocumentUriUsingTree(tree, rootId),
            arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { if (it.moveToFirst()) folderName = it.getString(0) ?: "" }

        val files = ArrayList<Map<String, Any>>()
        var otherFiles = 0
        var tooMany = false
        // Breadth first, so the files at the top of the folder come first.
        val queue = ArrayDeque<Triple<String, String, Int>>() // document id, path inside the folder, depth
        queue.add(Triple(rootId, "", 0))
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE)
        while (queue.isNotEmpty()) {
            val (dirId, prefix, depth) = queue.removeFirst()
            resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, dirId), columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: continue
                    if (name.startsWith(".")) continue // hidden files and folders
                    if (c.getString(2) == Document.MIME_TYPE_DIR) {
                        if (depth < MAX_DEPTH) queue.add(Triple(id, "$prefix$name/", depth + 1))
                        continue
                    }
                    if (name.substringAfterLast('.', "").lowercase() !in extensions) {
                        otherFiles++
                        continue
                    }
                    if (files.size >= MAX_FILES) {
                        tooMany = true
                        continue
                    }
                    files.add(
                        mapOf(
                            "name" to "$prefix$name",
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                            "size" to (if (c.isNull(3)) -1L else c.getLong(3)),
                        ),
                    )
                }
            }
        }
        return mapOf("folder" to folderName, "files" to files, "otherFiles" to otherFiles, "tooMany" to tooMany, "limit" to MAX_FILES)
    }
}
