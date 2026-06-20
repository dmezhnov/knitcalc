import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from the environment (CI, via GitHub Secrets) or from
// a local android/key.properties. When neither is present the release build
// falls back to debug keys so `flutter run --release` still works locally.
val keystoreProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) {
            file.inputStream().use { load(it) }
        }
    }

fun signingValue(envKey: String, propKey: String): String? =
    System.getenv(envKey) ?: keystoreProperties.getProperty(propKey)

val releaseStoreFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val hasReleaseSigning = releaseStoreFile != null

android {
    namespace = "io.github.dmezhnov.knitcalc"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "io.github.dmezhnov.knitcalc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the stable release key when configured; otherwise debug keys so
            // local release builds keep working. A consistent key is required for
            // sideload self-updates to install over a previous version.
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    // Flutter's `--split-per-abi` bumps each per-ABI APK's versionCode by an ABI
    // offset (arm64 -> 2000 + base, etc.) — only needed for Google Play
    // multi-APK. We ship an .aab to Play (it gets its own codes) and use the
    // APKs for sideload / IzzyOnDroid, where mixed codes make moving between the
    // universal (base) and a per-ABI build (offset + base) look like a downgrade,
    // so Android refuses the self-update install. Force the base code on every
    // output. This callback registers after the Flutter plugin's, so it wins.
    applicationVariants.all {
        outputs.all {
            (this as com.android.build.gradle.internal.api.ApkVariantOutputImpl)
                .versionCodeOverride = flutter.versionCode
        }
    }
}

flutter {
    source = "../.."
}
