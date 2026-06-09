package io.github.dmezhnov.knitcalc

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "knitcalc/android_update"

    // Under Waydroid render into a TextureView instead of the default
    // FlutterSurfaceView: its hardware composer renders the dedicated surface
    // overlay into an undersized buffer and bilinearly upscales it, which blurs the
    // whole UI, whereas a TextureView is composited through the normal View pipeline
    // and stays sharp. TextureView is slower, so everywhere else (real devices) we
    // keep the default surface mode.
    override fun getRenderMode(): RenderMode =
        if (isWaydroid()) RenderMode.texture else RenderMode.surface

    /** Waydroid stamps "waydroid" into its product build identifiers. */
    private fun isWaydroid(): Boolean =
        listOf(Build.BRAND, Build.MANUFACTURER, Build.DEVICE, Build.PRODUCT)
            .any { it.contains("waydroid", ignoreCase = true) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstallerPackageName" -> result.success(installerPackageName())
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "Missing apk path", null)
                        } else {
                            installApk(path)
                            result.success(null)
                        }
                    }
                    "isPackageInstalled" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.error("no_package", "Missing package name", null)
                        } else {
                            result.success(isPackageInstalled(pkg))
                        }
                    }
                    "saveImageToGallery" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                        if (bytes == null || name == null) {
                            result.error("bad_args", "Missing image bytes or name", null)
                        } else {
                            result.success(saveImageToGallery(bytes, name))
                        }
                    }
                    "uninstallPackage" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.error("no_package", "Missing package name", null)
                        } else {
                            // Returns a short diagnostic string so a silent no-op
                            // (uninstaller resolves but nothing shows) is still
                            // observable on-device — the Dart side surfaces it.
                            result.success(requestUninstall(pkg))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** The package that installed this app, used to detect the channel. */
    private fun installerPackageName(): String? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }

    /** Whether [packageName] is installed (must be listed in the manifest <queries>). */
    private fun isPackageInstalled(packageName: String): Boolean =
        try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

    /** Opens the system uninstall dialog for [packageName]; the user confirms it.
     *  Launched from this Activity's context, so no FLAG_ACTIVITY_NEW_TASK.
     *
     *  Returns a short diagnostic string describing the outcome:
     *    "not_installed"        — the package is no longer present
     *    "no_handler"           — no activity resolved either uninstall intent
     *    "launched:<action>->…" — startActivity succeeded for that component
     *    "error:<action>:<ex>…" — startActivity threw for that action
     *  Tries ACTION_DELETE first, then the deprecated ACTION_UNINSTALL_PACKAGE,
     *  since some OEM ROMs only honour one of them. */
    private fun requestUninstall(packageName: String): String {
        if (!isPackageInstalled(packageName)) {
            return "not_installed"
        }
        val uri = Uri.fromParts("package", packageName, null)
        for (action in listOf(Intent.ACTION_DELETE, Intent.ACTION_UNINSTALL_PACKAGE)) {
            val intent = Intent(action, uri)
            val handler = intent.resolveActivity(packageManager) ?: continue
            return try {
                startActivity(intent)
                "launched:$action->${handler.flattenToShortString()}"
            } catch (e: Exception) {
                "error:$action:${e.javaClass.simpleName}:${e.message}"
            }
        }
        return "no_handler"
    }

    /** Saves [bytes] as a JPEG into the device gallery (Pictures/KnitCalc) via
     *  MediaStore. On API 29+ this needs no permission; on older versions it
     *  relies on WRITE_EXTERNAL_STORAGE (declared maxSdkVersion=28). Returns
     *  whether the image was written. */
    private fun saveImageToGallery(bytes: ByteArray, displayName: String): Boolean {
        val collection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }

        val values =
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        "${Environment.DIRECTORY_PICTURES}/KnitCalc",
                    )
                    // Hide the row until the bytes are fully written.
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

        val uri = contentResolver.insert(collection, values) ?: return false

        return try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            true
        } catch (_: Exception) {
            // Roll back the placeholder row so a failed write leaves no empty entry.
            contentResolver.delete(uri, null, null)
            false
        }
    }

    /** Hands a downloaded APK to the system package installer. */
    private fun installApk(path: String) {
        val file = File(path)
        val uri: Uri =
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

        val intent =
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        startActivity(intent)
    }
}
