package io.github.dmezhnov.knitcalc

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
                    "uninstallPackage" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.error("no_package", "Missing package name", null)
                        } else {
                            requestUninstall(pkg)
                            result.success(null)
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

    /** Opens the system uninstall dialog for [packageName]; the user confirms it. */
    private fun requestUninstall(packageName: String) {
        val intent =
            Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
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
